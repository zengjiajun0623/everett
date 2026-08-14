#!/usr/bin/env bash
# Verification loop, gate 2: interrogate the running devnet over RPC and
# prove it matches the constitution. Independent of the Go code by design:
# the schedule is recomputed in Python and compared against on-chain state.
set -euo pipefail
RPC="${RPC:-http://127.0.0.1:8545}"
# EXPECT_CHAINID guards against auditing the wrong chain (default: the
# dev chain; pass EXPECT_CHAINID=15537392 for Wheeler). A DeepSeek audit
# demonstrated the false green this prevents: with a live node on the
# host, the script happily audited a different chain than intended.
EXPECT_CHAINID="${EXPECT_CHAINID:-15537391}"
call() { curl -s -X POST -H 'Content-Type: application/json' --data "$1" "$RPC"; }

echo "== chainId (expect $EXPECT_CHAINID) =="
GOT=$(call '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' | grep -o '0x[0-9a-f]*')
echo "$GOT"
[ "$((GOT))" = "$EXPECT_CHAINID" ] || { echo "FAIL: chainId $((GOT)) != expected $EXPECT_CHAINID (wrong node? set RPC= / EXPECT_CHAINID=)"; exit 1; }

echo "== genesis: London active (baseFeePerGas present), no withdrawalsRoot =="
call '{"jsonrpc":"2.0","id":2,"method":"eth_getBlockByNumber","params":["0x0",false]}' | python3 -c '
import json, sys
b = json.load(sys.stdin)["result"]
assert b and b.get("baseFeePerGas") is not None, "FAIL: no baseFeePerGas at genesis (London/1559 inactive: Art IV burn impossible)"
assert "withdrawalsRoot" not in b or b["withdrawalsRoot"] is None, "FAIL: withdrawalsRoot present at genesis (a PoS field on a PoW chain)"
bf = b["baseFeePerGas"]
print("OK: baseFeePerGas=%s, no withdrawalsRoot" % bf)
'

echo "== supply audit (exact, independent recomputation; uncle- and tx-aware) =="
python3 "$(cd "$(dirname "$0")" && pwd)/burn_audit.py"
# verify_rewards.py remains as the strict single-miner G2 gate (plus genesis
# pinning via EXPECT_GENESIS); it intentionally fails on multi-miner chains.
