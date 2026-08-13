#!/usr/bin/env bash
# Everett devnet boot: clone core-geth, apply the reward patch, run unit
# tests (gate), build, init genesis, mine. Fail fast at every step.
set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$EVERETT/build"
DATADIR="$WORK/devnet-data"
mkdir -p "$WORK"

if [ ! -d "$WORK/core-geth" ]; then
  git clone --depth 1 https://github.com/etclabscore/core-geth "$WORK/core-geth"
fi

cp "$EVERETT/client/rewards_everett.go" "$WORK/core-geth/params/mutations/"
cp "$EVERETT/client/rewards_everett_test.go" "$WORK/core-geth/params/mutations/"
cp "$EVERETT/client/difficulty_everett.go" "$WORK/core-geth/consensus/ethash/"
cp "$EVERETT/client/difficulty_everett_test.go" "$WORK/core-geth/consensus/ethash/"
python3 "$EVERETT/scripts/apply_hook.py" "$WORK/core-geth/params/mutations/rewards.go"
python3 "$EVERETT/scripts/apply_daa_hook.py" "$WORK/core-geth/consensus/ethash/consensus.go"

cd "$WORK/core-geth"
echo "== unit tests (verification gate 1: schedule + DAA) =="
go test ./params/mutations/ -run TestEverett -v
go test ./consensus/ethash/ -run TestASERT -v

echo "== build =="
make geth
GETH="$WORK/core-geth/build/bin/geth"

echo "== init genesis =="
# Devnet genesis (0x20000 difficulty) by default: the production difficulty
# guess stalls CPU miners. Override with GENESIS=genesis.json for prod tests.
GENESIS_FILE="$EVERETT/${GENESIS:-genesis-devnet.json}"
rm -rf "$DATADIR"
"$GETH" --datadir "$DATADIR" init "$GENESIS_FILE"

echo "== mining (Ctrl-C to stop; run verify_devnet.sh in another shell) =="
exec "$GETH" --datadir "$DATADIR" --networkid 15537393 --nodiscover \
  --mine --miner.threads 1 \
  --miner.etherbase 0x1000000000000000000000000000000000000001 \
  --http --http.api eth,net,web3
