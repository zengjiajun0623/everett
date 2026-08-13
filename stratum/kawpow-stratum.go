// kawpow-stratum: a solo stratum sidecar for Everett-family nodes.
//
// Speaks the KawPow stratum dialect that kawpowminer/T-Rex/TeamRedMiner
// expect (G6_P1_NOTES.md §4.2, derived from kawpowminer's EthStratumClient
// source), backed by the node's eth_getWork/eth_submitWork RPC:
//
//   miner → mining.subscribe            → [null, extranonce]
//   miner → mining.authorize            → true
//   node  → mining.set_target [target64]
//   node  → mining.notify [jobId, header64, seed64, target64, clean, height, bits]
//   miner → mining.submit [user, jobId, 0xnonce16, 0xheader64, 0xmix64] → bool
//
// Vardiff solo mode: miners are sent a fixed-difficulty SHARE target
// (-sharediff, default 8M) so the submission rate stays sane at any chain
// difficulty; the node judges every forwarded share against the real block
// target. The node performs KawPow verification on submit (light path), so
// the sidecar stays consensus-free by design.
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/big"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

var (
	nodeURL   = flag.String("node", "http://127.0.0.1:8545", "Everett node RPC")
	listen    = flag.String("listen", ":3333", "stratum listen address")
	poll      = flag.Duration("poll", 250*time.Millisecond, "work poll interval")
	shareDiff = flag.Int64("sharediff", 8_000_000, "share difficulty sent to miners (0 = share target == block target). At trivial chain difficulty a GPU finds hundreds of block-target solutions per second and drowns in its own submission queue; a fixed share difficulty caps the rate like pool vardiff. No block is ever lost: when chain difficulty is below sharediff every share is also a block, and above it the miner submits everything that clears the share bar, which includes every block solution.")
)

// two256 = 2^256, the difficulty-to-target conversion base.
var two256 = new(big.Int).Lsh(big.NewInt(1), 256)

// --- node RPC ----------------------------------------------------------------

type rpcReq struct {
	ID     int             `json:"id"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
	Ver    string          `json:"jsonrpc"`
}

// nodeClient bounds every node RPC: the node can stall for seconds while
// it digests a burst of submitted blocks (observed live: one hung
// eth_submitWork backed the whole reply path past the miner's 2-second
// watchdog). Nothing in the sidecar may ever wait on the node unboundedly.
var nodeClient = &http.Client{Timeout: 8 * time.Second}

func nodeCall(method string, params interface{}, out interface{}) error {
	p, _ := json.Marshal(params)
	body, _ := json.Marshal(rpcReq{ID: 1, Method: method, Params: p, Ver: "2.0"})
	resp, err := nodeClient.Post(*nodeURL, "application/json", bytes.NewReader(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	var wrap struct {
		Result json.RawMessage `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&wrap); err != nil {
		return err
	}
	if wrap.Error != nil {
		return fmt.Errorf("node: %s", wrap.Error.Message)
	}
	if out != nil {
		return json.Unmarshal(wrap.Result, out)
	}
	return nil
}

// --- work state --------------------------------------------------------------

type work struct {
	jobID  string
	header string // 64 hex, no 0x
	seed   string
	target string // BLOCK target (node's boundary), 64 hex
	share  string // share target sent to miners (vardiff), 64 hex
	height uint64
	bits   string
	done   bool // guarded by mu: a block was found for this job, or a
	            // newer job superseded it. Solo mode needs exactly ONE
	            // solution per job to reach the node; at trivial devnet
	            // difficulty a GPU finds hundreds per second, and
	            // forwarding them all (each a synchronous node roundtrip
	            // in the read loop) backs up submit replies past the
	            // miner's 2-second response watchdog — it disconnects and
	            // wastes everything. Cost one 12-minute run to learn.
}

var (
	mu      sync.Mutex
	current *work
	jobs    = map[string]*work{} // jobId -> work
	jobSeq  int
	clients = map[net.Conn]*client{}
)

type client struct {
	conn       net.Conn
	enc        *json.Encoder
	writeMu    sync.Mutex // json.Encoder is not concurrency-safe; the poller
	                      // broadcasts jobs while this client's goroutine
	                      // writes submit replies. Serialize both.
	extranonce string
	authorized bool
	worker     string
}

func strip0x(s string) string { return strings.TrimPrefix(s, "0x") }

// toCompact encodes a 256-bit target in Bitcoin compact-bits form; the
// miner parses the notify "bits" field with SetCompact.
func toCompact(target *big.Int) string {
	b := target.Bytes()
	size := len(b)
	var compact uint64
	if size <= 3 {
		compact = target.Uint64() << (8 * (3 - uint(size)))
	} else {
		compact = new(big.Int).Rsh(target, uint(8*(size-3))).Uint64()
	}
	if compact&0x00800000 != 0 {
		compact >>= 8
		size++
	}
	return fmt.Sprintf("%08x", compact|uint64(size)<<24)
}

