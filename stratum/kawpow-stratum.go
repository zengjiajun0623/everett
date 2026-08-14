// kawpow-stratum: a solo stratum sidecar for Everett-family nodes.
//
// Speaks the KawPow stratum dialect that kawpowminer/T-Rex/TeamRedMiner
// expect (G6_P1_NOTES.md §4.2, derived from kawpowminer's EthStratumClient
// source), backed by the node's eth_getWork/eth_submitWork RPC:
//
//	miner → mining.subscribe            → [null, extranonce]
//	miner → mining.authorize            → true
//	node  → mining.set_target [target64]
//	node  → mining.notify [jobId, header64, seed64, target64, clean, height, bits]
//	miner → mining.submit [user, jobId, 0xnonce16, 0xheader64, 0xmix64] → bool
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

const (
	// maxClients caps concurrent miner connections (see handle()).
	maxClients = 128
	// handshakeTimeout bounds an UNAUTHORIZED connection. A real miner
	// subscribes and authorizes within milliseconds; a socket that opens
	// and says nothing is a squatter holding a 64 KiB buffer and a slot.
	handshakeTimeout = 60 * time.Second
	// idleTimeout bounds an authorized miner. It is deliberately generous:
	// a low-hashrate rig can go a long time between shares, and dropping a
	// healthy miner just to reclaim a slot would be a worse bug than the
	// one this bounds. Miners reconnect automatically either way.
	idleTimeout = 30 * time.Minute
)

// two256 = 2^256, the difficulty-to-target conversion base.
var two256 = new(big.Int).Lsh(big.NewInt(1), 256)

// maxTarget is the largest 256-bit target. sharediff 1 is a legal flag
// value and divides two256 to exactly 2^256, one past this: unclamped it
// would emit a 65-hex-char target and compact bits that overflow the
// miner's SetCompact.
var maxTarget = new(big.Int).Sub(two256, big.NewInt(1))

// shareTarget converts a share difficulty into the target sent to miners;
// diff <= 0 means "share target == block target". The result always fits
// in 256 bits, so %064x renders exactly 64 hex chars and toCompact yields
// bits that SetCompact decodes without overflow.
func shareTarget(diff int64, blockT *big.Int) *big.Int {
	if diff <= 0 {
		return blockT
	}
	st := new(big.Int).Div(two256, big.NewInt(diff))
	if st.Cmp(maxTarget) > 0 {
		st.Set(maxTarget)
	}
	return st
}

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
	done   bool // guarded by mu: a block WAS found for this job. Solo mode
	// needs exactly ONE solution per job to reach the node; at
	// trivial devnet difficulty a GPU finds hundreds per second,
	// and forwarding them all (each a synchronous node roundtrip
	// in the read loop) backs up submit replies past the miner's
	// 2-second response watchdog, it disconnects and wastes
	// everything. Cost one 12-minute run to learn. Job ROTATION
	// no longer sets this: the node accepts solutions for older
	// work packages within its stale window, so retiring on
	// rotation discarded blocks.
}

var (
	mu       sync.Mutex
	current  *work
	jobs     = map[string]*work{} // jobId -> work
	jobOrder []string             // jobs keys in insertion order, oldest first (guarded by mu)
	jobSeq   int
	clients  = map[net.Conn]*client{}
)

type client struct {
	conn    net.Conn
	enc     *json.Encoder
	writeMu sync.Mutex // json.Encoder is not concurrency-safe; the poller
	// broadcasts jobs while this client's goroutine
	// writes submit replies. Serialize both.
	extranonce string
	authorized bool
	worker     string
	// inFlight bounds this client to ONE forward at a time. The sidecar is
	// consensus-free by design, so it cannot cheaply tell a real share from
	// shape-valid garbage: only the node can, and each check costs it a full
	// KawPow light verification. core-geth's remote sealer handles submits,
	// new work, and getWork on ONE goroutine, so an unauthenticated LAN
	// client spamming well-formed junk could occupy all four forward slots
	// and starve both the honest miner's winning share and new-work
	// generation, stalling block production without doing any PoW itself.
	// One slot per client caps that at 1/4 of the pipe. It costs an honest
	// miner nothing: the done flag already means one solution per job.
	inFlight atomic.Bool
}

