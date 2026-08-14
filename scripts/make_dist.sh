#!/usr/bin/env bash
# Package a runnable node for distribution: binary + genesis + runner.
#   NET=wheeler BOOTNODE=enode://... scripts/make_dist.sh
# Networks: wheeler (testnet, chainId 15537392, genesis-wheeler.json)
#           everett (mainnet,  chainId 15537393, genesis.json — Art. VIII!)
set -euo pipefail
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
SRC="${COREGETH_DIR:-$EVERETT/build/core-geth}"
GETH="$SRC/build/bin/geth"
[ -x "$GETH" ] || { echo "build first: scripts/deploy_node.sh (or COREGETH_DIR=... pointing at a built tree)"; exit 1; }

# A package is a consensus artifact: prove the tree it came from is the
# pinned, patched one and that the binary is not older than its sources.
# Shipping a stale binary is how a "fixed" consensus bug reaches users
# unfixed.
PIN=$(sed -n 's/^COREGETH_COMMIT="${COREGETH_COMMIT:-\([0-9a-f]\{40\}\)}"/\1/p' "$EVERETT/scripts/ci_prepare.sh")
HAVE=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo none)
[ "$HAVE" = "$PIN" ] || { echo "FAIL: $SRC is at $HAVE, pin is $PIN; re-run scripts/deploy_node.sh"; exit 1; }
for f in kawpow_core.go kawpow_engine.go difficulty_everett.go; do
  cmp -s "$EVERETT/client/$f" "$SRC/consensus/ethash/$f" || {
    echo "FAIL: $SRC/consensus/ethash/$f differs from client/$f; the tree is not the current patch set"; exit 1; }
done
cmp -s "$EVERETT/client/rewards_everett.go" "$SRC/params/mutations/rewards_everett.go" || {
  echo "FAIL: rewards_everett.go in $SRC differs from client/; re-run scripts/deploy_node.sh"; exit 1; }
[ "$GETH" -nt "$SRC/consensus/ethash/kawpow_core.go" ] || {
  echo "FAIL: $GETH is older than its sources; rebuild before packaging"; exit 1; }

NET="${NET:-wheeler}"
case "$NET" in
  wheeler) NETWORKID=15537392; GENESIS_FILE=genesis-wheeler.json ;;
  everett) NETWORKID=15537393; GENESIS_FILE=genesis.json
    # Art. VIII: packaging the reserved mainnet is a ceremony act.
    [ "${EVERETT_ART_VIII_CEREMONY:-0}" = "1" ] || {
      echo "FAIL: NET=everett packages the RESERVED mainnet (15537393)."
      echo "      Set EVERETT_ART_VIII_CEREMONY=1 only as part of the Article VIII ceremony."; exit 1; } ;;
  *) echo "unknown NET=$NET"; exit 1 ;;
esac
: "${BOOTNODE:?set BOOTNODE=enode://...@host:port}"
PLAT="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
STAGE="$EVERETT/dist/$NET-node-$PLAT"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp "$GETH" "$STAGE/geth"
cp "$EVERETT/$GENESIS_FILE" "$STAGE/"
sed -e "s|__NETNAME__|$NET|g" -e "s|__NETWORKID__|$NETWORKID|g" \
    -e "s|__GENESIS__|$GENESIS_FILE|g" -e "s|__BOOTNODE__|$BOOTNODE|g" \
    "$EVERETT/dist/run-node.sh" > "$STAGE/run-node.sh"
sed -e "s|__NETNAME__|$NET|g" -e "s|__NETWORKID__|$NETWORKID|g" \
    "$EVERETT/dist/NODE_README.md" > "$STAGE/README.md"
chmod +x "$STAGE/geth" "$STAGE/run-node.sh"
tar -C "$EVERETT/dist" -czf "$EVERETT/dist/$NET-node-$PLAT.tar.gz" "$NET-node-$PLAT"
echo "packaged: dist/$NET-node-$PLAT.tar.gz ($(du -h "$EVERETT/dist/$NET-node-$PLAT.tar.gz" | cut -f1))"
