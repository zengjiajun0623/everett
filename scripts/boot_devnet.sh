#!/usr/bin/env bash
# Everett devnet boot: clone core-geth, apply the reward patch, run unit
# tests (gate), build, init genesis, mine. Fail fast at every step.
set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$EVERETT/build"
DATADIR="$WORK/devnet-data"
mkdir -p "$WORK"

# ONE canonical prep: ci_prepare.sh (clone, compat, all Everett files, all
# five hooks including KawPow and chain-keyed activation). boot_devnet.sh
# previously duplicated a pre-KawPow subset of this, which meant a fresh
# machine following the README built a geth that could not validate
# Wheeler v2 or mainnet. Never fork the prep again.
# Honor COREGETH_DIR: ci_prepare.sh preps whatever tree that names, so a
# hardcoded path here would prep one tree and then test and build another.
export COREGETH_DIR="${COREGETH_DIR:-$WORK/core-geth}"
bash "$EVERETT/scripts/ci_prepare.sh"

cd "$COREGETH_DIR"
echo "== unit tests (verification gates: schedule + DAA incl. exhaustive enumeration + KawPow) =="
go test ./params/mutations/ -run TestEverett -v
go test ./consensus/ethash/ -run TestASERT -v
go test ./consensus/ethash/ -run TestKawPow -timeout 40m

echo "== build =="
make geth
GETH="$COREGETH_DIR/build/bin/geth"

echo "== init genesis =="
# Devnet genesis (0x20000 difficulty) by default: the production difficulty
# guess stalls CPU miners. Override with GENESIS=genesis.json for prod tests.
# genesis-dev.json (chainId 15537391) is the canonical devnet. The legacy
# genesis-devnet.json carries the RESERVED mainnet chainId 15537393; since
# chain-keyed activation forces KawPow on that ID, legacy ethash devnet
# datadirs need RESET=1 (re-init on genesis-dev.json) under current builds.
# The chain persists across runs; RESET=1 wipes it and starts from genesis.
GENESIS_FILE="$EVERETT/${GENESIS:-genesis-dev.json}"
if [ "${RESET:-0}" = "1" ] || [ ! -d "$DATADIR/geth/chaindata" ]; then
  rm -rf "$DATADIR"
  "$GETH" --datadir "$DATADIR" init "$GENESIS_FILE"
else
  echo "existing chain found in $DATADIR (RESET=1 to wipe)"
fi
# networkid follows the genesis file's chainId instead of a hardcoded value.
NETWORKID=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['config']['chainId'])" "$GENESIS_FILE")

echo "== mining (Ctrl-C to stop; run verify_devnet.sh in another shell) =="
# Rewards go to ETHERBASE; set it to your own address to keep what you mine.
ETHERBASE="${ETHERBASE:-0x1000000000000000000000000000000000000001}"
exec "$GETH" --datadir "$DATADIR" --networkid "$NETWORKID" --nodiscover \
  --mine --miner.threads "${THREADS:-1}" \
  --miner.etherbase "$ETHERBASE" \
  --http --http.api eth,net,web3
