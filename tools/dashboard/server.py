#!/usr/bin/env python3
"""Everett network dashboard server.

Serves a single-page dashboard and a JSON status API aggregated from the
local node's JSON-RPC. Runs server-side so the node's RPC stays
localhost-only with no CORS changes; open the dashboard from any LAN
device.

  python3 server.py            # http://0.0.0.0:8484, node http://127.0.0.1:8545
  RPC=http://127.0.0.1:8545 PORT=8484 python3 server.py

The supply figure is not an estimate: scripts/burn_audit.py (the exact,
uncle- and burn-aware Article III/IV recomputation) runs every 5 minutes
and its verdict is shown as-is.
"""
import atexit
import json
import os
import signal
import subprocess
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RPC = os.environ.get("RPC", "http://127.0.0.1:8545")
PORT = int(os.environ.get("PORT", "8484"))
HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT = os.path.join(HERE, "..", "..", "scripts", "burn_audit.py")
AUDIT_CMD = ["python3", AUDIT]   # exact spawn cmdline; also the stale-kill match
# The audit refuses to run against a chain other than this one, so the
# expectation must track RPC. Hardcoding Wheeler made a dashboard pointed
# anywhere else (a devnet, and mainnet on launch day) show a permanent red
# audit FAIL. Resolved at startup from the node itself unless the operator
# pins it explicitly, which keeps the guard meaningful (it still catches
# the node changing identity underneath a running dashboard) without
# breaking every other chain.
EXPECT_CHAINID = os.environ.get("EXPECT_CHAINID")
WINDOW = 300          # blocks kept for charts
AUDIT_EVERY = 300     # seconds between exact supply audits


