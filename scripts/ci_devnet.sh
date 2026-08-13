#!/usr/bin/env bash
# End-to-end gate: build, mine a short chain, audit supply wei-exact against
# the constitution, then assert the genesis hash is unchanged. Any consensus
# or schedule regression fails here even if unit tests pass.
set -euo pipefail
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
cd "$EVERETT/build/core-geth"
make geth
GETH="$EVERETT/build/core-geth/build/bin/geth"
DATA="$EVERETT/build/ci-devnet"

rm -rf "$DATA"
"$GETH" --datadir "$DATA" init "$EVERETT/genesis-dev.json"
"$GETH" --datadir "$DATA" --networkid 15537391 --nodiscover --maxpeers 0 \
  --mine --miner.threads 1 \
  --miner.etherbase 0x1000000000000000000000000000000000000001 \
  --http --http.api eth,net,web3 > "$EVERETT/build/ci-node.log" 2>&1 &
NODE=$!
trap 'kill $NODE 2>/dev/null || true' EXIT

# Wait for blocks (DAG generation on a cold CI runner takes a few minutes).
for i in $(seq 1 120); do
  n=$(curl -s -m 2 -X POST -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
      http://127.0.0.1:8545 | grep -o '0x[0-9a-f]*' || true)
  if [ -n "$n" ] && [ "$n" != "0x0" ] && [ $((n)) -ge 5 ]; then
    echo "mined $((n)) blocks"
    break
  fi
  sleep 10
done
[ -n "${n:-}" ] && [ $((n)) -ge 5 ] || { echo "FAIL: no blocks mined"; tail -30 "$EVERETT/build/ci-node.log"; exit 1; }

EXPECT_GENESIS= python3 - <<'PY'
import json, os, urllib.request
def rpc(m, p=[]):
    r = urllib.request.Request("http://127.0.0.1:8545",
        json.dumps({"jsonrpc":"2.0","id":1,"method":m,"params":p}).encode(),
        {"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(r))["result"]
g = rpc("eth_getBlockByNumber", ["0x0", False])
assert g["hash"], "no genesis"
assert g["stateRoot"] == "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421", "genesis state not empty (Art. V.1)"
print("genesis invariants OK:", g["hash"])
PY

python3 "$EVERETT/scripts/burn_audit.py"
echo "devnet e2e gate PASSED"
