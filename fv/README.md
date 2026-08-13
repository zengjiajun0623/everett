# Formal verification

Machine-checked proofs about Everett's consensus delta. Core Lean 4
only — no mathlib; a monetary constitution's arguments are finite
integer arithmetic and induction, and the proofs read that way.

## EverettSchedule.lean — Article III

The model mirrors `client/rewards_everett.go` exactly (same floor
semantics, same constants), faithful because the Go side uses
arbitrary-precision integers. Proven, no sorries:

| Theorem | Statement |
|---|---|
| `decay_step_le` | 1000·D(n+1) ≤ 993·D(n) — the floor never gains |
| `decay_mono`, `decay_strict_anti`, `decay_zero_stable` | decay is non-increasing, strictly decreasing while positive, and 0 is absorbing |
| `decay_le_geometric` | 1000ⁿ·D(n) ≤ 993ⁿ·d0 |
| `decaySum_bounded` | 7·ΣD + 1000·D(next) ≤ 1000·d0 — hence **total decay issuance < d0·1000/7 ≈ 25,714,285.71 ETT, forever** |
| `reward_le`, `reward_pos` | 0 < R(b) ≤ 2.0 ETT for every b ≥ 1 |
| `reward_slowstart_le` | slow start only ever reduces |
| `reward_eventually_tail` | once decay dies, R = 0.2 ETT exactly, forever |

Seven `native_decide` anchors pin the Lean model to the identical test
vectors the Go (`rewards_everett_test.go`) and Python
(`scripts/verify_rewards.py` / `burn_audit.py`) implementations check —
three independently-written implementations, one machine-checked spec.

The exhaustively-enumerated ASERT fixed-point proofs live in Go
(`client/asert_enum_test.go`): the approximation's domain is finite, so
enumeration IS the proof, and they run inside the standard TestASERT
gates.

## Build

    cd fv && lake build     # elan toolchain, pinned in lean-toolchain

CI runs this on every push (`formal-verification` job).
