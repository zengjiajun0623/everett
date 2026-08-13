#!/usr/bin/env bash
# Everett node entrypoint (container). Mirrors scripts/boot_devnet.sh and
# dist/run-node.sh, adapted for the image layout:
#   - datadir      /data   (bind-mounted volume on the host)
#   - genesis      /etc/everett/*.json, selected by GENESIS
#   - RPC          0.0.0.0:8545 inside the container; the compose file
#                  publishes it to 127.0.0.1:8545 on the host ONLY.
#   - mining       MINE=1 + ETHERBASE required; MINER_THREADS=0 serves
#                  work to the external GPU miner without CPU mining.
set -euo pipefail

DATADIR="${DATADIR:-/data}"
GENESIS="${GENESIS:-genesis-devnet.json}"
BOOTNODE="${BOOTNODE:-}"
MINE="${MINE:-0}"
MINER_THREADS="${MINER_THREADS:-0}"
PORT="${PORT:-30303}"

case "$GENESIS" in
  genesis-devnet.json)  NETWORKID="${NETWORKID:-15537393}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  genesis-wheeler.json) NETWORKID="${NETWORKID:-15537392}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  genesis.json)         NETWORKID="${NETWORKID:-15537393}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  /*)                   NETWORKID="${NETWORKID:-15537393}"; GENESIS_FILE="$GENESIS" ;;
  *) echo "run-node: unsupported GENESIS='$GENESIS' (use genesis-devnet.json, genesis-wheeler.json, genesis.json, or an absolute path)" >&2; exit 1 ;;
esac

mkdir -p "$DATADIR"

if [ ! -d "$DATADIR/geth/chaindata" ]; then
  echo "== init chain from $GENESIS_FILE =="
  geth --datadir "$DATADIR" init "$GENESIS_FILE"
fi

ARGS=(--datadir "$DATADIR" --networkid "$NETWORKID" --port "$PORT"
      --http --http.addr 0.0.0.0 --http.port 8545 --http.api eth,net,web3
      --http.vhosts '*')

# Devnet: private, no discovery. Wheeler: public, join via bootnode(s).
if [ -n "$BOOTNODE" ]; then
  ARGS+=(--bootnodes "$BOOTNODE")
else
  ARGS+=(--nodiscover)
fi

if [ "${MINE:-0}" = "1" ]; then
  # MINER_THREADS=0 = serve eth_getWork only; the GPU miner mines. ETHERBASE
  # is a hard requirement: no constitutional revenue to an unset address.
  ARGS+=(--mine --miner.threads "$MINER_THREADS"
         --miner.etherbase "${ETHERBASE:?run-node: set ETHERBASE=0xYourAddress to mine}")
fi

exec geth "${ARGS[@]}"
