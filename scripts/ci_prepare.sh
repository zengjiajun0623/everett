#!/usr/bin/env bash
# Clone core-geth and apply every Everett patch. Used by CI and reusable
# locally; boot_devnet.sh does the same work plus running a node.
set -euo pipefail
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$EVERETT/build"
mkdir -p "$WORK"

# Where to materialize the patched tree. Default is the production location
# (the launchd wheeler-node plist execs build/core-geth/build/bin/geth), so
# GATES MUST NOT USE THE DEFAULT on an operator host: ci_devnet.sh passes
# COREGETH_DIR=build/ci/core-geth so a verification run can never rebuild or
# delete the binary the live node relaunches from.
COREGETH_DIR="${COREGETH_DIR:-$WORK/core-geth}"
mkdir -p "$(dirname "$COREGETH_DIR")"

# Pinned to the commit every Everett gate has been verified against
# (same pin as docker/node.Dockerfile ARG COREGETH_COMMIT; the
# consistency gate asserts the two never diverge). Override with
# COREGETH_COMMIT=... to track a newer upstream deliberately.
COREGETH_COMMIT="${COREGETH_COMMIT:-10f1ea745cd89d72c398484a234cdc7fb29ecc32}"
fetch_pin() {
  git init "$COREGETH_DIR"
  git -C "$COREGETH_DIR" remote add origin https://github.com/etclabscore/core-geth 2>/dev/null || true
  git -C "$COREGETH_DIR" fetch --depth 1 origin "$COREGETH_COMMIT"
  git -C "$COREGETH_DIR" checkout FETCH_HEAD
}
# Never rebuild or delete a tree something is currently running from. The
# launchd production node execs $COREGETH_DIR/build/bin/geth on an operator
# host, so a casual prep here (scripts/boot_devnet.sh defaults to this same
# path, and it is the README's headline command) would relink the live
# node's binary underneath it. Deliberate deployment sets EVERETT_DEPLOY=1;
# everything else is refused with a pointer to an isolated tree.
in_use() { pgrep -f "^$COREGETH_DIR/build/bin/geth( |$)" >/dev/null 2>&1; }
if in_use && [ "${EVERETT_DEPLOY:-0}" != "1" ]; then
  echo "FAIL: a node is RUNNING from $COREGETH_DIR." >&2
  echo "      Preparing it would rebuild the live node's binary underneath it." >&2
  echo "      Use an isolated tree:  COREGETH_DIR=\$PWD/build/ci/core-geth $0" >&2
  echo "      To deploy on purpose:  RESTART=1 scripts/deploy_node.sh" >&2
  exit 1
fi

if [ ! -d "$COREGETH_DIR" ]; then
  fetch_pin
elif ! HAVE=$(git -C "$COREGETH_DIR" rev-parse HEAD 2>/dev/null); then
  # Directory exists but has no valid HEAD: debris from an interrupted
  # first fetch. Self-heal, unless a live node is running out of it.
  if in_use; then
    echo "FAIL: $COREGETH_DIR has no valid HEAD, but a node is RUNNING from it." >&2
    echo "      Refusing to wipe a live node's tree. Stop the node first, or" >&2
    echo "      prep elsewhere: COREGETH_DIR=\$PWD/build/ci/core-geth $0" >&2
    exit 1
  fi
  echo "WARN: $COREGETH_DIR has no valid HEAD (interrupted fetch?); refetching pin" >&2
  rm -rf "$COREGETH_DIR"
  fetch_pin
else
  # An existing checkout must BE the pin, not merely exist: a stale tree
  # would silently run every gate against the wrong upstream.
  [ "$HAVE" = "$COREGETH_COMMIT" ] || {
    echo "FAIL: $COREGETH_DIR is at $HAVE, pin is $COREGETH_COMMIT" >&2
    echo "      rm -rf $COREGETH_DIR to refetch, or set COREGETH_COMMIT to match." >&2
    echo "      CAUTION: on an operator host build/core-geth is the tree the live" >&2
    echo "      launchd node execs from; use COREGETH_DIR=build/ci/core-geth for gates." >&2
    exit 1
  }
fi
cd "$COREGETH_DIR"

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
python3 "$EVERETT/scripts/apply_kawpow_hooks.py" consensus/ethash/consensus.go consensus/ethash/sealer.go eth/backend.go cmd/utils/flags.go
cp "$EVERETT/client/kawpow_engine.go" consensus/ethash/
echo "core-geth prepared with Everett patches at $COREGETH_DIR"
