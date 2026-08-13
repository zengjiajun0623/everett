#!/usr/bin/env bash
# Package a runnable node for distribution: binary + genesis + runner.
#   NET=wheeler BOOTNODE=enode://... scripts/make_dist.sh
# Networks: wheeler (testnet, chainId 15537392, genesis-wheeler.json)
#           everett (mainnet,  chainId 15537393, genesis.json — Art. VIII!)
set -euo pipefail
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
GETH="$EVERETT/build/core-geth/build/bin/geth"
[ -x "$GETH" ] || { echo "build first: scripts/boot_devnet.sh"; exit 1; }
NET="${NET:-wheeler}"
case "$NET" in
  wheeler) NETWORKID=15537392; GENESIS_FILE=genesis-wheeler.json ;;
  everett) NETWORKID=15537393; GENESIS_FILE=genesis.json ;;
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
