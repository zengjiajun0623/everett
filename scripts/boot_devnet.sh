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

echo "== modern-Go compat fixes (idempotent) =="
cd "$WORK/core-geth"
# blst v0.3.11 fails under Go 1.23+; bump to the fixed release.
if grep -q "blst v0.3.1[1-6]" go.mod; then
  go get github.com/supranational/blst@v0.3.17
fi
# fjl/memsize uses a runtime linkname removed in modern Go; excise it
# (same removal upstream geth made). All three deletes are no-ops once done.
sed -i.bak -e '/fjl\/memsize\/memsizeui/d' -e '/var Memsize memsizeui.Handler/d' \
  -e '/http.Handle("\/memsize\/"/d' internal/debug/flags.go && rm -f internal/debug/flags.go.bak
sed -i.bak '/debug.Memsize.Add("node", stack)/d' cmd/geth/main.go && rm -f cmd/geth/main.go.bak
cd "$WORK/.."

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
# genesis-dev.json (chainId 15537391) is the canonical devnet; the legacy
# genesis-devnet.json carries the RESERVED mainnet chainId 15537393 and is
# kept only for existing datadirs (an existing chain is never re-inited, so
# old devnets keep working — new ones get the dedicated ID).
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
