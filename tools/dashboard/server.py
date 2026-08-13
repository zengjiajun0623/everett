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
import json
import os
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RPC = os.environ.get("RPC", "http://127.0.0.1:8545")
PORT = int(os.environ.get("PORT", "8484"))
HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT = os.path.join(HERE, "..", "..", "scripts", "burn_audit.py")
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
            # re-check the last few for reorgs, then fetch anything new
            recheck = range(max(lo, known - 8), known + 1) if known else []
            fetch = list(recheck) + list(range(max(lo, known + 1), head + 1))
            for n in fetch:
                b = fetch_block(n)
                if b is None:
                    continue
                with S.lock:
                    old = S.blocks.get(n)
                    if old is None or old["hash"] != b["hash"]:
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


def run_audit():
    while True:
        try:
            out = subprocess.run(
                ["python3", AUDIT], env={**os.environ, "RPC": RPC, "EXPECT_CHAINID": "15537392"},
                capture_output=True, text=True, timeout=600)
            lines = out.stdout.strip().splitlines() or [
                "no stdout; stderr tail:"] + out.stderr.strip().splitlines()[-4:]
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
    threading.Thread(target=follow_head, daemon=True).start()
    threading.Thread(target=run_audit, daemon=True).start()
    print(f"everett dashboard on http://0.0.0.0:{PORT} (node {RPC})")
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
