package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

// TestProtocolConcurrent drives the real connection handler the way a fleet
// of miners does: many clients subscribing, re-authorizing, and submitting
// at once while the poller retires and broadcasts jobs.
//
// It exists because the CI job named "vet + race tests" previously ran the
// race detector over tests that never started the server, so the detector
// saw no server goroutines at all. A data race between the authorize
// handler and the submit-forward goroutine shipped through that gate. This
// test makes the gate mean what its name says.
//
// A fake node accepts every solution, so the forward goroutine's success
// branch (where the race lived) actually executes. Negative-controlled:
// reverting the worker-name capture makes this test fail under -race.
func TestProtocolConcurrent(t *testing.T) {
	// Fake node that ACCEPTS every submitted solution. This is what makes
	// the test exercise the forward goroutine's success branch, where the
	// worker-name race lived; with a dead node the forward always errors
	// and that code never runs.
	node := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			ID     int    `json:"id"`
			Method string `json:"method"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"jsonrpc":"2.0","id":%d,"result":true}`, req.ID)
	}))
	savedURL := *nodeURL
	*nodeURL = node.URL
	// Restoring the flag and closing the fake node must happen only after
	// every in-flight forward goroutine is done: those goroutines read
	// *nodeURL inside nodeCall, so an unsynchronized restore races them
	// (caught in CI, not locally: pure test-harness timing). Acquiring
	// every forward slot proves none are still running, because submit()
	// holds a slot for the whole call and releases it on return.
	defer func() {
		for i := 0; i < cap(forwardSlots); i++ {
			forwardSlots <- struct{}{}
		}
		*nodeURL = savedURL
		node.Close()
		for i := 0; i < cap(forwardSlots); i++ {
			<-forwardSlots
		}
	}()

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	done := make(chan struct{})
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				select {
				case <-done:
					return
				default:
					return
				}
			}
			go handle(conn)
		}
	}()

	// Inject a job the way pollWork would, including the retire/broadcast
	// path that races with client writes.
	inject := func(seq int) {
		w := &work{
			jobID:  fmt.Sprintf("%08x", seq),
			header: fmt.Sprintf("%064x", seq),
			seed:   fmt.Sprintf("%064x", seq+1),
			target: fmt.Sprintf("%064x", 1), // unbeatable: submits stay local
			share:  fmt.Sprintf("%064x", 1),
			height: uint64(seq),
			bits:   "1d00ffff",
		}
		mu.Lock()
		if current != nil {
			current.done = true
		}
		current = w
		jobs[w.jobID] = w
		jobOrder = append(jobOrder, w.jobID)
		for len(jobOrder) > 16 {
			delete(jobs, jobOrder[0])
			jobOrder = jobOrder[1:]
		}
		snapshot := make([]*client, 0, len(clients))
		for _, c := range clients {
			snapshot = append(snapshot, c)
		}
		mu.Unlock()
		for _, c := range snapshot {
			go c.sendJob(w, true)
		}
	}

	addr := ln.Addr().String()
	const miners = 12
	var wg sync.WaitGroup
	stop := make(chan struct{})

	// Job churn while miners hammer the handler.
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 1; ; i++ {
			select {
			case <-stop:
				return
			default:
			}
			inject(i)
			time.Sleep(2 * time.Millisecond)
		}
	}()

	for m := 0; m < miners; m++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			conn, err := net.Dial("tcp", addr)
			if err != nil {
				t.Errorf("miner %d dial: %v", id, err)
				return
			}
			defer conn.Close()
			enc := json.NewEncoder(conn)
			go func() { // drain whatever the server pushes
				br := bufio.NewReader(conn)
				for {
					if _, err := br.ReadString('\n'); err != nil {
						return
					}
				}
			}()
			_ = enc.Encode(map[string]interface{}{"id": 1, "method": "mining.subscribe", "params": []interface{}{"fuzz/1.0"}})
			for i := 0; ; i++ {
				select {
				case <-stop:
					return
				default:
				}
				// Re-authorize repeatedly: this is the write side of the
				// worker-name race the old code had.
				_ = enc.Encode(map[string]interface{}{"id": 2, "method": "mining.authorize",
					"params": []interface{}{fmt.Sprintf("worker-%d-%d", id, i), "x"}})
				mu.Lock()
				jobID := ""
				if current != nil {
					jobID = current.jobID
				}
				mu.Unlock()
				_ = enc.Encode(map[string]interface{}{"id": 3, "method": "mining.submit",
					"params": []interface{}{fmt.Sprintf("worker-%d", id), jobID,
						fmt.Sprintf("0x%016x", id*1000+i), fmt.Sprintf("%064x", i), fmt.Sprintf("%064x", i)}})
				time.Sleep(time.Millisecond)
			}
		}(m)
	}

	time.Sleep(2500 * time.Millisecond)
	close(stop)
	close(done)
	wg.Wait()

	// The server must still be sane: job bookkeeping bounded, no deadlock.
	mu.Lock()
	nJobs, nOrder := len(jobs), len(jobOrder)
	mu.Unlock()
	if nJobs > 17 || nOrder > 17 {
		t.Fatalf("job bookkeeping unbounded: jobs=%d jobOrder=%d", nJobs, nOrder)
	}
	if nJobs != nOrder {
		t.Fatalf("jobs and jobOrder diverged: %d vs %d", nJobs, nOrder)
	}
	t.Logf("survived: jobs=%d jobOrder=%d", nJobs, nOrder)
}
