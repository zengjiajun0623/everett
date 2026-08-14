package main

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// Does closing and reopening a connection grant a fresh token budget?
//
// SCOPE, stated because a green result here is easy to over-read: since the
// per-host in-flight cap landed, ONE churning connection can occupy at most
// maxInFlightPerHost slots whether the budget is keyed by host or by
// connection, so this test alone no longer distinguishes the two. It still
// guards the regression it was written for (a reconnect must not visibly
// multiply node work), and the property it cannot see is enforced
// structurally instead: bucketFor keys hostBuckets by host, and
// releaseBucket refuses to drop an entry whose budget has not refilled, so
// a drained bucket cannot be discarded by disconnecting. The starvation
// test with its own negative control is what proves the fairness half.
func TestChurnResetsBudget(t *testing.T) {
	var calls atomic.Int64
	node := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		time.Sleep(2 * time.Millisecond)
		fmt.Fprint(w, `{"jsonrpc":"2.0","id":1,"result":false}`)
	}))
	defer node.Close()
	saved := *nodeURL
	*nodeURL = node.URL
	defer func() {
		for i := 0; i < cap(forwardSlots); i++ {
			forwardSlots <- struct{}{}
		}
		*nodeURL = saved
		for i := 0; i < cap(forwardSlots); i++ {
			<-forwardSlots
		}
	}()

	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	defer ln.Close()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go handle(c)
		}
	}()

	w := &work{jobID: "aa", header: fmt.Sprintf("%064x", 1), seed: fmt.Sprintf("%064x", 1),
		target: fmt.Sprintf("%064x", 1), share: fmt.Sprintf("%064x", 1), height: 1, bits: "1d00ffff"}
	mu.Lock()
	current = w
	jobs[w.jobID] = w
	jobOrder = append(jobOrder, w.jobID)
	mu.Unlock()

	burn := func(reconnect bool, rounds int) int64 {
		before := calls.Load()
		var conn net.Conn
		var enc *json.Encoder
		open := func() {
			conn, _ = net.Dial("tcp", ln.Addr().String())
			enc = json.NewEncoder(conn)
			_ = enc.Encode(map[string]interface{}{"id": 1, "method": "mining.subscribe", "params": []interface{}{"x"}})
			_ = enc.Encode(map[string]interface{}{"id": 2, "method": "mining.authorize", "params": []interface{}{"w", "x"}})
			time.Sleep(15 * time.Millisecond)
		}
		open()
		for r := 0; r < rounds; r++ {
			for i := 0; i < 70; i++ {
				_ = enc.Encode(map[string]interface{}{"id": 3, "method": "mining.submit",
					"params": []interface{}{"w", w.jobID, fmt.Sprintf("0x%016x", r*100+i), w.header, fmt.Sprintf("%064x", 7)}})
			}
			time.Sleep(60 * time.Millisecond)
			if reconnect {
				conn.Close()
				open()
			}
		}
		time.Sleep(200 * time.Millisecond)
		conn.Close()
		return calls.Load() - before
	}

	persistent := burn(false, 6)
	time.Sleep(300 * time.Millisecond)
	churned := burn(true, 6)
	t.Logf("node verifications: persistent connection=%d, churned connections=%d", persistent, churned)
	if churned > persistent*2 {
		t.Fatalf("CHURN BYPASS CONFIRMED: reconnecting bought %dx the node work (%d vs %d)",
			churned/max(persistent, 1), churned, persistent)
	}
}

func max(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
