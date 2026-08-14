#!/usr/bin/env bash
# Join the Wheeler testnet from Windows via WSL2 (Ubuntu-family distro).
# Run as root inside WSL:  wsl -d <distro> -u root -- bash join_wheeler_wsl.sh
#
# Env: BOOTNODE (default: the public bootnode from the README)
#      MINE=1 to mine (a local mining account is created automatically)
#      THREADS (default 2)
#
# WSL GOTCHA, learned the hard way: Windows tears down the WSL VM when the
# launching wsl.exe session exits, killing nohup'd nodes. Keep the node alive
# with a Windows scheduled task running geth in the FOREGROUND:
#   schtasks /create /f /tn WheelerNode /tr "wsl.exe -d <distro> -u root -- bash /root/start_wheeler.sh" /sc once /st 00:00
#   schtasks /run /tn WheelerNode          (and again after each reboot)
# This script writes /root/start_wheeler.sh for exactly that purpose.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
BOOTNODE="${BOOTNODE:-enode://ad614b8cc1737cdaeaa38706ef131c924a37e507bc8d1e76897037056d6c67bfafca8ed4c65e6be76ed319f38c89a6a5f9acb75b8da822146fc6cc4d9d117b5f@71.183.54.11:30303}"

apt-get update -qq >/dev/null
apt-get install -y -qq git build-essential python3 curl >/dev/null
if ! /usr/local/go/bin/go version 2>/dev/null | grep -q "go1.2[2-9]\|go1.[3-9]"; then
  curl -sL https://go.dev/dl/go1.22.5.linux-amd64.tar.gz -o /tmp/go.tgz
  rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tgz
fi
export PATH=/usr/local/go/bin:$PATH

if [ -d /root/everett ]; then
  git -C /root/everett pull -q --ff-only
else
  git clone -q https://github.com/zengjiajun0623/everett /root/everett
fi
cd /root/everett
# ONE canonical prep. This used to re-implement ci_prepare.sh's twelve
# steps inline (pin, fetch, two compat seds, six file copies, three hook
# appliers). That is exactly the shape of bug the audit campaign kept
# finding: a change to the copy list or a hook argument had to be
# remembered in three places, and when it was not, a consensus gate ran
# zero tests. Delegating removes one of the three copies outright.
#
# EVERETT_DEPLOY=1 is the honest flag here: ci_prepare refuses by default
# to rebuild a tree a live node runs from, and on this host that node is
# exactly the one this script owns and is about to restart.
#
# The pin literal stays: scripts/check_consistency.py asserts that this
# file, ci_prepare.sh and docker/node.Dockerfile all name the same
# core-geth commit, so dropping it would silently remove this recipe from
# that gate. It is passed through so the two cannot disagree.
COREGETH_COMMIT="${COREGETH_COMMIT:-10f1ea745cd89d72c398484a234cdc7fb29ecc32}"
COREGETH_DIR=/root/everett/build/core-geth COREGETH_COMMIT="$COREGETH_COMMIT" \
  EVERETT_DEPLOY=1 bash /root/everett/scripts/ci_prepare.sh
cd build/core-geth
bash /root/everett/scripts/gate_test.sh ./params/mutations/ TestEverett 5 | tail -1
bash /root/everett/scripts/gate_test.sh ./consensus/ethash/ TestASERT 11 | tail -1
bash /root/everett/scripts/gate_test.sh ./consensus/ethash/ TestKawPow 7 -timeout 40m | tail -1
make geth 2>&1 | tail -1
GETH=/root/everett/build/core-geth/build/bin/geth

