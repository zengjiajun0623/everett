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
