#!/usr/bin/env bash
# Run an Everett node. First run initializes the chain from genesis; after
# that your chain persists in ./everett-data.
#
#   ./run-node.sh                          join the network, no mining
#   MINE=1 ETHERBASE=0xYou ./run-node.sh   join and mine to your address
#   BOOTNODE=enode://... ./run-node.sh     use a different entry point
set -euo pipefail
cd "$(dirname "$0")"
DATADIR="./everett-data"

# Default bootnode: replace with the current network entry point if stale.
BOOTNODE="${BOOTNODE:-enode://a69b5064e52823fcd50a25bc9b4570efac9538bd4bf134ab27f2bc87a4a392c13020345f668666eb338f1e9d6ae3685f6d46591adee3a31dc0bfc11e39406895@192.168.1.172:30303}"

if [ ! -d "$DATADIR/geth/chaindata" ]; then
  ./geth --datadir "$DATADIR" init genesis-devnet.json
fi

ARGS=(--datadir "$DATADIR" --networkid 15537393 --port "${PORT:-30303}"
      --authrpc.port "${AUTHRPC:-8551}"
      --bootnodes "$BOOTNODE" --nat any
      --http --http.port "${HTTP_PORT:-8545}" --http.api eth,net,web3)
if [ "${MINE:-0}" = "1" ]; then
  ARGS+=(--mine --miner.threads "${THREADS:-1}"
         --miner.etherbase "${ETHERBASE:?set ETHERBASE=0xYourAddress to mine}")
fi
exec ./geth "${ARGS[@]}"
