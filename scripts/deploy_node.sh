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
# EVERETT_DEPLOY=1 is the deliberate exception to ci_prepare's refusal to
# touch a tree a live node runs from. This script is that deliberate case.
COREGETH_DIR="$PROD" EVERETT_DEPLOY=1 bash "$EVERETT/scripts/ci_prepare.sh"

echo "== 2. build =="
(cd "$PROD" && make geth)

echo "== 3. verify the tree really carries this patch set =="
# NOT a cmp of the copied files against client/: step 1 just copied them
# there, so such a comparison compares a file with a copy of itself made
# seconds earlier and cannot fail. What needs proving is the part copying
# does not cover: the six hook-injected consensus blocks, which are
# idempotent by marker and so can silently persist at an older version.
python3 "$EVERETT/scripts/apply_kawpow_hooks.py" --verify \
  "$PROD/consensus/ethash/consensus.go" "$PROD/consensus/ethash/sealer.go" \
  "$PROD/eth/backend.go" "$PROD/cmd/utils/flags.go" \
  || { echo "FAIL: KawPow hooks missing or outdated in $PROD"; exit 1; }
grep -q "everettRewards" "$PROD/params/mutations/rewards.go" \
  || { echo "FAIL: Article III reward hook missing from $PROD/params/mutations/rewards.go"; exit 1; }
grep -q "everettCalcDifficulty\|EverettASERT\|asert" "$PROD/consensus/ethash/consensus.go" \
  || { echo "FAIL: ASERT difficulty hook missing from $PROD/consensus/ethash/consensus.go"; exit 1; }
[ "$GETH" -nt "$PROD/consensus/ethash/kawpow_core.go" ] \
  || { echo "FAIL: $GETH is older than its sources; the build did not produce it"; exit 1; }
BUILT_SHA=$(shasum -a 256 "$GETH" | cut -d' ' -f1)
echo "OK: hooks current, binary newer than sources, sha256 ${BUILT_SHA:0:16}"

if [ "${RESTART:-0}" != "1" ]; then
  echo
  echo "Binary is staged but the RUNNING node still executes the old image."
  echo "Restart to deploy:  RESTART=1 scripts/deploy_node.sh"
  exit 0
fi

echo "== 4. restart the launchd node =="
# launchctl unload/load return 0 even when they do nothing (a moved plist,
# a job in another domain, a node started by hand), so their exit codes
# prove nothing. Check the preconditions ourselves.
[ -f "$PLIST" ] || { echo "FAIL: no plist at $PLIST; this node is not launchd-managed by that label"; exit 1; }
PLIST_EXEC=$(plutil -extract ProgramArguments.0 raw "$PLIST" 2>/dev/null || true)
[ "$PLIST_EXEC" = "$GETH" ] || {
  echo "FAIL: $PLIST runs '$PLIST_EXEC', not the binary this script builds ($GETH)."
  echo "      Deploying would leave the running node on a different image."; exit 1; }

OLD_PID=$(pgrep -f "^$GETH" | head -1 || true)
BEFORE=$(curl -s -m 5 -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' "$RPC" \
  | grep -o '0x[0-9a-f]*' || echo 0x0)
echo "height before: $((BEFORE)), old pid: ${OLD_PID:-none}"
launchctl unload "$PLIST" || true
launchctl load "$PLIST" || true

echo "== 5. prove the RUNNING PROCESS is the binary we just built =="
# The old check watched the height climb. A height climbing is exactly what
# a still-running OLD node also produces, so it could not tell deployment
# from no-op. Process identity can: a different pid, executing a file whose
# sha256 is the one we built, started after the build.
NEW_PID=""
for _ in $(seq 1 40); do
  sleep 5
  CAND=$(pgrep -f "^$GETH" | head -1 || true)
  [ -n "$CAND" ] || continue
  [ "$CAND" != "${OLD_PID:-}" ] || continue
  NEW_PID="$CAND"
  break
done
[ -n "$NEW_PID" ] || {
  echo "FAIL: no NEW geth process for $GETH within 200s (old pid ${OLD_PID:-none} may still be running)." >&2
  echo "      The node was NOT redeployed. Check build/wheeler.log and launchctl print." >&2
  exit 1; }
RUN_SHA=$(shasum -a 256 "$(ps -o comm= -p "$NEW_PID" | sed 's/^ *//')" 2>/dev/null | cut -d' ' -f1 || true)
[ "$RUN_SHA" = "$BUILT_SHA" ] || {
  echo "FAIL: pid $NEW_PID runs a binary with sha256 ${RUN_SHA:0:16}, expected ${BUILT_SHA:0:16}" >&2; exit 1; }
echo "OK: pid ${OLD_PID:-none} -> $NEW_PID, running sha256 ${RUN_SHA:0:16} (the binary built above)"

echo "== 6. prove the chain continued across the restart =="
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
    echo "OK: height $((BEFORE)) -> $((AFTER))"
    exec env RPC="$RPC" EXPECT_CHAINID=15537392 python3 "$EVERETT/scripts/burn_audit.py"
  fi
done
echo "FAIL: no new block within 200s of the restart; check build/wheeler.log" >&2
exit 1
