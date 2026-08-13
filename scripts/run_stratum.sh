#!/usr/bin/env bash
# Build and run the KawPow stratum sidecar against a local Everett node.
#   NODE=http://127.0.0.1:8545 LISTEN=:3333 scripts/run_stratum.sh
# The node must run with EVERETT_KAWPOW=1 and --http (api eth) reachable.
# Point a miner at it:  kawpowminer -U -P stratum+tcp://0xYou@<host>:3333
# (scheme matters: stratum+tcp = plain mode 0, the dialect this sidecar
#  speaks; bare stratum:// autodetects into dialects it doesn't — see
#  stratum/README.md)
set -euo pipefail
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="/opt/homebrew/bin:$PATH"
cd "$EVERETT/stratum"
go build -o "$EVERETT/build/kawpow-stratum" .
exec "$EVERETT/build/kawpow-stratum" \
  -node "${NODE:-http://127.0.0.1:8545}" \
  -listen "${LISTEN:-:3333}"
