# Formal verification

Machine-checked proofs about Everett's consensus delta. Core Lean 4
only, no mathlib: a monetary constitution's arguments are finite
integer arithmetic and induction, and the proofs read that way.

## EverettSchedule.lean · Article III

The model mirrors `client/rewards_everett.go` exactly (same floor
semantics, same constants). The Go side uses fixed-width 256-bit
integers (holiman/uint256); faithfulness to the unbounded ℕ model holds
because the largest intermediate value, (d0+tail)·92999 ≈ 2^78, sits
far below 2^256, so wrapping is unreachable. Proven, no sorries:

| Theorem | Statement |
|---|---|
| `decay_step_le` | 1000·D(n+1) ≤ 993·D(n): the floor never gains |
| `decay_mono`, `decay_strict_anti`, `decay_zero_stable` | decay is non-increasing, strictly decreasing while positive, and 0 is absorbing |
| `decay_le_geometric` | 1000ⁿ·D(n) ≤ 993ⁿ·d0 |
| `decaySum_bounded` | 7·ΣD + 1000·D(next) ≤ 1000·d0, so the per-era sum stays below d0·1000/7 ≈ 257.14 ETT |
| `issued_invariant` / `issued_le` / **`supply_bound`** | the per-block summation link: base-reward issuance through ANY height B is ≤ 0.2·B + eraLen·d0·1000/7 wei. **Decay component < 25,714,285.72 ETT of base rewards, forever, machine-checked end to end** |
| `decay_dies`, `decay_zero_forever`, `reward_terminal` | decay is exactly 0 from era 5360; from block 536,000,000 every reward is exactly the 0.2 tail. The terminal monetary state is a dated fact, not an asymptote |
| `reward_mono_after_slowstart` | after the launch window, rewards never rise |
| `uncle_multiplier` | with the 2-uncle cap, a block mints ≤ 9/8 of its base reward, so full-chain issuance is bounded by 9/8 of every figure above (decay component < 28.93M ETT; the per-block fact is the theorem, the chain-level 9/8 scaling is arithmetic on top of `supply_bound`) |
| `reward_le`, `reward_pos` | 0 < R(b) ≤ 2.0 ETT for every b ≥ 1 |
| `reward_slowstart_le` | slow start only ever reduces |
| `reward_eventually_tail` | once decay dies, R = 0.2 ETT exactly, forever |

Eight `native_decide` anchors (incl. the era-boundary blocks 92999 and
99999) pin the Lean model to the same value set the Go
(`rewards_everett_test.go`) and Python (`scripts/verify_rewards.py` /
`burn_audit.py`) implementations compute; the anchor set overlaps the Go
vectors and extends them at the boundaries the Go suite skips. Three
independently-written implementations, one machine-checked spec.

Trusted-base note: every theorem except `decay_dies` (and its
dependents `decay_zero_forever` / `reward_terminal`) is kernel-checked
with only `propext` and `Quot.sound`. `decay_dies` iterates 5,360
bignum steps and is proved by `native_decide`, which additionally
trusts Lean's compiler (`Lean.ofReduceBool`). The eight value anchors
share that trusted base; all bounds and invariants do not.

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
the summation gap, the undischarged eventually-tail premise, the
uncle channel, and a ×eraLen arithmetic slip in this README. All four
are now theorems (or corrected text) above. The review-then-formalize
loop, working as intended.
