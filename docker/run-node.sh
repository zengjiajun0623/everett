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
GENESIS="${GENESIS:-genesis-dev.json}"
BOOTNODE="${BOOTNODE:-}"
MINE="${MINE:-0}"
MINER_THREADS="${MINER_THREADS:-0}"
PORT="${PORT:-30303}"

# genesis-dev.json (15537391) is the canonical devnet. genesis-devnet.json
# is LEGACY: it predates the chain-ID split and carries 15537393, the ID
# reserved for the mainnet launch ceremony — kept only so existing stacks
# keep working. genesis.json itself is reserved (Art. VIII); do not run it
# casually.
case "$GENESIS" in
  genesis-dev.json)     NETWORKID="${NETWORKID:-15537391}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  genesis-devnet.json)  NETWORKID="${NETWORKID:-15537393}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  genesis-wheeler.json) NETWORKID="${NETWORKID:-15537392}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  genesis.json)         NETWORKID="${NETWORKID:-15537393}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  /*)                   NETWORKID="${NETWORKID:-15537391}"; GENESIS_FILE="$GENESIS" ;;
  *) echo "run-node: unsupported GENESIS='$GENESIS' (use genesis-dev.json, genesis-wheeler.json, genesis.json, genesis-devnet.json [legacy], or an absolute path)" >&2; exit 1 ;;
esac

# Art. VIII: mainnet begins with a launch ceremony, not an env var. The
# reserved genesis ships in the image so ceremony infrastructure can use
# this packaging, but it refuses to start without an explicit
# acknowledgment — a convenience image must not run the reserved chain
# casually.
if [ "$GENESIS" = "genesis.json" ] && [ "${EVERETT_ART_VIII_CEREMONY:-0}" != "1" ]; then
  echo "run-node: genesis.json (chain ID 15537393) is RESERVED for the Article VIII launch ceremony (CONSTITUTION.md)." >&2
  echo "run-node: use genesis-dev.json (devnet) or genesis-wheeler.json (testnet); set EVERETT_ART_VIII_CEREMONY=1 only as part of the ceremony." >&2
  exit 1
fi

mkdir -p "$DATADIR"

if [ ! -d "$DATADIR/geth/chaindata" ]; then
  echo "== init chain from $GENESIS_FILE =="
  geth --datadir "$DATADIR" init "$GENESIS_FILE"
fi

# vhosts: only the hostnames that actually reach this RPC — the miner
# (Host: node), the healthcheck and host-published curls (localhost /
# 127.0.0.1). A wildcard would reopen the DNS-rebinding hole the vhosts
# check exists to close. Extend HTTP_VHOSTS if you front it differently.
ARGS=(--datadir "$DATADIR" --networkid "$NETWORKID" --port "$PORT"
      --http --http.addr 0.0.0.0 --http.port 8545 --http.api eth,net,web3
      --http.vhosts "${HTTP_VHOSTS:-node,localhost,127.0.0.1}")

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
