#!/usr/bin/env bash
# Deploy the repo's current consensus code to the PRODUCTION node tree.
#
# Why this exists: verification gates deliberately build in an isolated
# tree (build/ci/core-geth) so they can never disturb the live node. That
# isolation means a green gate run proves nothing about what the operator
# node is actually executing. An audit round found exactly that gap: the
# 64-bit KawPow DAG fix was gate-verified while the live Wheeler node kept
# running the pre-fix binary. Deployment is now an explicit, verified act.
#
#   scripts/deploy_node.sh              prep + build + verify, no restart
#   RESTART=1 scripts/deploy_node.sh    also restart the launchd node and
#                                       prove the chain continues
set -euo pipefail
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
PROD="$EVERETT/build/core-geth"
GETH="$PROD/build/bin/geth"
PLIST="$HOME/Library/LaunchAgents/com.everett.wheeler-node.plist"
RPC="${RPC:-http://127.0.0.1:8545}"

echo "== 1. prep the production tree from repo HEAD =="
COREGETH_DIR="$PROD" bash "$EVERETT/scripts/ci_prepare.sh"

echo "== 2. build =="
(cd "$PROD" && make geth)

echo "== 3. verify the binary matches the repo's consensus sources =="
for f in kawpow_core.go kawpow_engine.go difficulty_everett.go; do
  cmp -s "$EVERETT/client/$f" "$PROD/consensus/ethash/$f" \
    || { echo "FAIL: $PROD/consensus/ethash/$f != client/$f"; exit 1; }
done
cmp -s "$EVERETT/client/rewards_everett.go" "$PROD/params/mutations/rewards_everett.go" \
  || { echo "FAIL: rewards_everett.go mismatch"; exit 1; }
[ "$GETH" -nt "$PROD/consensus/ethash/kawpow_core.go" ] \
  || { echo "FAIL: $GETH is older than its sources"; exit 1; }
echo "OK: $GETH built from the current patch set"

if [ "${RESTART:-0}" != "1" ]; then
  echo
  echo "Binary is staged but the RUNNING node still executes the old image."
  echo "Restart to deploy:  RESTART=1 scripts/deploy_node.sh"
  exit 0
fi

echo "== 4. restart the launchd node =="
BEFORE=$(curl -s -m 5 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' "$RPC" \
  | grep -o '0x[0-9a-f]*' || echo 0x0)
echo "height before: $((BEFORE))"
launchctl unload "$PLIST"
launchctl load "$PLIST"

echo "== 5. prove the chain continues on the new binary =="
for _ in $(seq 1 40); do
  sleep 5
  AFTER=$(curl -s -m 5 -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' "$RPC" \
    | grep -o '0x[0-9a-f]*' || true)
  [ -n "$AFTER" ] || continue
  # Height must not go BACKWARD (that would mean a different datadir or a
  # re-init), and must eventually exceed the pre-restart height.
  [ $((AFTER)) -ge $((BEFORE)) ] || { echo "FAIL: height went backward: $((AFTER)) < $((BEFORE))"; exit 1; }
  if [ $((AFTER)) -gt $((BEFORE)) ]; then
    echo "OK: height $((BEFORE)) -> $((AFTER)) on the new binary"
    exec env RPC="$RPC" EXPECT_CHAINID=15537392 python3 "$EVERETT/scripts/burn_audit.py"
  fi
done
echo "FAIL: no new block within 200s of the restart; check build/wheeler.log" >&2
exit 1