func strip0x(s string) string { return strings.TrimPrefix(s, "0x") }

// isHex reports whether s is non-empty and all lowercase-or-digit hex.
func isHex(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if !(r >= '0' && r <= '9' || r >= 'a' && r <= 'f' || r >= 'A' && r <= 'F') {
			return false
		}
	}
	return true
}

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
			shareT := shareTarget(*shareDiff, t)
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
			// Older jobs are NOT retired here. core-geth keeps every work
			// package it handed out and accepts a solution for any of them
			// within staleThreshold (7) blocks of the current head
			// (consensus/ethash/sealer.go: s.works[sealhash], pruned only
			// past that window). getWork changes on every tx that lands in
			// the pending block, far more often than the head moves, so
			// retiring on rotation threw away solutions the node would
			// have accepted as blocks. done is now set only when a block
			// really was found for that job, which is what it means.
			// Flood control does not depend on this: vardiff sets the
			// share target and forwardSlots caps in-flight node calls.
			current = w
			jobs[w.jobID] = w
			jobOrder = append(jobOrder, w.jobID)
			// Trim the OLDEST retired job, deterministically. Map-iteration
			// eviction picked a random victim, which could be the job we
			// retired one line up: the one whose shares are still in TCP
			// flight from the GPU and need the instant-ack path in submit().
			// jobOrder is FIFO, so index 0 is always the oldest and can never
			// be the just-appended current job while len > 16.
			for len(jobOrder) > 16 {
				delete(jobs, jobOrder[0])
				jobOrder = jobOrder[1:]
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
	// Cap concurrent miners. The listener is deliberately reachable from
	// the LAN (and the compose stack publishes it), so without a cap any
	// host can pin unbounded memory: every connection holds a 64 KiB
	// scanner buffer and an entry in the clients map for as long as it
	// stays open. A solo sidecar serves a handful of rigs; 128 is far
	// above any real fleet and far below a resource problem.
	mu.Lock()
	if len(clients) >= maxClients {
		mu.Unlock()
		log.Printf("refusing %s: %d clients already connected (cap)", conn.RemoteAddr(), maxClients)
		conn.Close()
		return
	}
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
	// Two-phase read deadline. Until the miner authorizes it gets only
	// handshakeTimeout; afterwards the generous idleTimeout. Without any
	// deadline these connections lived forever, holding their buffer and
	// client slot, with no cap on how many a LAN host could open.
	_ = conn.SetReadDeadline(time.Now().Add(handshakeTimeout))
	defer func() {
		// nil err = clean EOF (the miner closed); anything else names the
		// real reason this side dropped the session.
		log.Printf("miner %s disconnected: scan err=%v", conn.RemoteAddr(), sc.Err())
	}()
	connectedAt := time.Now()
	for sc.Scan() {
		// An AUTHORIZED miner keeps its session alive by talking. An
		// unauthorized one gets an ABSOLUTE budget from connect time: the
		// deadline used to be re-armed on every received line, before
		// parsing, so a socket dripping one junk byte a minute never
		// expired and could hold a client slot forever. 128 of those
		// filled the cap and every real miner got refused.
		if c.authorized {
			_ = conn.SetReadDeadline(time.Now().Add(idleTimeout))
		} else if time.Since(connectedAt) > handshakeTimeout {
			log.Printf("closing %s: no authorize within %s", conn.RemoteAddr(), handshakeTimeout)
			return
		}
		var m stratumMsg
		if err := json.Unmarshal(sc.Bytes(), &m); err != nil {
			continue
		}
		switch m.Method {
		case "mining.subscribe":
			c.send(respMsg{ID: m.ID, Result: []interface{}{nil, c.extranonce}})
		case "mining.authorize":
			c.authorized = true
			// Arm the generous window NOW. The loop sets it at the TOP of
			// the next iteration, so without this a miner that authorizes
			// and then waits for its first job (or simply mines slowly)
			// still carried the absolute connect+handshakeTimeout deadline
			// and was dropped 60s after connecting.
			_ = conn.SetReadDeadline(time.Now().Add(idleTimeout))
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
		// A block for this job was already found. The share is still
		// valid work, so ack it instantly and keep the reply queue clear
		// of the miner's response watchdog. No node call.
		mu.Unlock()
		return true
	}
	mu.Unlock()
	if !ok {
		log.Printf("submit for unknown job %q", jobID)
		return false
	}
	// The header must be the one this job handed out. A submit that pairs
	// job A with job B's header would be forwarded as-is, and if the node
	// accepted it (both are live inside its stale window) we would mark A
	// done. Every later share for A, including a genuine block-winning
	// nonce, would then take the done early-ack above and never reach the
	// node: a block silently lost while the miner is told "accepted".
	// Stock miners always pair them correctly, so this only fires on a
	// buggy or hostile client, which is exactly when it matters.
	if !strings.EqualFold(strip0x(header), w.header) {
		log.Printf("submit for job %q carries header %q, job has %s: rejecting",
			jobID, strip0x(header), w.header)
		return false
	}
	// Shape checks REJECT. They used to log and fall through, so a
	// malformed share was acked true and still forwarded: a buggy miner
	// saw 100% "accepted" while producing nothing, and any LAN host could
	// spend our node's CPU on garbage eth_submitWork verifications for
	// free. The sidecar is consensus-free, but it can afford to check that
	// a nonce is 16 hex digits before spending the node on it.
	n := strings.ToLower(strip0x(nonce))
	if len(n) != 16 || !isHex(n) {
		log.Printf("submit for job %q: malformed nonce %q (want 16 hex): rejecting", jobID, nonce)
		return false
	}
	if !isHex(strip0x(mix)) || len(strip0x(mix)) != 64 {
		log.Printf("submit for job %q: malformed mix %q (want 64 hex): rejecting", jobID, mix)
		return false
	}
	if !strings.HasPrefix(n, c.extranonce) {
		// Advisory only: in solo mode one miner owns the nonce space.
		log.Printf("submit nonce %q outside extranonce %s (advisory)", nonce, c.extranonce)
	}
	// Capture the worker name NOW, on this goroutine: submit() runs on the
	// same read-loop goroutine that writes c.worker in the authorize case,
	// so this read is ordered. The forward goroutine below must not touch
	// c.worker itself: a miner re-sending mining.authorize while a forward
	// is in flight would race the read-loop write against that read.
	worker := c.worker
	// Ack instantly and forward ASYNC. The node can stall for seconds
	// digesting a block burst; a synchronous forward here puts that stall
	// on the miner's reply path and trips its 2-second response watchdog
	// (observed live, and this rather than share volume killed four runs).
	//
	// The share is NOT known to be good here: this sidecar never checks it
	// against the target, because doing so is exactly the KawPow work the
	// node does on submitWork. An earlier comment claimed otherwise and was
	// wrong. What is bounded instead is cost: one forward per client at a
	// time, and four overall.
	if !c.inFlight.CompareAndSwap(false, true) {
		// This client already has a submit being verified by the node.
		// Ack it (the miner should not stall on our accounting) but do not
		// spend a second node verification on it.
		nSkipped := forwardsSkipped.Add(1)
		if nSkipped == 1 || nSkipped%100 == 0 {
			log.Printf("submits skipped, client already has one in flight: %d so far", nSkipped)
		}
		return true
	}
	select {
	case forwardSlots <- struct{}{}:
		go func() {
			defer func() { <-forwardSlots; c.inFlight.Store(false) }()
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
				log.Printf("BLOCK: job %s height=%d nonce=%s from %q", jobID, w.height, nonce, worker)
			} else {
				nBelow := sharesBelow.Add(1)
				if nBelow == 1 || nBelow%50 == 0 {
					log.Printf("shares below block target: %d so far (expected under vardiff; sample: job %q nonce=%q)", nBelow, jobID, nonce)
				}
			}
		}()
	default:
		// All forward slots busy (node stalled). Dropping the forward loses
		// nothing a later share will not redo.
		c.inFlight.Store(false)
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
	forwardsSkipped atomic.Uint64
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
