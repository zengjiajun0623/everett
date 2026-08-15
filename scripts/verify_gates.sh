#!/usr/bin/env bash
# Test the tests: break something on purpose and assert the gate NOTICES.
#
# Why this exists. Ten audit rounds on this repo found the same shape over
# and over: a guard that measured something a FAILURE also produces. The
# deploy check watched the chain height climb, which a still-running old
# node does too. A binary-identity check hashed a file against itself. A
# connection timeout bounded silence rather than the connection. A drift
# gate compared filenames but not destinations. Each looked correct, each
# passed its own tests, and each proved nothing.
#
# The reason that class survives normal review is that the guard, the test
# for the guard, and the comment describing it all come from one head: a
# wrong model corrupts all three identically. A negative control is the one
# self-administered check that does not inherit the model, because it asks
# a different question. Not "does my gate pass when things are good" but
# "does my gate FAIL when I break exactly the thing it claims to detect".
#
# Those controls were run by hand during the audit and written down in
# prose (RUNBOOK, SECURITY.md, test comments). Prose decays: nothing
# re-runs it, so a gate can be weakened later and the claim stays green.
# This script makes them executable.
#
#   scripts/verify_gates.sh          fast controls (seconds)
#   scripts/verify_gates.sh --full   also the consensus vector control
#
# Every mutation is applied to a COPY. The real tree is never modified.
set -uo pipefail
EVERETT=$(cd "$(dirname "$0")/.." && pwd)
FULL=0
[ "${1:-}" = "--full" ] && FULL=1

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

# run_control <name> <gate-it-defends> <file-it-mutates> <mutation> <gate>
#
# The target file is named so the harness can PROVE the mutation landed. On
# its first run two rows reported a gate miss when one of them was really a
# mutation whose pattern no longer matched anything: a no-op mutation and a
# blind gate look identical from the outside, which is the very confusion
# this script exists to prevent. Now a mutation that changes nothing is a
# harness error, reported separately from a gate that failed to notice.
#
# The md5 check catches SYNTACTIC no-ops only. A mutation can change bytes
# and still be semantically inert: an early era-boundary mutation here
# shifted an index the loop never lands on, so the model's output was
# identical and the row read as a gate miss. When a row reports MISSED,
# confirm the mutation actually changes behaviour before believing the
# gate is blind. That is the one step of this harness a human still owns.
run_control() {
  local name="$1" gate="$2" target="$3" mutate="$4" check="$5"
  local dir="$WORK/$(echo "$name" | tr ' /' '__')"
  mkdir -p "$dir"
  # Copy only what the gates need; the build tree is huge and irrelevant.
  (cd "$EVERETT" && tar cf - --exclude=build --exclude=.git . ) | (cd "$dir" && tar xf -) 2>/dev/null

  local before after
  before=$(md5 -q "$dir/$target" 2>/dev/null || md5sum "$dir/$target" 2>/dev/null | cut -d" " -f1)
  if ! ( cd "$dir" && eval "$mutate" ) >/dev/null 2>&1; then
    printf "  %-46s %s\n" "$name" "HARNESS ERROR: mutation command failed"
    FAIL=$((FAIL + 1))
    return
  fi
  after=$(md5 -q "$dir/$target" 2>/dev/null || md5sum "$dir/$target" 2>/dev/null | cut -d" " -f1)
  if [ "$before" = "$after" ]; then
    printf "  %-46s %s\n" "$name" "HARNESS ERROR: mutation changed nothing in $target"
    FAIL=$((FAIL + 1))
    return
  fi
  if ( cd "$dir" && eval "$check" ) >/dev/null 2>&1; then
    printf "  %-46s %s\n" "$name" "*** MISSED: $gate stayed green ***"
    FAIL=$((FAIL + 1))
  else
    printf "  %-46s %s\n" "$name" "caught by $gate"
    PASS=$((PASS + 1))
  fi
}

echo "Negative controls: each row BREAKS something, then asserts a gate goes red."
echo

# --- constitution-consistency ------------------------------------------------
run_control "decay constant 993 -> 990" "constitution-consistency" scripts/burn_audit.py \
  "python3 -c \"p='scripts/burn_audit.py'; s=open(p).read(); open(p,'w').write(s.replace('d = d * 993 // 1000','d = d * 990 // 1000',1))\"" \
  "python3 scripts/check_consistency.py"

run_control "wrong era decay in the cross-check model" "constitution-consistency" scripts/check_consistency.py \
  "python3 - <<'PY'
s=open('scripts/check_consistency.py').read()
s=s.replace('total += (era_end - i + 1) * (_era_decay(k) + TAIL)',
            'total += (era_end - i + 1) * (_era_decay(k + 1) + TAIL)',1)
