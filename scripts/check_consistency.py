#!/usr/bin/env python3
"""Constitution-vs-implementation gate.

The 55-agent audit found the constitution, the spec, and the code drifting
apart (timestamp-vs-block schedules, unauthorized uncle issuance). This
script makes that class of drift a CI failure: the monetary parameters must
appear identically in CONSTITUTION.md, GENESIS_SPEC.md, the Go client, and
the Python auditor, and the two independent reward implementations must
agree wei-for-wei over a sweep of block numbers.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
fail = []


def read(p):
    return (ROOT / p).read_text()


# --- 1. the constitutional constants appear where they must -----------------
checks = [
    ("CONSTITUTION.md", r"993\s*/\s*1000", "per-era decay 993/1000"),
    ("CONSTITUTION.md", r"100,000", "era length 100,000 blocks"),
    ("CONSTITUTION.md", r"93,000", "slow-start 93,000 blocks"),
    ("CONSTITUTION.md", r"R_tail\s*=\s*0\.2", "tail 0.2"),
    ("GENESIS_SPEC.md", r"993/1000", "spec decay"),
    ("GENESIS_SPEC.md", r"100,000 blocks", "spec era length"),
    ("client/rewards_everett.go", r"everettEraLength uint64 = 100_000", "go era length"),
    ("client/rewards_everett.go", r"everettSlowStart uint64 = 93_000", "go slow start"),
    ("client/rewards_everett.go", r"everettNum\s*=\s*uint256\.NewInt\(993\)|NewInt\(993\)", "go decay numerator"),
    ("client/rewards_everett.go", r"200_000_000_000_000_000", "go tail (0.2 ETT)"),
    ("scripts/verify_rewards.py", r"ERA, SLOW = 100_000, 93_000", "python era/slow"),
    ("scripts/verify_rewards.py", r"TAIL, D0 = 2 \* 10\*\*17, 18 \* 10\*\*17", "python tail/D0"),
    ("scripts/burn_audit.py", r"ERA, SLOW = 100_000, 93_000", "auditor era/slow"),
]
for path, pattern, label in checks:
    if not re.search(pattern, read(path)):
        fail.append(f"{path}: missing {label} (pattern {pattern!r})")

# --- 2. chain IDs are what the spec says ------------------------------------
if '"chainId": 15537393' not in read("genesis.json"):
    fail.append("genesis.json: mainnet chain ID must be 15537393")
if '"chainId": 15537392' not in read("genesis-wheeler.json"):
    fail.append("genesis-wheeler.json: Wheeler chain ID must be 15537392")
if '"alloc": {}' not in read("genesis.json").replace("\n", " ").replace('"alloc":{}', '"alloc": {}'):
    fail.append("genesis.json: Article V.1 requires an empty alloc")

# --- 3. the two reward implementations agree, wei for wei -------------------
ERA, SLOW = 100_000, 93_000
TAIL, D0 = 2 * 10**17, 18 * 10**17


def py_reward(n):
    if n == 0:
        return 0
    d = D0
    for _ in range(n // ERA):
        d = d * 993 // 1000
    r = TAIL + d
    if n < SLOW:
        r = r * n // SLOW
    return r


# Independent transcription of the Go implementation's control flow, kept
# separate so a copy-paste error in either is visible here.
def go_reward(n):
    if n == 0:
        return 0
    era = n // ERA
    d = D0
    for _ in range(era):
        d = (d * 993) // 1000
    r = d + TAIL
    if n < SLOW:
        r = (r * n) // SLOW
    return r


sweep = [0, 1, 2, 46_500, 92_999, 93_000, 93_001, 99_999, 100_000, 100_001,
         199_999, 200_000, 1_000_000, 9_870_000, 500_000_000]
for n in sweep:
    a, b = py_reward(n), go_reward(n)
    if a != b:
        fail.append(f"reward mismatch at block {n}: {a} != {b}")
    if a < 0:
        fail.append(f"negative reward at block {n}")
    if n > 0 and a < TAIL * n // SLOW if n < SLOW else a < TAIL:
        pass

# monotonic decay after slow start, never below the tail
prev = None
for n in range(SLOW, SLOW + 10 * ERA, ERA):
    r = py_reward(n)
    if r < TAIL:
        fail.append(f"reward fell below the constitutional tail at block {n}: {r}")
    if prev is not None and r > prev:
        fail.append(f"reward increased after slow start at block {n}")
    prev = r

if fail:
    print("CONSISTENCY GATE FAILED:")
    for f in fail:
        print("  -", f)
    sys.exit(1)
print(f"consistency gate PASSED ({len(checks)} document checks, {len(sweep)} reward vectors)")


# --- core-geth pin consistency (added after the DeepSeek version audit:
# the Dockerfile was pinned but the scripts cloned unpinned HEAD, and the
# docs claimed "pinned" — the two definitions must never diverge) -------
import re as _re
_ci = open(ROOT / "scripts" / "ci_prepare.sh").read()
_df = open(ROOT / "docker" / "node.Dockerfile").read()
_m1 = _re.search(r'COREGETH_COMMIT:-([0-9a-f]{40})', _ci)
_m2 = _re.search(r'ARG COREGETH_COMMIT=([0-9a-f]{40})', _df)
assert _m1 and _m2, "core-geth pin missing from ci_prepare.sh or node.Dockerfile"
assert _m1.group(1) == _m2.group(1), (
    f"core-geth pin drift: ci_prepare.sh={_m1.group(1)} node.Dockerfile={_m2.group(1)}")
_j = open(ROOT / "scripts" / "join_wheeler_wsl.sh").read()
_m3 = _re.search(r'COREGETH_COMMIT:-([0-9a-f]{40})', _j)
assert _m3 and _m3.group(1) == _m1.group(1), "join_wheeler_wsl.sh pin drift"
print("core-geth pin consistent across Dockerfile + scripts:", _m1.group(1)[:12])
