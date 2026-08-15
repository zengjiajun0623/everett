#!/usr/bin/env python3
"""Assert the peer ledger captures a stranger's identity.

The ledger exists for one moment: an unknown node connects, mines, and
leaves. If it records the connection but loses the host or the client
string, it is worse than nothing -- it looks like evidence while answering
none of the questions that get asked afterwards.

So this drives peer_ledger.py against a stub admin_peers carrying a peer we
do not own, and requires the host, the client string, and the announcement
to all survive. Run by scripts/verify_gates.sh, which also breaks the
ledger on purpose to confirm this test goes red.
"""
import json, os, subprocess, sys, tempfile, threading, http.server

FOREIGN_HOST = "79.112.90.198"
FOREIGN_ID = "deadbeefcafe1234" + "0" * 48
FOREIGN_NAME = "CoreGeth/v1.12.23-unstable-10f1ea74/darwin-arm64/go1.25.5"
PEERS = [
    {"id": "bc0f767c1ad49940" + "0" * 48, "name": "CoreGeth/linux-amd64/go1.22.5",
     "network": {"remoteAddress": "192.168.1.158:61214"}},
    {"id": FOREIGN_ID, "name": FOREIGN_NAME,
     "network": {"remoteAddress": FOREIGN_HOST + ":44012"}},
]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"]))
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "result": PEERS}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    failures = []
    try:
        with tempfile.TemporaryDirectory() as td:
            ledger = os.path.join(td, "peers.tsv")
            env = dict(os.environ, RPC=f"http://127.0.0.1:{srv.server_address[1]}",
                       PEER_LEDGER=ledger)
            first = subprocess.run([sys.executable, os.path.join(here, "peer_ledger.py")],
                                   env=env, capture_output=True, text=True)
            if first.returncode != 0:
                failures.append(f"ledger exited {first.returncode}: {first.stderr.strip()}")
            if not os.path.exists(ledger):
                print("FAIL: no ledger written at all", file=sys.stderr)
                return 1
            body = open(ledger).read()
            rows = [r for r in body.strip().split("\n")[1:] if r]

            if FOREIGN_HOST not in body:
                failures.append(f"the stranger's host {FOREIGN_HOST} was not recorded")
            if "go1.25.5" not in body:
                failures.append("the stranger's client string was not recorded")
            if FOREIGN_ID[:16] not in first.stdout:
                failures.append("a new peer was not announced on stdout")
            if len(rows) != 2:
                failures.append(f"expected 2 peers, ledger has {len(rows)}")

            # Re-running must update, never duplicate: this runs every 60s
            # forever, so a per-run append would grow without bound.
            second = subprocess.run([sys.executable, os.path.join(here, "peer_ledger.py")],
                                    env=env, capture_output=True, text=True)
            rows2 = [r for r in open(ledger).read().strip().split("\n")[1:] if r]
            if len(rows2) != 2:
                failures.append(f"re-run duplicated rows: {len(rows2)} (expected 2)")
            if second.stdout.strip():
                failures.append("a known peer was re-announced as new")
    finally:
        srv.shutdown()

    for f in failures:
        print(f"FAIL: {f}", file=sys.stderr)
    if failures:
        return 1
    print("peer ledger: stranger's host, client, and announcement all captured")
    return 0


if __name__ == "__main__":
    sys.exit(main())
