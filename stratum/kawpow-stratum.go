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
// Solo mode: share target = block target, every accepted share is a block.
// The node performs KawPow verification on submit (light path), so the
// sidecar stays consensus-free by design.
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
	"time"
)

var (
	nodeURL = flag.String("node", "http://127.0.0.1:8545", "Everett node RPC")
	listen  = flag.String("listen", ":3333", "stratum listen address")
	poll    = flag.Duration("poll", 250*time.Millisecond, "work poll interval")
)

// --- node RPC ----------------------------------------------------------------

type rpcReq struct {
	ID     int             `json:"id"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
	Ver    string          `json:"jsonrpc"`
}

func nodeCall(method string, params interface{}, out interface{}) error {
	p, _ := json.Marshal(params)
	body, _ := json.Marshal(rpcReq{ID: 1, Method: method, Params: p, Ver: "2.0"})
	resp, err := http.Post(*nodeURL, "application/json", bytes.NewReader(body))
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
	target string
	height uint64
	bits   string
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
			w := &work{
				jobID:  fmt.Sprintf("%08x", jobSeq),
				header: header,
				seed:   strip0x(res[1]),
				target: fmt.Sprintf("%064x", t),
				height: height,
				bits:   toCompact(t),
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
				c.sendJob(w, true)
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

func (c *client) send(m stratumMsg) {
	c.writeMu.Lock()
	c.enc.Encode(m)
	c.writeMu.Unlock()
}

func (c *client) sendJob(w *work, clean bool) {
	c.send(stratumMsg{Method: "mining.set_target", Params: []interface{}{w.target}})
	c.send(stratumMsg{Method: "mining.notify",
		Params: []interface{}{w.jobID, w.header, w.seed, w.target, clean, w.height, w.bits}})
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
	for sc.Scan() {
		var m stratumMsg
		if err := json.Unmarshal(sc.Bytes(), &m); err != nil {
			continue
		}
		switch m.Method {
		case "mining.subscribe":
			c.send(stratumMsg{ID: m.ID, Result: []interface{}{nil, c.extranonce}})
		case "mining.authorize":
			c.authorized = true
			if len(m.Params) > 0 {
				c.worker, _ = m.Params[0].(string)
			}
			c.send(stratumMsg{ID: m.ID, Result: true})
			mu.Lock()
			if current != nil {
				c.sendJob(current, true)
			}
			mu.Unlock()
		case "mining.submit":
			c.send(stratumMsg{ID: m.ID, Result: c.submit(m.Params)})
		case "eth_submitHashrate", "mining.extranonce.subscribe":
			c.send(stratumMsg{ID: m.ID, Result: true})
		default:
			c.send(stratumMsg{ID: m.ID, Result: true})
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
	var accepted bool
	err := nodeCall("eth_submitWork",
		[]string{"0x" + n, "0x" + strip0x(header), "0x" + strip0x(mix)}, &accepted)
	if err != nil {
		log.Printf("submitWork error: %v", err)
		return false
	}
	if accepted {
		log.Printf("BLOCK: job %s height=%d nonce=%s from %s", jobID, w.height, nonce, c.worker)
	} else {
		log.Printf("share rejected by node (stale or invalid): job %s nonce=%s", jobID, nonce)
	}
	return accepted
}

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
			continue
		}
		go handle(conn)
	}
}
