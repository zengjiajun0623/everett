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
bash "$EVERETT/scripts/gate_test.sh" ./params/mutations/ TestEverett 5
bash "$EVERETT/scripts/gate_test.sh" ./consensus/ethash/ TestASERT 11
bash "$EVERETT/scripts/gate_test.sh" ./consensus/ethash/ TestKawPow 7 -timeout 40m

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
# networkid follows the genesis file's chainId instead of a hardcoded value.
NETWORKID=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['config']['chainId'])" "$GENESIS_FILE")

# Art. VIII: the reserved mainnet chain begins with a ceremony, not with a
# dev script. Same guard the container and dist runners carry; this was the
# only runner without one.
if [ "$NETWORKID" = "15537393" ] && [ "${EVERETT_ART_VIII_CEREMONY:-0}" != "1" ]; then
  echo "boot_devnet: $GENESIS_FILE carries chain ID 15537393, RESERVED for the Article VIII launch ceremony (CONSTITUTION.md)." >&2
  echo "boot_devnet: use genesis-dev.json (default) or genesis-wheeler.json." >&2
  exit 1
fi

if [ "${RESET:-0}" = "1" ] || [ ! -d "$DATADIR/geth/chaindata" ]; then
  rm -rf "$DATADIR"
  "$GETH" --datadir "$DATADIR" init "$GENESIS_FILE"
else
  # An existing datadir holds whatever chain it was INITIALIZED with. Taking
  # --networkid from the GENESIS env while reusing that datadir silently
  # put the old chain on a different wire protocol. Refuse the mismatch.
  # Dedicated ports on BOTH probes. geth starts the full stack before it
  # evaluates --exec, so it binds the default authrpc 8551 unless told
  # otherwise; on a host already running a node that bind fails, geth dies
  # before printing, and the fail-closed check below then misdiagnoses it
  # as an unreadable datadir and tells the operator to stop production.
  HAVE_GENESIS=$("$GETH" --datadir "$DATADIR" --port 30399 --authrpc.port 8557 --nodiscover --maxpeers 0 \
    console --exec 'eth.getBlock(0).hash' 2>/dev/null | grep -o '[0-9a-f]\{64\}' | head -1 || true)
  WANT_GENESIS=$(python3 - "$GETH" "$GENESIS_FILE" <<'PYEOF'
import subprocess, sys, tempfile, os, shutil
geth, gen = sys.argv[1], sys.argv[2]
d = tempfile.mkdtemp()
try:
    subprocess.run([geth, "--datadir", d, "init", gen], capture_output=True, check=True)
    out = subprocess.run([geth, "--datadir", d, "--port", "30397",
                          "--authrpc.port", "8558", "--nodiscover",
                          "--maxpeers", "0", "console", "--exec", "eth.getBlock(0).hash"],
                         capture_output=True, text=True)
    import re
    m = re.search(r"[0-9a-f]{64}", out.stdout)
    print(m.group(0) if m else "")
finally:
    shutil.rmtree(d, ignore_errors=True)
PYEOF
)
  # Fail CLOSED. Either probe can come back empty (a leftover geth holding
  # the probe port, a locked datadir), and requiring both to be non-empty
  # before refusing meant the guard silently skipped exactly when something
  # was already odd, which is the moment it is most needed.
  [ -n "$HAVE_GENESIS" ] || { echo "boot_devnet: could not read $DATADIR's genesis; refusing to guess. Stop any node using it, or RESET=1." >&2; exit 1; }
  [ -n "$WANT_GENESIS" ] || { echo "boot_devnet: could not compute $GENESIS_FILE's genesis hash; refusing to guess." >&2; exit 1; }
  if [ "$HAVE_GENESIS" != "$WANT_GENESIS" ]; then
    echo "boot_devnet: $DATADIR holds genesis $HAVE_GENESIS but GENESIS=$GENESIS_FILE is $WANT_GENESIS." >&2
    echo "boot_devnet: reusing it with --networkid $NETWORKID would run the OLD chain on the NEW network id." >&2
    echo "boot_devnet: RESET=1 to re-init, or point DATADIR elsewhere." >&2
    exit 1
  fi
  echo "existing chain found in $DATADIR (RESET=1 to wipe)"
fi

echo "== mining (Ctrl-C to stop) =="
echo "   verify in another shell:  RPC=http://127.0.0.1:${HTTP_PORT:-8547} EXPECT_CHAINID=$NETWORKID scripts/verify_devnet.sh"
# Rewards go to ETHERBASE; set it to your own address to keep what you mine.
ETHERBASE="${ETHERBASE:-0x1000000000000000000000000000000000000001}"
# core-geth reads --miner.threads 0 as "use every core"; only a NEGATIVE
# value disables local mining. Same translation the container and dist
# runners do, so THREADS=0 means here what it means everywhere else.
THREADS_FLAG="${THREADS:-1}"
[ "$THREADS_FLAG" = "0" ] && THREADS_FLAG=-1
# Dedicated ports, env-overridable. The defaults (30303/8545/8551) are the
# production node's on an operator host, so the README's canonical devnet
# command used to die on "address already in use", or, with production
# briefly stopped, squat the ports and hold the live node in a launchd
# crash loop. Every other booting script here is hermetic for this reason.
exec "$GETH" --datadir "$DATADIR" --networkid "$NETWORKID" --nodiscover \
  --port "${PORT:-30306}" --authrpc.port "${AUTHRPC_PORT:-8554}" \
  --mine --miner.threads "$THREADS_FLAG" \
  --miner.etherbase "$ETHERBASE" \
  --http --http.port "${HTTP_PORT:-8547}" --http.api eth,net,web3