def rpc(method, params=None, timeout=8):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method,
                       "params": params or []}).encode()
    req = urllib.request.Request(RPC, data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        out = json.loads(r.read())
    if "error" in out and out["error"]:
        raise RuntimeError(out["error"].get("message", "rpc error"))
    return out.get("result")


def hx(v):
    return int(v, 16) if isinstance(v, str) else int(v)


def fetch_block(n):
    b = rpc("eth_getBlockByNumber", [hex(n), False])
    if b is None:
        return None
    return {
        "number": hx(b["number"]),
        "hash": b["hash"],
        "miner": b["miner"].lower(),
        "difficulty": hx(b["difficulty"]),
        "timestamp": hx(b["timestamp"]),
        "gasUsed": hx(b["gasUsed"]),
        "baseFee": hx(b.get("baseFeePerGas", "0x0")),
        "txs": len(b.get("transactions", [])),
        "uncles": len(b.get("uncles", [])),
        "nonce": b.get("nonce", "0x0"),
    }


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.blocks = {}          # number -> block dict
        self.head = 0
        self.chain_id = None
        self.peers = []
        self.node_ok = False
        self.audit = {"status": "pending", "detail": "first audit not yet run"}
        self.started = time.time()


S = State()


def follow_head():
    """Poll the head; backfill the window; reconcile shallow reorgs."""
    while True:
        try:
            head = hx(rpc("eth_blockNumber"))
            with S.lock:
                S.node_ok = True
                if S.chain_id is None:
                    S.chain_id = hx(rpc("eth_chainId"))
                known = S.head
            lo = max(1, head - WINDOW)
            # Drop anything ABOVE the current head first. A reorg to a
            # higher-total-difficulty but SHORTER chain (ASERT swings make
            # that reachable) or an operator resync leaves orphaned blocks
            # that no re-fetch can correct: heights above head return None,
            # so the stale entries would survive and the tip, charts, and
            # intervals would mix two chains.
            with S.lock:
                for n in [n for n in S.blocks if n > head]:
                    del S.blocks[n]
            # Re-check recent blocks for same-height reorgs. The window is
            # adaptive: at least 8, and always back to the deepest block
            # whose hash we have not re-read since the head last moved.
            depth = max(8, min(WINDOW, head - known + 8)) if known else 8
            recheck = range(max(lo, known - depth), known + 1) if known else []
            fetch = list(recheck) + list(range(max(lo, known + 1), head + 1))
            reorged = False
            for n in fetch:
                b = fetch_block(n)
                if b is None:
                    continue
                with S.lock:
                    old = S.blocks.get(n)
                    if old is not None and old["hash"] != b["hash"]:
                        reorged = True
                    if old is None or old["hash"] != b["hash"]:
                        S.blocks[n] = b
            # A reorg at the edge of the window means deeper blocks may
            # also have changed; sweep the whole window once to converge.
            if reorged:
                for n in list(range(lo, head + 1)):
                    b = fetch_block(n)
                    if b is None:
                        continue
                    with S.lock:
                        if S.blocks.get(n, {}).get("hash") != b["hash"]:
                            S.blocks[n] = b
            with S.lock:
                S.head = head
                for n in list(S.blocks):
                    if n < head - WINDOW:
                        del S.blocks[n]
        except Exception as e:
            with S.lock:
                S.node_ok = False
                S.last_err = str(e)
        try:
            peers = rpc("admin_peers") or []
            with S.lock:
                S.peers = [{
                    "name": p.get("name", "")[:60],
                    "addr": p.get("network", {}).get("remoteAddress", ""),
                    "inbound": p.get("network", {}).get("inbound", False),
                } for p in peers]
        except Exception:
            pass
        time.sleep(3)


_audit_proc = None            # live burn_audit Popen, guarded by _audit_lock
_audit_lock = threading.Lock()


def kill_stale_audits():
    """Reap burn_audit children orphaned by a previous dashboard instance.

    If the dashboard crashes (e.g. port 8484 already bound) the spawned
    full-chain replay is orphaned and keeps hammering the node RPC while
    launchd relaunches us. Match the full cmdline of our own invocation
    pattern so manual `python3 scripts/burn_audit.py` runs from the repo
    root (a different cmdline) are left alone.
    """
    pattern = " ".join(AUDIT_CMD)
    try:
        out = subprocess.run(["ps", "-axo", "pid=,ppid=,command="],
                             capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return
    for line in out.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) != 3:
            continue
        pid_s, ppid_s, cmd = parts
        if cmd.strip() != pattern or not pid_s.isdigit() or not ppid_s.isdigit():
            continue
        pid, ppid = int(pid_s), int(ppid_s)
        # ORPHANS ONLY. A live parent means this audit belongs to a running
        # dashboard (a second instance on another port is a legitimate
        # thing to start); killing it would blank that dashboard's audit
        # tile. Orphans are reparented to init, so ppid == 1.
        if ppid != 1:
            continue
        try:
            # killpg only when the pid really leads its own group: pid
            # recycling could otherwise make this signal an unrelated
            # group that happens to share the number.
            if os.getpgid(pid) == pid:
                os.killpg(pid, signal.SIGKILL)
            else:
                os.kill(pid, signal.SIGKILL)
        except OSError:
            continue
        print(f"killed orphaned burn_audit pid {pid}")


def _kill_audit_group():
    """Kill the live audit's process group; runs at exit and on SIGTERM."""
    with _audit_lock:
        proc = _audit_proc
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except OSError:
        pass


def _on_sigterm(signum, frame):
    _kill_audit_group()
    sys.exit(0)   # SystemExit also runs the atexit handler


def run_audit():
    global _audit_proc
    while True:
        try:
            # start_new_session gives the audit its own process group, so
            # shutdown (atexit/SIGTERM) can kill the group and a dashboard
            # crash never leaves N concurrent full-chain replays behind;
            # kill_stale_audits() at startup mops up anything that did.
            proc = subprocess.Popen(
                AUDIT_CMD, env={**os.environ, "RPC": RPC,
                     **({"EXPECT_CHAINID": EXPECT_CHAINID} if EXPECT_CHAINID else {})},
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                start_new_session=True)
            with _audit_lock:
                _audit_proc = proc
            try:
                stdout, stderr = proc.communicate(timeout=600)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except OSError:
                    proc.kill()
                proc.communicate()
                raise
            finally:
                with _audit_lock:
                    _audit_proc = None
            lines = stdout.strip().splitlines() or [
                "no stdout; stderr tail:"] + stderr.strip().splitlines()[-4:]
            tail = lines[-6:]
            verdict = "PASS" if any("PASS" in l for l in lines) else "FAIL"
            stats = next((l for l in lines if l.startswith("blocks=")), "")
            # total supply = sum of the audit's exact per-miner balances
            supply_wei = 0
            for l in lines:
                if " actual=" in l:
                    try:
                        supply_wei += int(l.split(" actual=")[1].split()[0])
                    except (ValueError, IndexError):
                        pass
            with S.lock:
                S.audit = {"status": verdict, "stats": stats,
                           "detail": "\n".join(tail),
                           "supplyEtt": supply_wei / 1e18,
                           "at": int(time.time())}
        except Exception as e:
            with S.lock:
                S.audit = {"status": "error", "detail": str(e),
                           "at": int(time.time())}
        time.sleep(AUDIT_EVERY)


def status_payload():
    with S.lock:
        blocks = sorted(S.blocks.values(), key=lambda b: b["number"])
        head, chain_id = S.head, S.chain_id
        peers, node_ok = list(S.peers), S.node_ok
        audit = dict(S.audit)
    out = {"nodeOk": node_ok, "chainId": chain_id, "head": head,
           "peers": peers, "audit": audit, "now": int(time.time())}
    if blocks:
        tip = blocks[-1]
        out["tip"] = tip
        n = len(blocks)
        # block intervals + averages over up to the last 20 / whole window
        ivals = [blocks[i]["timestamp"] - blocks[i - 1]["timestamp"]
                 for i in range(1, n)]
        last20 = ivals[-20:] if ivals else []
        out["avgBlockTime20"] = round(sum(last20) / len(last20), 2) if last20 else None
        # hashrate estimate: mean difficulty / mean interval, recent window
        k = min(40, n - 1)
        if k > 0:
            dsum = sum(b["difficulty"] for b in blocks[-k:])
            tspan = blocks[-1]["timestamp"] - blocks[-k - 1]["timestamp"]
            out["hashrate"] = round(dsum / tspan) if tspan > 0 else None
        out["uncleRate"] = round(
            sum(b["uncles"] for b in blocks) / n, 4)
        out["series"] = [
            {"n": b["number"], "d": b["difficulty"], "t": b["timestamp"],
             "m": b["miner"], "u": b["uncles"], "no": b.get("nonce", "0x0")}
            for b in blocks]
        miners = {}
        for b in blocks:
            miners[b["miner"]] = miners.get(b["miner"], 0) + 1
        out["miners"] = sorted(
            ([m, c] for m, c in miners.items()), key=lambda x: -x[1])
    return out


class H(BaseHTTPRequestHandler):
    # BaseHTTPRequestHandler reads the request line from a BLOCKING socket
    # with no timeout, and ThreadingHTTPServer gives every connection its
    # own thread. A LAN client that opens sockets and sends nothing would
    # otherwise pin a thread and a file descriptor each, forever, until the
    # process hits its descriptor limit and the dashboard stops answering
    # while still looking alive. A read timeout bounds that; a slow but
    # real client simply reconnects.
    timeout = 10

    def setup(self):
        super().setup()
        self.connection.settimeout(self.timeout)

    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.startswith("/api/status"):
            body = json.dumps(status_payload()).encode()
            ctype = "application/json"
        elif self.path in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as f:
                body = f.read()
            ctype = "text/html; charset=utf-8"
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    if EXPECT_CHAINID is None:
        try:
            EXPECT_CHAINID = str(hx(rpc("eth_chainId")))
            print(f"audit chain expectation resolved from the node: {EXPECT_CHAINID}", flush=True)
        except Exception as e:
            print(f"could not read eth_chainId from {RPC} ({e}); "
                  "audits will run without a chain guard until restarted", flush=True)
    kill_stale_audits()
    atexit.register(_kill_audit_group)
    signal.signal(signal.SIGTERM, _on_sigterm)
    # Bind before starting the workers: if the port is already taken we
    # exit here, before spawning an audit, instead of crash-looping fresh
    # full-chain replays against the node every ThrottleInterval.
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), H)
    threading.Thread(target=follow_head, daemon=True).start()
    threading.Thread(target=run_audit, daemon=True).start()
    # flush: launchd block-buffers stdout to its log file, so without
    # this the startup lines sit invisible until the process exits.
    print(f"everett dashboard on http://0.0.0.0:{PORT} (node {RPC})", flush=True)
    httpd.serve_forever()
