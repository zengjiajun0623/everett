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
# Content checks, not greps for an identifier: a marker can be present
# while the hook BODY is an older version, which is exactly how a stale
# hook survived undetected in the production tree.
python3 "$EVERETT/scripts/apply_hook.py" --verify "$PROD/params/mutations/rewards.go" \
  || { echo "FAIL: Article III reward hook missing or outdated in $PROD"; exit 1; }
python3 "$EVERETT/scripts/apply_daa_hook.py" --verify "$PROD/consensus/ethash/consensus.go" \
  || { echo "FAIL: ASERT difficulty hook missing or outdated in $PROD"; exit 1; }
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
# The original check watched the height climb, which a still-running OLD
# node produces just as well. The replacement then hashed "the file at
# $GETH", which is the file we had just built, so it could never disagree
# with BUILT_SHA either. Both were proofs of nothing.
#
# Ask LAUNCHD which process it manages instead of guessing with pgrep: a
# devnet started from this same tree has the identical argv[0], so the
# lowest matching pid could name a different node entirely.
LABEL=com.everett.wheeler-node
NEW_PID=""
for _ in $(seq 1 40); do
  sleep 5
  CAND=$(launchctl list "$LABEL" 2>/dev/null | awk -F'= ' '/"PID"/ {gsub(/[^0-9]/,"",$2); print $2}')
  [ -n "$CAND" ] || continue
  [ "$CAND" != "${OLD_PID:-}" ] || continue
  NEW_PID="$CAND"
  break
done
[ -n "$NEW_PID" ] || {
  echo "FAIL: launchd reports no NEW pid for $LABEL within 200s (old pid ${OLD_PID:-none} may still be running)." >&2
  echo "      The node was NOT redeployed. Check build/wheeler.log and launchctl print gui/$UID/$LABEL." >&2
  exit 1; }

# Identity, not a tautology. Hashing "the file at $GETH" re-hashed the file
# we had just built and could never disagree with BUILT_SHA. What must be
# proven is that the RUNNING process is executing THAT file: compare the
# inode the process holds open as its text image against the inode we
# built, and require the process to have started after the binary's mtime.
BUILT_INODE=$(stat -f %i "$GETH")
RUN_INODE=$(lsof -p "$NEW_PID" 2>/dev/null | awk '$4 == "txt" {print $(NF-1); exit}')
[ "$RUN_INODE" = "$BUILT_INODE" ] || {
  echo "FAIL: pid $NEW_PID executes inode ${RUN_INODE:-unknown}, but the binary built above is inode $BUILT_INODE." >&2
  echo "      The running node is NOT the image this deploy produced." >&2; exit 1; }
BIN_EPOCH=$(stat -f %m "$GETH")
PID_EPOCH=$(ps -o lstart= -p "$NEW_PID" | xargs -I{} date -j -f "%a %b %d %T %Y" "{}" +%s 2>/dev/null || echo 0)
[ "$PID_EPOCH" -ge "$BIN_EPOCH" ] 2>/dev/null || {
  echo "WARN: could not prove pid $NEW_PID started after the build (pid=$PID_EPOCH bin=$BIN_EPOCH)" >&2; }
echo "OK: pid ${OLD_PID:-none} -> $NEW_PID (launchd), executing inode $RUN_INODE = the binary built above, sha256 ${BUILT_SHA:0:16}"

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
