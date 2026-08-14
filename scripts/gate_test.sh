#!/usr/bin/env bash
# Run a Go test gate and PROVE it actually ran.
#
#   gate_test.sh <package> <run-pattern> <min-tests> [extra go test args...]
#
# Why this exists: `go test -run TestFoo` prints "ok ... [no tests to run]"
# and exits 0 when nothing matches the pattern. Every Everett gate selects
# tests by name, and the test files are COPIED into the core-geth tree by
# the prep recipes, so a missed copy, a rename, or a typo in the pattern
# turns a consensus gate into a green no-op. That is not hypothetical: an
# audit found the ASERT enumeration tests being copied into no recipe at
# all, and the gates stayed green because the pattern matched nothing.
#
# This wrapper fails unless at least <min-tests> tests actually PASSED.
set -euo pipefail
PKG="${1:?usage: gate_test.sh <package> <run-pattern> <min-tests> [args...]}"
PATTERN="${2:?missing run pattern}"
MIN="${3:?missing minimum test count}"
shift 3

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
set +e
go test "$PKG" -run "$PATTERN" -v "$@" 2>&1 | tee "$OUT"
STATUS=${PIPESTATUS[0]}
set -e
[ "$STATUS" -eq 0 ] || { echo "GATE FAIL: $PKG -run $PATTERN returned $STATUS" >&2; exit 1; }

if grep -q "no tests to run" "$OUT"; then
  echo "GATE FAIL: pattern '$PATTERN' matched NO tests in $PKG." >&2
  echo "           The gate would have reported success while verifying nothing." >&2
  echo "           A test file is probably missing from the prep recipe." >&2
  exit 1
fi

RAN=$(grep -c '^--- PASS: ' "$OUT" || true)
if [ "$RAN" -lt "$MIN" ]; then
  echo "GATE FAIL: only $RAN test(s) passed for '$PATTERN' in $PKG, expected at least $MIN." >&2
  echo "           Either a test file is missing from the prep recipe, or the" >&2
  echo "           expected count in the caller needs updating deliberately." >&2
  exit 1
fi
echo "gate OK: $RAN test(s) passed for '$PATTERN' in $PKG (minimum $MIN)"
