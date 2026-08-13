#!/usr/bin/env bash
# Package a runnable Everett node for distribution: binary + genesis + runner.
# Output: dist/everett-node-<platform>.tar.gz
set -euo pipefail
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
GETH="$EVERETT/build/core-geth/build/bin/geth"
[ -x "$GETH" ] || { echo "build first: scripts/boot_devnet.sh"; exit 1; }
PLAT="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
STAGE="$EVERETT/dist/everett-node-$PLAT"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp "$GETH" "$STAGE/geth"
cp "$EVERETT/genesis-devnet.json" "$EVERETT/genesis.json" "$STAGE/"
cp "$EVERETT/dist/run-node.sh" "$STAGE/"
cp "$EVERETT/dist/NODE_README.md" "$STAGE/README.md"
chmod +x "$STAGE/geth" "$STAGE/run-node.sh"
tar -C "$EVERETT/dist" -czf "$EVERETT/dist/everett-node-$PLAT.tar.gz" "everett-node-$PLAT"
echo "packaged: dist/everett-node-$PLAT.tar.gz ($(du -h "$EVERETT/dist/everett-node-$PLAT.tar.gz" | cut -f1))"
