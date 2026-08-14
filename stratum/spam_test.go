package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// TestSpamClientCannotStarveHonestMiner is the regression test for a
// cross-model audit finding: the sidecar validates a submit's SHAPE but
// cannot check it against the target (that is the KawPow work the node
// does), so an unauthenticated LAN client could spam well-formed garbage,
// occupy every forward slot, and starve both the honest miner's winning
// share and the node's new-work generation, which core-geth's remote
// sealer handles on the same single goroutine.
//
// The defense is one in-flight forward per client. This test asserts the
// property that matters: while a spammer submits as fast as it can, an
// honest miner's submits still reach the node.
func TestSpamClientCannotStarveHonestMiner(t *testing.T) {
	// Set BEFORE any goroutine can read it: handle() reads hostOf, so
	// assigning it once the accept loop is live is a data race in the
	// harness (the race detector caught exactly that).
	saveHostOf := hostOf
	var nextHost atomic.Value
	nextHost.Store("10.0.0.1")
	hostOf = func(net.Conn) string { return nextHost.Load().(string) }
	defer func() { hostOf = saveHostOf }()

	var nodeCalls atomic.Int64
	var honestSeen atomic.Int64
	// The fake node is SLOW, like a real one running KawPow verification.
	// That is what makes slot monopolisation possible in the first place.
	node := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			ID     int      `json:"id"`
			Method string   `json:"method"`
			Params []string `json:"params"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		nodeCalls.Add(1)
		if len(req.Params) > 0 && req.Params[0] == "0x00000000deadbeef" {
			honestSeen.Add(1) // the honest miner's distinctive nonce
		}
		time.Sleep(150 * time.Millisecond)
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"jsonrpc":"2.0","id":%d,"result":false}`, req.ID)
	}))
	defer node.Close()
	savedURL := *nodeURL
	*nodeURL = node.URL
	defer func() {
		for i := 0; i < cap(forwardSlots); i++ {
			forwardSlots <- struct{}{}
		}
		*nodeURL = savedURL
		for i := 0; i < cap(forwardSlots); i++ {
			<-forwardSlots
		}
	}()

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go handle(conn)
		}
	}()

	// One live job for everyone to submit against.
	w := &work{
		jobID: "cafe0001", header: fmt.Sprintf("%064x", 0xabc),
		seed: fmt.Sprintf("%064x", 1), target: fmt.Sprintf("%064x", 1),
		share: fmt.Sprintf("%064x", 1), height: 42, bits: "1d00ffff",
	}
	mu.Lock()
	current = w
	jobs[w.jobID] = w
	jobOrder = append(jobOrder, w.jobID)
	mu.Unlock()

	dial := func(t *testing.T) *json.Encoder {
		t.Helper()
		conn, err := net.Dial("tcp", ln.Addr().String())
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { conn.Close() })
		go func() {
			br := bufio.NewReader(conn)
			for {
				if _, err := br.ReadString('\n'); err != nil {
					return
				}
			}
		}()
		enc := json.NewEncoder(conn)
		_ = enc.Encode(map[string]interface{}{"id": 1, "method": "mining.subscribe", "params": []interface{}{"x"}})
		_ = enc.Encode(map[string]interface{}{"id": 2, "method": "mining.authorize", "params": []interface{}{"w", "x"}})
		return enc
	}

	submit := func(enc *json.Encoder, nonce string) {
		_ = enc.Encode(map[string]interface{}{"id": 3, "method": "mining.submit",
			"params": []interface{}{"worker", w.jobID, nonce, w.header, fmt.Sprintf("%064x", 7)}})
	}

	spam := dial(t)
	time.Sleep(50 * time.Millisecond) // let handle() bind that host
	nextHost.Store("10.0.0.2")
	honest := dial(t)
	time.Sleep(50 * time.Millisecond)
	time.Sleep(100 * time.Millisecond)

	stop := make(chan struct{})
	go func() { // the attacker, submitting as fast as it can
		for i := 0; ; i++ {
			select {
			case <-stop:
				return
			default:
			}
			submit(spam, fmt.Sprintf("0x%016x", i))
		}
	}()

	// The honest miner submits its winning share a handful of times over
	// the window, as a real miner would across successive jobs.
	for i := 0; i < 3; i++ {
		time.Sleep(250 * time.Millisecond)
		submit(honest, "0x00000000deadbeef")
	}
	time.Sleep(700 * time.Millisecond)
	close(stop)

	if honestSeen.Load() == 0 {
		t.Fatalf("STARVED: the honest miner's share never reached the node "+
			"while a spammer was active (node calls: %d)", nodeCalls.Load())
	}
	t.Logf("honest submits delivered: %d, total node calls: %d, spam skipped: %d",
		honestSeen.Load(), nodeCalls.Load(), forwardsSkipped.Load())
}

// TestPerIPCapStopsBudgetMultiplication: the submit budget is per client,
// so one host opening many clients multiplies it. Before the per-IP cap,
// ten connections from a single address measurably degraded the honest
// miner's delivery. Loopback is exempt in production (operator tooling),
// and every test connection is loopback, so the exemption is switched off
// here or the cap would be unexercised by construction.
func TestPerIPCapStopsBudgetMultiplication(t *testing.T) {
	saveExempt := exemptLoopback
	exemptLoopback = false
	defer func() { exemptLoopback = saveExempt }()

	mu.Lock()
	saved := clients
	clients = map[net.Conn]*client{}
	mu.Unlock()
	defer func() { mu.Lock(); clients = saved; mu.Unlock() }()

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go handle(conn)
		}
	}()

	// Open well past the cap from one host, keeping each socket alive.
	const attempts = 12
	var held []net.Conn
	for i := 0; i < attempts; i++ {
		c, err := net.Dial("tcp", ln.Addr().String())
		if err != nil {
			break
		}
		held = append(held, c)
		defer c.Close()
		time.Sleep(15 * time.Millisecond) // let handle() register or refuse
	}

	mu.Lock()
	registered := len(clients)
	mu.Unlock()
	if registered > *maxPerIPFlag {
		t.Fatalf("per-IP cap did not hold: %d connections registered from one host, cap is %d",
			registered, *maxPerIPFlag)
	}
	t.Logf("attempted %d connections from one host, %d registered (cap %d)",
		attempts, registered, *maxPerIPFlag)
}