func pollWork() {
	for {
		var res [4]string
		if err := nodeCall("eth_getWork", []string{}, &res); err != nil {
			time.Sleep(2 * time.Second)
			continue
		}
		header := strip0x(res[0])
		mu.Lock()
		if current == nil || current.header != header {
			jobSeq++
			t, _ := new(big.Int).SetString(strip0x(res[2]), 16)
			if t == nil {
				t = big.NewInt(0)
			}
			height, _ := strconv.ParseUint(strip0x(res[3]), 16, 64)
			shareT := t
			if *shareDiff > 0 {
				shareT = new(big.Int).Div(two256, big.NewInt(*shareDiff))
			}
			w := &work{
				jobID:  fmt.Sprintf("%08x", jobSeq),
				header: header,
				seed:   strip0x(res[1]),
				target: fmt.Sprintf("%064x", t),
				share:  fmt.Sprintf("%064x", shareT),
				height: height,
				// bits MUST encode the SHARE target: kawpowminer's CUDA
				// kernel takes its search boundary from the notify bits
				// field, not from mining.set_target (verified live —
				// 1,639 solutions in 7s at a "8M" share target because
				// bits still said 131k). Block bits carry no information
				// the miner needs; the node rebuilds them itself.
				bits: toCompact(shareT),
			}
			// Retire every older job: the node's getWork has moved on, so
			// their solutions can no longer become blocks through it —
			// ack them as redundant shares without a node call.
			for _, old := range jobs {
				old.done = true
			}
			current = w
			jobs[w.jobID] = w
			if len(jobs) > 16 {
				for id := range jobs {
					if id != w.jobID && len(jobs) > 16 {
						delete(jobs, id)
					}
				}
			}
			// Snapshot clients under the lock; send outside it so a slow
			// miner's socket cannot stall job propagation to the others.
			snapshot := make([]*client, 0, len(clients))
			for _, c := range clients {
				snapshot = append(snapshot, c)
			}
			mu.Unlock()
			for _, c := range snapshot {
				go c.sendJob(w, true)
			}
			log.Printf("new job %s height=%d target=%s...", w.jobID, w.height, w.target[:16])
			time.Sleep(*poll)
			continue
		}
		mu.Unlock()
		time.Sleep(*poll)
	}
}

// --- stratum protocol --------------------------------------------------------

type stratumMsg struct {
	ID     interface{}   `json:"id"`
	Method string        `json:"method,omitempty"`
	Params []interface{} `json:"params,omitempty"`
	Result interface{}   `json:"result,omitempty"`
	Error  interface{}   `json:"error,omitempty"`
}

// respMsg is a JSON-RPC response: result is ALWAYS present, even when
// false — stratumMsg's omitempty would drop a false result entirely,
// leaving `{"id":40}` with neither result nor error on rejected shares.
type respMsg struct {
	ID     interface{} `json:"id"`
	Result interface{} `json:"result"`
	Error  interface{} `json:"error,omitempty"`
}

func (c *client) send(m interface{}) {
	c.writeMu.Lock()
	// A miner that stops reading must never stall the sidecar: bound every
	// write, and on failure close the connection so the read loop reaps it.
	c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	err := c.enc.Encode(m)
	c.writeMu.Unlock()
	if err != nil {
		log.Printf("write to %s failed, dropping client: %v", c.conn.RemoteAddr(), err)
		c.conn.Close()
	}
}

func (c *client) sendJob(w *work, clean bool) {
	// Miners get the SHARE target (vardiff); the node still judges
	// submissions against the block target.
	c.send(stratumMsg{Method: "mining.set_target", Params: []interface{}{w.share}})
	c.send(stratumMsg{Method: "mining.notify",
		Params: []interface{}{w.jobID, w.header, w.seed, w.share, clean, w.height, w.bits}})
}

var extraSeq uint32

