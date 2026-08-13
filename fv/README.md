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
| `decaySum_bounded` | 7·ΣD + 1000·D(next) ≤ 1000·d0 — the per-era sum stays below d0·1000/7 ≈ 257.14 ETT |
| `issued_invariant` / `issued_le` / **`supply_bound`** | the per-block summation link: base-reward issuance through ANY height B is ≤ 0.2·B + eraLen·d0·1000/7 wei — **decay component < 25,714,285.72 ETT of base rewards, forever, machine-checked end to end** |
| `decay_dies`, `decay_zero_forever`, `reward_terminal` | decay is exactly 0 from era 5360; from block 536,000,000 every reward is exactly the 0.2 tail — the terminal monetary state is a dated fact, not an asymptote |
| `reward_mono_after_slowstart` | after the launch window, rewards never rise |
| `uncle_multiplier` | with the 2-uncle cap, a block mints ≤ 9/8 of its base reward — so full-chain issuance is bounded by 9/8 of every figure above (decay component < 28.93M ETT) |
| `reward_le`, `reward_pos` | 0 < R(b) ≤ 2.0 ETT for every b ≥ 1 |
| `reward_slowstart_le` | slow start only ever reduces |
| `reward_eventually_tail` | once decay dies, R = 0.2 ETT exactly, forever |

Eight `native_decide` anchors (incl. the era-boundary block 99999) pin the Lean model to the identical test
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

## Review provenance

The first version proved the per-era bound and claimed the per-block
consequence in prose; an adversarial review (Kimi, 2026-08-13) flagged
the summation gap, the undischargeble eventually-tail premise, the
uncle channel, and a ×eraLen arithmetic slip in this README. All four
are now theorems (or corrected text) above — the review-then-formalize
loop working as intended.
