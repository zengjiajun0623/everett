#!/usr/bin/env python3
"""Record who connects to this node, because nothing else does.

On 2026-08-15 a full-chain scan turned up 14 blocks from an address nobody
could identify. The obvious question -- which peer was connected when they
were mined -- had no answer: at INFO verbosity core-geth logs only
"Looking for peers peercount=N", with no enode, no address, no client
string. Peer identity exists ONLY in a live admin_peers call, so the moment
a peer disconnects, who they were is gone. The one external participant we
can name is named because a human happened to run admin_peers while they
were still connected and pasted it into the RUNBOOK.

Log rotation was the wrong suspect and worth stating so: raising retention
would have preserved nothing, since the identity was never written down.

One line per unique peer, so this stays kilobytes indefinitely. Called once
a minute from liveness_watch.sh, which already polls the node.
"""
import json, os, sys, time, urllib.request

RPC = os.environ.get("RPC", "http://127.0.0.1:8545")
EVERETT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.environ.get("PEER_LEDGER", os.path.join(EVERETT, "build", "peers-seen.tsv"))
COLS = ["id", "first_seen", "last_seen", "seen_count", "name", "addrs"]


def rpc(method, params=()):
    req = urllib.request.Request(
        RPC, json.dumps({"jsonrpc": "2.0", "method": method,
                         "params": list(params), "id": 1}).encode(),
        {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r).get("result")


def load():
    rows = {}
    if not os.path.exists(LEDGER):
        return rows
    with open(LEDGER) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == len(COLS) and parts[0] != "id":
                rows[parts[0]] = dict(zip(COLS, parts))
    return rows


def save(rows):
    tmp = LEDGER + ".tmp"
    with open(tmp, "w") as fh:
        fh.write("\t".join(COLS) + "\n")
        for r in sorted(rows.values(), key=lambda r: r["first_seen"]):
            fh.write("\t".join(str(r[c]) for c in COLS) + "\n")
    os.replace(tmp, LEDGER)   # atomic: a reader never sees a half-written ledger


def main():
    try:
        peers = rpc("admin_peers") or []
    except Exception as e:
        print(f"peer_ledger: RPC unreachable ({e})", file=sys.stderr)
        return 1

    rows, now = load(), time.strftime("%Y-%m-%d %H:%M:%S")
    new = []
    for p in peers:
        pid = (p.get("id") or "")[:16]
        if not pid:
            continue
        # A peer redials from a fresh source port constantly, so the port is
        # noise; the host is the identity worth keeping. Hosts accumulate
        # because a roaming peer legitimately has several.
        addr = (p.get("network") or {}).get("remoteAddress", "?")
        host = addr.rsplit(":", 1)[0] if ":" in addr else addr
        name = (p.get("name") or "?").replace("\t", " ")[:60]
        if pid in rows:
            r = rows[pid]
            r["last_seen"], r["name"] = now, name
            r["seen_count"] = str(int(r["seen_count"]) + 1)
            hosts = [h for h in r["addrs"].split(",") if h]
            if host not in hosts:
                hosts.append(host)
                r["addrs"] = ",".join(hosts[-5:])
        else:
            rows[pid] = {"id": pid, "first_seen": now, "last_seen": now,
                         "seen_count": "1", "name": name, "addrs": host}
            new.append((pid, host, name))

    try:
        save(rows)
    except OSError as e:
        # One line, not a traceback: this runs every 60s from the liveness
        # watch, and a persistent failure would otherwise bury the alarm's
        # own output under a repeating stack dump.
        print(f"peer_ledger: cannot write {LEDGER} ({e})", file=sys.stderr)
        return 1
    for pid, host, name in new:
        # Printed so it lands in liveness.log: a join should be visible
        # without anyone thinking to look. Deliberately NOT an iMessage --
        # alerts are for failures, and a new peer is good news.
        print(f"NEW PEER {pid} from {host} ({name})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
