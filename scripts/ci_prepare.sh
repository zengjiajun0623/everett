#!/usr/bin/env bash
# Clone core-geth and apply every Everett patch. Used by CI and reusable
# locally; boot_devnet.sh does the same work plus running a node.
set -euo pipefail
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$EVERETT/build"
mkdir -p "$WORK"

if [ ! -d "$WORK/core-geth" ]; then
  git clone --depth 1 https://github.com/etclabscore/core-geth "$WORK/core-geth"
fi
cd "$WORK/core-geth"

# Modern-Go compat (idempotent): blst bump, memsize excision.
if grep -q "blst v0.3.1[1-6]" go.mod; then
  go get github.com/supranational/blst@v0.3.17
fi
sed -i.bak -e '/fjl\/memsize\/memsizeui/d' -e '/var Memsize memsizeui.Handler/d' \
  -e '/http.Handle("\/memsize\/"/d' internal/debug/flags.go && rm -f internal/debug/flags.go.bak
sed -i.bak '/debug.Memsize.Add("node", stack)/d' cmd/geth/main.go && rm -f cmd/geth/main.go.bak

cp "$EVERETT/client/rewards_everett.go" "$EVERETT/client/rewards_everett_test.go" params/mutations/
cp "$EVERETT/client/difficulty_everett.go" "$EVERETT/client/difficulty_everett_test.go" "$EVERETT/client/asert_enum_test.go" consensus/ethash/
cp "$EVERETT/client/kawpow_core.go" "$EVERETT/client/kawpow_core_test.go" consensus/ethash/
python3 "$EVERETT/scripts/apply_hook.py" params/mutations/rewards.go
python3 "$EVERETT/scripts/apply_daa_hook.py" consensus/ethash/consensus.go
echo "core-geth prepared with Everett patches"
python3 "$EVERETT/scripts/apply_kawpow_hooks.py" consensus/ethash/consensus.go consensus/ethash/sealer.go eth/backend.go cmd/utils/flags.go
cp "$EVERETT/client/kawpow_engine.go" consensus/ethash/
