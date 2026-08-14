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
# is LEGACY: it predates the chain-ID split and carries 15537393, the
# reserved mainnet ID. NOTE: chain-keyed activation forces KawPow ON for
# 15537393, so legacy ethash devnet datadirs are NOT usable with current
# binaries; re-init on genesis-dev.json or stay on a pre-flip build.
# genesis.json itself is reserved (Art. VIII); do not run it casually.
case "$GENESIS" in
  genesis-dev.json)     NETWORKID="${NETWORKID:-15537391}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  genesis-devnet.json)  NETWORKID="${NETWORKID:-15537393}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  genesis-wheeler.json) NETWORKID="${NETWORKID:-15537392}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  genesis.json)         NETWORKID="${NETWORKID:-15537393}"; GENESIS_FILE="/etc/everett/$GENESIS" ;;
  # Absolute path: derive the network ID from the genesis CONTENT. The old
  # default (15537391) silently put a node carrying someone else's genesis
  # on the dev network's wire protocol, where it could find no peers and
  # would have been rejected by the ones it wanted.
  /*)                   GENESIS_FILE="$GENESIS" ;;
  *) echo "run-node: unsupported GENESIS='$GENESIS' (use genesis-dev.json, genesis-wheeler.json, genesis.json, genesis-devnet.json [legacy], or an absolute path)" >&2; exit 1 ;;
esac

# Art. VIII: mainnet begins with a launch ceremony, not an env var. The
# reserved genesis ships in the image so ceremony infrastructure can use
# this packaging, but it refuses to start without an explicit
# acknowledgment: a convenience image must not run the reserved chain
# casually. The guard keys on the CONTENT (chain ID 15537393), not the
# filename, so an absolute-path GENESIS or the legacy genesis-devnet.json
# cannot slip past it.
if [ ! -f "$GENESIS_FILE" ]; then
  echo "run-node: genesis file not found: $GENESIS_FILE" >&2
  exit 1
fi
# ONE chainId extraction, used by both the Art VIII guard and the
# networkid default below. Earlier there were two: a line-based one for
# networkid and a whitespace-collapsing one for the guard. Collapsing the
# file to a single line makes BRE `.*` greedy, so that one returned the
# LAST "chainId" in the file; a genesis with any later chainId-shaped key
# read as a different chain in the guard than in --networkid. grep -o
# takes the FIRST match and never spans keys.
genesis_chainid() {
  tr -d ' \n\t\r' < "$1" | grep -o '"chainId":[0-9][0-9]*' | head -1 | cut -d: -f2
}
GENESIS_CHAINID=$(genesis_chainid "$GENESIS_FILE")
if [ "$GENESIS_CHAINID" = "15537393" ] && [ "${EVERETT_ART_VIII_CEREMONY:-0}" != "1" ]; then
  echo "run-node: $GENESIS carries chain ID 15537393, RESERVED for the Article VIII launch ceremony (CONSTITUTION.md)." >&2
  echo "run-node: use genesis-dev.json (devnet) or genesis-wheeler.json (testnet); set EVERETT_ART_VIII_CEREMONY=1 only as part of the ceremony." >&2
  echo "run-node: (legacy genesis-devnet.json stacks: those datadirs need a pre-flip build anyway; see docker/README.md.)" >&2
  exit 1
fi

# Absolute-path genesis: derive networkid from the same extraction the
# guard used. The old default (15537391) put a node carrying someone
# else's genesis on the dev network's wire protocol.
if [ -z "${NETWORKID:-}" ]; then
  NETWORKID="$GENESIS_CHAINID"
  [ -n "$NETWORKID" ] || { echo "run-node: cannot read chainId from $GENESIS_FILE; pass NETWORKID explicitly" >&2; exit 1; }
fi

mkdir -p "$DATADIR"

CHAINMARK="$DATADIR/.everett-chainid"
if [ ! -d "$DATADIR/geth/chaindata" ]; then
  echo "== init chain from $GENESIS_FILE =="
  geth --datadir "$DATADIR" init "$GENESIS_FILE"
  echo "$GENESIS_CHAINID" > "$CHAINMARK"
else
  # A volume holds whatever chain it was INITIALIZED with. Switching
  # GENESIS on an existing volume (the documented way to move a stack from
  # devnet to Wheeler) used to keep serving the OLD chain under the NEW
  # --networkid: every handshake fails on the genesis mismatch, so the node
  # sits at zero peers on old blocks with no error, and the operator
  # believes they joined. Refuse instead. boot_devnet.sh guards the same
  # scenario for the source path.
  if [ ! -f "$CHAINMARK" ]; then
    # Volume from an older image: identify it once, then cache.
    # eth.chainId() has no console output formatter in the pinned tree, so
    # it returns the raw RPC QUANTITY: "0xed14f0", not 15537392. Accepting
    # only decimal digits therefore discarded every real answer and made
    # this guard a permanent no-op for exactly the legacy volumes it
    # exists to protect. Probe on dedicated ports too: the defaults are
    # the ones a running node already holds.
    HAVE=$(geth --datadir "$DATADIR" --port 30399 --authrpc.port 8559 --nodiscover --maxpeers 0 \
      console --exec 'eth.chainId()' 2>/dev/null | tr -d '"' | tr -d '\r')
    case "$HAVE" in
      0x*|0X*) HAVE=$(printf '%d' "$HAVE" 2>/dev/null || echo "") ;;
      ''|*[!0-9]*) HAVE="" ;;
    esac
    [ -n "$HAVE" ] && echo "$HAVE" > "$CHAINMARK"
  fi
  if [ -f "$CHAINMARK" ]; then
    HAVE=$(cat "$CHAINMARK")
    if [ "$HAVE" != "$GENESIS_CHAINID" ]; then
      echo "run-node: this volume holds chain $HAVE, but GENESIS=$GENESIS selects chain $GENESIS_CHAINID." >&2
      echo "run-node: running it would serve the OLD chain under --networkid $GENESIS_CHAINID:" >&2
      echo "run-node: no peer would accept the handshake and the node would look joined while it is not." >&2
      echo "run-node: use a fresh volume for the new chain, or wipe this one." >&2
      exit 1
    fi
  fi
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
  # core-geth reads --miner.threads 0 as "use every core" and only a
  # NEGATIVE value disables local mining (consensus/ethash/sealer.go:
  # `if threads == 0 { threads = runtime.NumCPU() }`). MINER_THREADS=0 is
  # documented here and defaulted in compose to mean "serve work to the
  # GPU miner and do no hashing", so translate it to -1. Without this the
  # default stack quietly CPU-mines KawPow on all cores and builds a
  # ~1 GiB DAG in RAM.
  THREADS_FLAG="$MINER_THREADS"
  [ "$MINER_THREADS" = "0" ] && THREADS_FLAG=-1
  ARGS+=(--mine --miner.threads "$THREADS_FLAG"
         --miner.etherbase "${ETHERBASE:?run-node: set ETHERBASE=0xYourAddress to mine}")
fi

exec geth "${ARGS[@]}"
