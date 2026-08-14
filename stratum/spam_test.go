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
	honest := dial(t)
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
