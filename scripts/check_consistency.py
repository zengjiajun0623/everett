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
    # The auditor's DECAY was unpinned: editing 993 here passed this gate
    # untouched, and only a live chain would have contradicted it. Found by
    # scripts/verify_gates.sh on its first run.
    ("scripts/burn_audit.py", r"d \* 993 // 1000", "auditor decay 993/1000"),
    ("scripts/burn_audit.py", r"TAIL, D0 = 2 \* 10\*\*17, 18 \* 10\*\*17", "auditor tail/D0"),
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


# A STRUCTURALLY DIFFERENT model of the same article, so the comparison
# below is a real cross-check. The previous "independent transcription"
# was the first function with its operands reordered: any shared
# misreading of the constitution lived in both, and the sweep could not
# disagree with itself.
#
# This model derives the per-block reward from CUMULATIVE issuance:
# build total issuance up to a height, then difference two heights. It
# reaches the same numbers by a different route, and an off-by-one at an
# era or slow-start boundary shows up here as a mismatch even though the
# era-by-era loop above would happily agree with a copy of itself.
#
# Note on flooring: the schedule floors once PER ERA (the chain multiplies
# and truncates each era), so a closed-form D0*993^k/1000^k with a single
# final floor is a DIFFERENT schedule and diverges by era 10. The per-era
# convention is the law; this model applies it explicitly.
_cum_cache = {}


def _era_decay(k):
    """Decay component in era k, floored once per era, as the chain does."""
    d = D0
    for _ in range(k):
        d = d * 993 // 1000
    return d


def _cum(n):
    """Total issued through block n, summed independently of py_reward."""
    if n <= 0:
        return 0
    if n in _cum_cache:
        return _cum_cache[n]
    total = 0
    # Slow start: each block pays a proportion of its era-0 reward, and the
    # proportion is floored per block, so this range must be summed, not
    # multiplied out.
    base0 = _era_decay(0) + TAIL
    for i in range(1, min(n, SLOW - 1) + 1):
        total += base0 * i // SLOW
    # After the slow start, blocks in the same era pay identically, so each
    # era contributes (count in era) * (decay + tail).
    i = SLOW
    while i <= n:
        k = i // ERA
        era_end = min(n, (k + 1) * ERA - 1)
        total += (era_end - i + 1) * (_era_decay(k) + TAIL)
        i = era_end + 1
    _cum_cache[n] = total
    return total


def spec_reward(n):
    return _cum(n) - _cum(n - 1)


sweep = [0, 1, 2, 46_500, 92_999, 93_000, 93_001, 99_999, 100_000, 100_001,
         199_999, 200_000, 1_000_000, 9_870_000, 500_000_000]
for n in sweep:
    a, b = py_reward(n), spec_reward(n)
    if a != b:
        fail.append(f"reward mismatch at block {n}: era-loop={a} spec-model={b}")
    if a < 0:
        fail.append(f"negative reward at block {n}")
    # Tail floor: the schedule's reward never drops below the 0.2 tail
    # (scaled proportionally inside the slow start).
    floor = TAIL * n // SLOW if n < SLOW else TAIL
    if n > 0 and a < floor:
        fail.append(f"reward below tail floor at block {n}: {a} < {floor}")

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

# Banner LAST: it used to print before the core-geth pin checks below, so a
# run that failed on pin drift had already announced "consistency gate
# PASSED" on stdout, which is what a human skims.

# --- prep-recipe drift ------------------------------------------------------
# docker/node.Dockerfile still re-implements ci_prepare.sh, on purpose:
# delegating would force `COPY . /src` BEFORE the core-geth fetch, so a
# README typo would bust the clone layer and re-run the 40-minute KawPow
# gate. The cost of keeping that copy is drift, and drift in exactly this
# list is what once shipped a green consensus gate that ran zero tests (a
# test file was added to some recipes' copy lists and not others). So the
# duplication is allowed but GATED: both recipes must copy the same client
# files and apply the same hooks to the same targets.
def _prep_facts(text):
    """Extract what a prep recipe actually DOES, not just which names it mentions.

    An earlier version compared only the SET of client/*.go filenames and the
    BASENAMES of hook targets, so it printed "recipes agree" while the two
    produced different trees: copying kawpow_engine.go into params/mutations/
    instead of consensus/ethash/, or applying the DAA hook to a different
    path, left it green. It now compares (source, DESTINATION) pairs and full
    hook target paths, which is what determines the resulting tree.
    """
    copies = set()
    # `cp a.go b.go dest/` and `COPY a.go b.go dest/` both end in the dest.
    for line in text.splitlines():
        t = line.strip().lstrip('#').strip()
        if not (t.startswith('cp ') or t.upper().startswith('COPY ')):
            continue
        parts = [w.strip('"\'') for w in t.split() if 'client/' in w or w.endswith('/')]
        srcs = [w.split('client/')[-1] for w in parts if 'client/' in w]
        dests = [w for w in parts if w.endswith('/')]
        if srcs and dests:
            for src in srcs:
                copies.add((src, dests[-1].rstrip('/')))
    hooks = set()
    for m in _re.finditer(r'(apply_\w+\.py)"?((?:\s+[\w/.-]+\.go)+)', text):
        targets = tuple(sorted(t.lstrip('./') for t in m.group(2).split()))
        hooks.add((m.group(1), targets))
    # The modern-Go compat block matters too: dropping the blst bump in one
    # recipe and not the other yields trees that build differently.
    compat = (bool(_re.search(r'blst v0\.3\.1\[1-6\]|blst@v0\.3\.17', text)),
              bool(_re.search(r'memsize', text)))
    return copies, hooks, compat


_ci_copies, _ci_hooks, _ci_compat = _prep_facts(_ci)
_df_copies, _df_hooks, _df_compat = _prep_facts(_df)
if _ci_copies != _df_copies:
    raise AssertionError(
        "prep drift: docker/node.Dockerfile copies client files to different places than "
        f"ci_prepare.sh.\n  only in ci_prepare: {sorted(_ci_copies - _df_copies)}"
        f"\n  only in Dockerfile: {sorted(_df_copies - _ci_copies)}\n"
        "A file copied to the wrong package, or not copied at all, is how a gate "
        "ends up running zero tests.")
if _ci_hooks != _df_hooks:
    raise AssertionError(
        "prep drift: docker/node.Dockerfile applies different hooks or targets than "
        f"ci_prepare.sh:\n  ci_prepare: {sorted(_ci_hooks)}\n  Dockerfile: {sorted(_df_hooks)}")
if _ci_compat != _df_compat:
    raise AssertionError(
        f"prep drift: the modern-Go compat block differs (blst, memsize) = "
        f"{_ci_compat} in ci_prepare.sh vs {_df_compat} in docker/node.Dockerfile")
print(f"prep recipes agree: {len(_ci_copies)} file copies with destinations, {len(_ci_hooks)} hook invocations, compat block {_ci_compat}")

print(f"consistency gate PASSED ({len(checks)} document checks, {len(sweep)} reward vectors)")
