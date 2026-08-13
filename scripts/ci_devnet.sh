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
# HERMETIC by construction: dedicated p2p/http/authrpc ports so a live
# node on this host can neither collide with us nor answer for us. A
# DeepSeek audit run demonstrated the failure this prevents: the e2e
# node died on a port bind, the gate polled default 8545, the LIVE
# Wheeler node answered, and the gate reported a false PASS against the
# wrong chain.
E2E_HTTP=8546
"$GETH" --datadir "$DATA" --networkid 15537391 --nodiscover --maxpeers 0 \
  --port 30304 --authrpc.port 8552 \
  --mine --miner.threads 1 \
  --miner.etherbase 0x1000000000000000000000000000000000000001 \
  --http --http.port "$E2E_HTTP" --http.api eth,net,web3 > "$EVERETT/build/ci-node.log" 2>&1 &
NODE=$!
trap 'kill $NODE 2>/dev/null || true' EXIT

# Wait for blocks (DAG generation on a cold CI runner takes a few minutes).
for i in $(seq 1 120); do
  # The gate must be talking to ITS OWN process, alive, on ITS OWN port.
  kill -0 "$NODE" 2>/dev/null || { echo "FAIL: e2e node died"; tail -30 "$EVERETT/build/ci-node.log"; exit 1; }
  n=$(curl -s -m 2 -X POST -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
      "http://127.0.0.1:$E2E_HTTP" | grep -o '0x[0-9a-f]*' || true)
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
    r = urllib.request.Request("http://127.0.0.1:8546",
        json.dumps({"jsonrpc":"2.0","id":1,"method":m,"params":p}).encode(),
        {"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(r))["result"]
# Identity assertions: THE dev chain, not merely AN Everett chain. The
# empty-state-root check alone is satisfied by every Everett genesis.
cid = rpc("eth_chainId")
assert cid == "0xed14ef", f"wrong chain: eth_chainId={cid}, want 0xed14ef (15537391 dev)"
g = rpc("eth_getBlockByNumber", ["0x0", False])
assert g["hash"] == "0xe07a390f57e263002b61552a644eee82b4548303e1460f4ecca1d30662e2d742", f"wrong genesis: {g['hash']}"
assert g["stateRoot"] == "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421", "genesis state not empty (Art. V.1)"
print("genesis identity OK:", g["hash"])
PY

RPC=http://127.0.0.1:8546 EXPECT_CHAINID=15537391 python3 "$EVERETT/scripts/burn_audit.py"
echo "devnet e2e gate PASSED"
