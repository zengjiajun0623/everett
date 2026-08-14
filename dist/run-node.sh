#!/usr/bin/env bash
# Run a __NETNAME__ node. First run initializes the chain from genesis; after
# that your chain persists in ./__NETNAME__-data.
#
#   ./run-node.sh                          join the network, no mining
#   MINE=1 ETHERBASE=0xYou ./run-node.sh   join and mine to your address
#   BOOTNODE=enode://... ./run-node.sh     use a different entry point
set -euo pipefail
cd "$(dirname "$0")"
DATADIR="./__NETNAME__-data"

# Art. VIII: chain ID 15537393 is the reserved mainnet, which begins with a
# launch ceremony, not by unpacking a tarball. Same guard the container
# entrypoint carries (docker/run-node.sh); a distribution package must not
# be the one channel that starts the reserved chain silently.
if [ "__NETWORKID__" = "15537393" ] && [ "${EVERETT_ART_VIII_CEREMONY:-0}" != "1" ]; then
  echo "run-node: this package targets chain ID 15537393, RESERVED for the Article VIII launch ceremony (CONSTITUTION.md)." >&2
  echo "run-node: use a wheeler (testnet) package; set EVERETT_ART_VIII_CEREMONY=1 only as part of the ceremony." >&2
  exit 1
fi

# Default bootnode: replace with the current network entry point if stale.
BOOTNODE="${BOOTNODE:-__BOOTNODE__}"

if [ ! -d "$DATADIR/geth/chaindata" ]; then
  ./geth --datadir "$DATADIR" init __GENESIS__
fi

ARGS=(--datadir "$DATADIR" --networkid __NETWORKID__ --port "${PORT:-30303}"
      --authrpc.port "${AUTHRPC:-8551}"
      --bootnodes "$BOOTNODE" --nat any
      --http --http.port "${HTTP_PORT:-8545}" --http.api eth,net,web3)
if [ "${MINE:-0}" = "1" ]; then
  ARGS+=(--mine --miner.threads "${THREADS:-1}"
         --miner.etherbase "${ETHERBASE:?set ETHERBASE=0xYourAddress to mine}")
fi
exec ./geth "${ARGS[@]}"
