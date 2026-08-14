#!/usr/bin/env bash
# Build and run the KawPow stratum sidecar against a local Everett node.
#   NODE=http://127.0.0.1:8545 LISTEN=:3333 scripts/run_stratum.sh
# The node must run with EVERETT_KAWPOW=1 and --http (api eth) reachable.
# Point a miner at it:  kawpowminer -U -P stratum+tcp://worker@<host>:3333
# (scheme matters: stratum+tcp = plain mode 0, the dialect this sidecar
#  speaks; bare stratum:// autodetects into dialects it doesn't, see
#  stratum/README.md). Payouts go to the NODE's --miner.etherbase; the
#  stratum username is logging only.
set -euo pipefail
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="/opt/homebrew/bin:$PATH"
BIN="$EVERETT/build/kawpow-stratum"
LISTEN="${LISTEN:-:3333}"

# On an operator host, $BIN is the binary the launchd sidecar
# (com.everett.stratum, KeepAlive) executes and :3333 is the port it owns.
# Rebuilding that path relinks the live service's binary, and binding that
# port makes one of the two processes exit on bind failure: either way the
# GPU fleet's connection dies. Deliberate redeploys set FORCE=1 (and
# restart the service); everything else gets its own path and port.
if pgrep -f "^$BIN" >/dev/null 2>&1 && [ "${FORCE:-0}" != "1" ]; then
  echo "FAIL: the production stratum sidecar is running from $BIN." >&2
  echo "      Building here would relink the live service's binary." >&2
  echo "      For a scratch instance:" >&2
  echo "        cd stratum && go build -o /tmp/kawpow-stratum . \\" >&2
  echo "          && /tmp/kawpow-stratum -node \${NODE:-http://127.0.0.1:8545} -listen :3334" >&2
  echo "      To redeploy the service on purpose: FORCE=1 $0, then" >&2
  echo "        launchctl unload/load ~/Library/LaunchAgents/com.everett.stratum.plist" >&2
  exit 1
fi

cd "$EVERETT/stratum"
go build -o "$BIN" .
exec "$BIN" \
  -node "${NODE:-http://127.0.0.1:8545}" \
  -listen "$LISTEN"