open('scripts/check_consistency.py','w').write(s)
PY" \
  "python3 scripts/check_consistency.py"

# --- prep-recipe drift (inside the consistency job) --------------------------
run_control "test file dropped from one prep recipe" "prep-drift gate" docker/node.Dockerfile \
  "python3 -c \"p='docker/node.Dockerfile'; s=open(p).read(); open(p,'w').write(s.replace(' client/asert_enum_test.go','',1))\"" \
  "python3 scripts/check_consistency.py"

run_control "client file copied to the wrong package" "prep-drift gate" scripts/ci_prepare.sh \
  "python3 -c \"p='scripts/ci_prepare.sh'; s=open(p).read(); open(p,'w').write(s.replace('kawpow_engine.go\\\" consensus/ethash/','kawpow_engine.go\\\" params/mutations/',1))\"" \
  "python3 scripts/check_consistency.py"

run_control "core-geth pin drifts between recipes" "pin-drift gate" docker/node.Dockerfile \
  "python3 -c \"p='docker/node.Dockerfile'; s=open(p).read(); open(p,'w').write(s.replace('ARG COREGETH_COMMIT=10f1ea745cd89d72c398484a234cdc7fb29ecc32','ARG COREGETH_COMMIT=' + '0'*40,1))\"" \
  "python3 scripts/check_consistency.py"

# --- formal-verification -----------------------------------------------------
run_control "a sorry planted in an fv subdirectory" "formal-verification" fv/Everett/Bad.lean \
  "mkdir -p fv/Everett && printf 'theorem bad : 1 = 1 := by sorry\n' > fv/Everett/Bad.lean" \
  "! grep -rn --include='*.lean' 'sorry' fv/"

# --- stratum-gates -----------------------------------------------------------
run_control "worker-name capture reverted (data race)" "stratum -race" stratum/kawpow-stratum.go \
  "python3 - <<'PY'
s=open('stratum/kawpow-stratum.go').read()
s=s.replace('\tworker := c.worker\n','')
s=s.replace('nonce, worker)','nonce, c.worker)')
open('stratum/kawpow-stratum.go','w').write(s)
PY" \
  "cd stratum && go test -race -count=1 -run TestProtocolConcurrent ."

run_control "per-host fairness cap removed (starvation)" "stratum spam test" stratum/kawpow-stratum.go \
  "python3 - <<'PY'
s=open('stratum/kawpow-stratum.go').read()
s=s.replace('\tif !c.bucket.reserveSlot() {','\tif false {')
open('stratum/kawpow-stratum.go','w').write(s)
PY" \
  "cd stratum && go test -count=1 -run TestSpamClient ."

run_control "per-IP connection cap removed" "stratum per-IP test" stratum/kawpow-stratum.go \
  "python3 - <<'PY'
s=open('stratum/kawpow-stratum.go').read()
s=s.replace('if *maxPerIPFlag > 0 && same >= *maxPerIPFlag {','if false {')
open('stratum/kawpow-stratum.go','w').write(s)
PY" \
  "cd stratum && go test -count=1 -run TestPerIPCap ."

# --- peer ledger -------------------------------------------------------------
# The ledger answers "who was connected when those blocks were mined". If it
# drops the host it still writes a plausible-looking row, which is the exact
# failure mode this repo keeps meeting: evidence that answers nothing.
run_control "peer host dropped from the ledger" "peer-ledger test" scripts/peer_ledger.py \
  "python3 - <<'PY'
s=open('scripts/peer_ledger.py').read()
s=s.replace('host = addr.rsplit(\":\", 1)[0] if \":\" in addr else addr','host = \"?\"')
open('scripts/peer_ledger.py','w').write(s)
PY" \
  "python3 scripts/test_peer_ledger.py"

# --- consensus vectors (slow: needs the patched tree) ------------------------
if [ "$FULL" = "1" ]; then
  echo
  echo "  (--full) consensus vector control, this one builds and takes minutes"
  run_control "KawPow period 3 -> 4" "consensus unit gates" client/kawpow_core.go \
    "python3 -c \"p='client/kawpow_core.go'; s=open(p).read(); open(p,'w').write(s.replace('kawpowPeriod     = 3','kawpowPeriod     = 4',1))\"" \
    "COREGETH_DIR=\$PWD/cg bash scripts/ci_prepare.sh >/dev/null 2>&1 && cd cg && go test ./consensus/ethash/ -run TestKawPowVectors -count=1"
fi

echo
echo "controls that caught their bug: $PASS"
echo "controls that MISSED:           $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "A gate that stays green while its own bug is present is not a gate."
  exit 1
fi