# Wheeler v2 (KawPow) re-genesis 2026-08-13: v1 datadirs are a different
# chain. Wipe on mismatch, keeping the keystore (mining account survives).
W2HASH=abd9bac321cc9176f1a540d8cab9bea6ce27a4621aeb6199642891141d5e8934
if [ -d /root/wheeler-data/geth/chaindata ]; then
  # Probe the datadir's genesis. A FAILED probe is not a v1 datadir: it
  # usually means the node is running and holds the datadir lock, and
  # wiping a healthy live v2 datadir on a hidden lock error is exactly
  # the disaster this used to cause. Only a SUCCESSFUL probe returning a
  # different hash identifies v1.
  PROBE_ERR=$(mktemp)
  GOT=$($GETH --datadir /root/wheeler-data --port 30398 --nodiscover --maxpeers 0 console --exec 'eth.getBlock(0).hash' 2>"$PROBE_ERR" | grep -o '[0-9a-f]\{64\}' | head -1 || true)
  if [ -z "$GOT" ]; then
    echo "FAIL: could not read the genesis of /root/wheeler-data." >&2
    echo "      If the node is running (WheelerNode scheduled task), stop it first:" >&2
    echo "        schtasks /end /tn WheelerNode   (from Windows)" >&2
    echo "      geth said:" >&2
    tail -3 "$PROBE_ERR" >&2
    rm -f "$PROBE_ERR"
    exit 1
  fi
  rm -f "$PROBE_ERR"
  if [ "$GOT" != "$W2HASH" ]; then
    echo "wheeler v1 datadir detected (genesis $GOT); re-initing for v2"
    rm -rf /root/wheeler-data/geth
  fi
fi
[ -d /root/wheeler-data/geth/chaindata ] || $GETH --datadir /root/wheeler-data init /root/everett/genesis-wheeler.json

MINEARGS=""
# v2 note: CPU KawPow mining (light path) is ~kH/s — near-useless. The
# PC mines with its GPU via stratum; this node verifies and relays.
if [ "${MINE:-0}" = "1" ]; then
  [ -f /root/wheeler-pw ] || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > /root/wheeler-pw
  ADDR=$(ls /root/wheeler-data/keystore/ 2>/dev/null | head -1 | grep -o '[0-9a-f]\{40\}$' || true)
  [ -n "$ADDR" ] && ADDR="0x$ADDR" || ADDR=$($GETH --datadir /root/wheeler-data account new --password /root/wheeler-pw 2>/dev/null | grep -o '0x[0-9a-fA-F]\{40\}' | head -1)
  echo "MINING ADDRESS: $ADDR"
  MINEARGS="--mine --miner.threads ${THREADS:-2} --miner.etherbase $ADDR"
fi

# The bootnode must ALSO be a static peer: --bootnodes only seeds
# discovery, and after any peer drop the node rediscovers the bootnode by
# its advertised (public) ENR address, which LAN nodes cannot reach when
# the router does not hairpin. A static entry keeps a persistent dial to
# the address we were actually given. Cost 20 minutes of a zero-peer
# retry loop to learn.
#
# It must go in config.toml, NOT datadir/geth/static-nodes.json: the
# pinned core-geth logs "The static-nodes.json file is deprecated and
# ignored. Use P2P.StaticNodes in config.toml instead." (node/config.go),
# so the JSON form left the node with discovery only and the incident
# above would recur silently.
rm -f /root/wheeler-data/geth/static-nodes.json
cat > /root/wheeler-config.toml <<TOMLEOF
[Node.P2P]
StaticNodes = ["$BOOTNODE"]
TOMLEOF

cat > /root/start_wheeler.sh <<STARTEOF
#!/usr/bin/env bash
exec $GETH --config /root/wheeler-config.toml \\
  --datadir /root/wheeler-data --networkid 15537392 --port 30313 \\
  --bootnodes "$BOOTNODE" --nat none $MINEARGS \\
  --http --http.addr 127.0.0.1 --http.port 8545 --http.api eth,net,web3 \\
  >> /root/wheeler.log 2>&1
STARTEOF
chmod +x /root/start_wheeler.sh
echo "READY: now create the scheduled task (see header comment) or run: bash /root/start_wheeler.sh"