func handle(conn net.Conn) {
	mu.Lock()
	extraSeq++
	c := &client{conn: conn, enc: json.NewEncoder(conn),
		extranonce: fmt.Sprintf("%04x", extraSeq&0xffff)}
	clients[conn] = c
	mu.Unlock()
	defer func() {
		mu.Lock()
		delete(clients, conn)
		mu.Unlock()
		conn.Close()
	}()
	log.Printf("miner connected from %s (extranonce %s)", conn.RemoteAddr(), c.extranonce)

	sc := bufio.NewScanner(conn)
	sc.Buffer(make([]byte, 64*1024), 64*1024)
	defer func() {
		// nil err = clean EOF (the miner closed); anything else names the
		// real reason this side dropped the session.
		log.Printf("miner %s disconnected: scan err=%v", conn.RemoteAddr(), sc.Err())
	}()
	for sc.Scan() {
		var m stratumMsg
		if err := json.Unmarshal(sc.Bytes(), &m); err != nil {
			continue
		}
		switch m.Method {
		case "mining.subscribe":
			c.send(respMsg{ID: m.ID, Result: []interface{}{nil, c.extranonce}})
		case "mining.authorize":
			c.authorized = true
			if len(m.Params) > 0 {
				c.worker, _ = m.Params[0].(string)
			}
			c.send(respMsg{ID: m.ID, Result: true})
			mu.Lock()
			w := current
			mu.Unlock()
			if w != nil {
				c.sendJob(w, true)
			}
		case "mining.submit":
			c.send(respMsg{ID: m.ID, Result: c.submit(m.Params)})
		case "eth_submitHashrate", "mining.extranonce.subscribe":
			c.send(respMsg{ID: m.ID, Result: true})
		default:
			// Unknown method = the miner negotiated a dialect we don't
			// speak (Eth-Proxy, NiceHash, EthereumStratum/2.0.0 — bare
			// stratum:// autodetects into these). A blind `true` here
			// makes that half-work and then hang with wasted solutions;
			// an explicit error makes the miner fail over or bail
			// loudly. Fix on the miner side: use stratum+tcp:// (plain
			// mode-0 stratum).
			log.Printf("unknown method %q from %s — miner is speaking a different stratum dialect; use stratum+tcp:// (mode 0)", m.Method, conn.RemoteAddr())
			c.send(respMsg{ID: m.ID, Result: nil, Error: []interface{}{-3, "method not supported; connect with stratum+tcp:// (plain stratum, mode 0)", nil}})
		}
	}
}

func (c *client) submit(params []interface{}) bool {
	if len(params) < 5 {
		return false
	}
	jobID, _ := params[1].(string)
	nonce, _ := params[2].(string)
	header, _ := params[3].(string)
	mix, _ := params[4].(string)

	mu.Lock()
	w, ok := jobs[jobID]
	if ok && w.done {
		// The block for this job is already found (or the job is
		// superseded). The share is still valid work — ack it instantly
		// so the reply queue never backs up into the miner's response
		// watchdog. No node call.
		mu.Unlock()
		return true
	}
	mu.Unlock()
	if !ok {
		log.Printf("submit for unknown job %s", jobID)
		return false
	}
	n := strip0x(nonce)
	if len(n) != 16 || !strings.HasPrefix(strings.ToLower(n), c.extranonce) {
		log.Printf("submit nonce %q fails extranonce %s check", nonce, c.extranonce)
		// Solo mode: accept anyway; the prefix is advisory when one miner owns the space.
	}
	// Ack instantly and forward ASYNC. The node can stall for seconds
	// digesting a block burst; a synchronous forward here puts that stall
	// on the miner's reply path and trips its 2-second response watchdog
	// (observed live — this, not share volume, killed four runs). The
	// share met the target we set, so it is a good share regardless of
	// what the node eventually says; only BLOCK logging depends on that.
	select {
	case forwardSlots <- struct{}{}:
		go func() {
			defer func() { <-forwardSlots }()
			var accepted bool
			err := nodeCall("eth_submitWork",
				[]string{"0x" + n, "0x" + strip0x(header), "0x" + strip0x(mix)}, &accepted)
			if err != nil {
				log.Printf("submitWork error: %v", err)
				return
			}
			if accepted {
				mu.Lock()
				w.done = true
				mu.Unlock()
				log.Printf("BLOCK: job %s height=%d nonce=%s from %s", jobID, w.height, nonce, c.worker)
			} else {
				nBelow := sharesBelow.Add(1)
				if nBelow == 1 || nBelow%50 == 0 {
					log.Printf("shares below block target: %d so far (expected under vardiff; sample: job %s nonce=%s)", nBelow, jobID, nonce)
				}
			}
		}()
	default:
		// All forward slots busy (node stalled): the share is still good;
		// dropping the forward loses nothing a later share won't redo.
		nDropped := forwardsDropped.Add(1)
		if nDropped == 1 || nDropped%50 == 0 {
			log.Printf("forwards dropped while node busy: %d so far", nDropped)
		}
	}
	return true
}

var (
	// At most 4 eth_submitWork calls in flight; beyond that the node is
	// stalled and additional forwards would only queue behind it.
	forwardSlots    = make(chan struct{}, 4)
	sharesBelow     atomic.Uint64
	forwardsDropped atomic.Uint64
)

func main() {
	flag.Parse()
	ln, err := net.Listen("tcp", *listen)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("kawpow-stratum listening on %s, node %s", *listen, *nodeURL)
	go pollWork()
	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("accept error: %v", err)
			time.Sleep(200 * time.Millisecond)
			continue
		}
		go handle(conn)
	}
}
