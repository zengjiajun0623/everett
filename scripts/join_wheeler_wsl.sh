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
[ -d build/core-geth ] || git clone -q --depth 1 https://github.com/etclabscore/core-geth build/core-geth
cd build/core-geth
if grep -q "blst v0.3.1[1-6]" go.mod; then go get github.com/supranational/blst@v0.3.17; fi
sed -i -e '/fjl\/memsize\/memsizeui/d' -e '/var Memsize memsizeui.Handler/d' \
  -e '/http.Handle("\/memsize\/"/d' internal/debug/flags.go
sed -i '/debug.Memsize.Add("node", stack)/d' cmd/geth/main.go
cp /root/everett/client/rewards_everett.go /root/everett/client/rewards_everett_test.go params/mutations/
cp /root/everett/client/difficulty_everett.go /root/everett/client/difficulty_everett_test.go /root/everett/client/asert_enum_test.go consensus/ethash/
cp /root/everett/client/kawpow_core.go /root/everett/client/kawpow_core_test.go consensus/ethash/
python3 /root/everett/scripts/apply_hook.py params/mutations/rewards.go
python3 /root/everett/scripts/apply_daa_hook.py consensus/ethash/consensus.go
python3 /root/everett/scripts/apply_kawpow_hooks.py consensus/ethash/consensus.go consensus/ethash/sealer.go eth/backend.go cmd/utils/flags.go
cp /root/everett/client/kawpow_engine.go consensus/ethash/
go test ./params/mutations/ -run TestEverett 2>&1 | tail -1
go test ./consensus/ethash/ -run TestASERT 2>&1 | tail -1
go test ./consensus/ethash/ -run TestKawPow -timeout 40m 2>&1 | tail -1
make geth 2>&1 | tail -1
GETH=/root/everett/build/core-geth/build/bin/geth

# Wheeler v2 (KawPow) re-genesis 2026-08-13: v1 datadirs are a different
# chain. Wipe on mismatch, keeping the keystore (mining account survives).
W2HASH=abd9bac321cc9176f1a540d8cab9bea6ce27a4621aeb6199642891141d5e8934
if [ -d /root/wheeler-data/geth/chaindata ]; then
  GOT=$($GETH --datadir /root/wheeler-data --port 30398 --nodiscover --maxpeers 0 console --exec 'eth.getBlock(0).hash' 2>/dev/null | grep -o '[0-9a-f]\{64\}' | head -1 || true)
  if [ "$GOT" != "$W2HASH" ]; then
    echo "wheeler v1 datadir detected (genesis ${GOT:-unreadable}); re-initing for v2"
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
# its advertised (public) ENR address — which LAN nodes cannot reach when
# the router doesn't hairpin. A static entry keeps a persistent dial to
# the address we were actually given. Cost 20 minutes of a zero-peer
# retry loop to learn.
mkdir -p /root/wheeler-data/geth
echo "[\"$BOOTNODE\"]" > /root/wheeler-data/geth/static-nodes.json

cat > /root/start_wheeler.sh <<STARTEOF
#!/usr/bin/env bash
exec $GETH --datadir /root/wheeler-data --networkid 15537392 --port 30313 \\
  --bootnodes "$BOOTNODE" --nat none $MINEARGS \\
  --http --http.addr 127.0.0.1 --http.port 8545 --http.api eth,net,web3 \\
  >> /root/wheeler.log 2>&1
STARTEOF
chmod +x /root/start_wheeler.sh
echo "READY: now create the scheduled task (see header comment) or run: bash /root/start_wheeler.sh"
