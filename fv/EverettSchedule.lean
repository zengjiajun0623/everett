/-
Article III of the Everett constitution, formalized.

The model below mirrors client/rewards_everett.go EXACTLY — same integer
(floor) semantics, same constants — over unbounded ℕ, which is faithful
because the Go implementation's fixed-width uint256 arithmetic cannot
wrap on this schedule (largest intermediate: (d0+tail)·92999 ≈ 2^78,
far under 2^256). The Go
`!num.IsUint64()` branch (returns bare tail for b ≥ 2^64) is not
modeled; `reward_terminal` proves the two definitions agree there:
decay is zero from era 5360, so both yield exactly `tail`.

Everything is proven with core Lean 4 only (no mathlib): the arguments
are finite ℕ arithmetic and induction, as a monetary constitution's
arguments should be.

Main results
  • decay_le_geometric : 1000^n · decay n ≤ 993^n · d0
      (each floor step loses against the exact geometric envelope)
  • decay_strict_anti  : decay is strictly decreasing until it hits 0
  • decaySum_bounded   : 7 · Σ_{i≤n} decay i + 1000 · decay (n+1) ≤ 1000 · d0
      hence Σ decay < d0·1000/7 FOREVER — total decay issuance is
      bounded by 100000 · d0 · 1000 / 7 wei ≈ 25,714,285.7 ETT
  • reward_le / reward_pos / slow-start bounds
  • reward_eventually_tail : once decay reaches 0, every reward is
      exactly the 0.2 ETT tail
-/

namespace Everett

/-- 0.2 ETT in wei (Art. III tail emission). -/
def tail : Nat := 200000000000000000
/-- 1.8 ETT in wei (Art. III initial decay component). -/
def d0 : Nat := 1800000000000000000
/-- Blocks per era. -/
def eraLen : Nat := 100000
/-- Slow-start window (Art. III). -/
def slowStart : Nat := 93000

/-- D(era): iterated floor decay, exactly `everettDecay` in Go. -/
def decay : Nat → Nat
  | 0 => d0
  | n + 1 => decay n * 993 / 1000

/-- R(block): exactly `EverettBlockReward` in Go. -/
def reward (b : Nat) : Nat :=
  if b = 0 then 0
  else
    let r := decay (b / eraLen) + tail
    if b < slowStart then r * b / slowStart else r

/-- Σ_{i=0}^{n} decay i. -/
def decaySum : Nat → Nat
  | 0 => decay 0
  | n + 1 => decaySum n + decay (n + 1)

/-! ### Decay properties -/

/-- One floor step never gains against the exact ratio: 1000·D(n+1) ≤ 993·D(n). -/
theorem decay_step_le (n : Nat) : 1000 * decay (n + 1) ≤ 993 * decay n := by
  show 1000 * (decay n * 993 / 1000) ≤ 993 * decay n
  have h := Nat.div_mul_le_self (decay n * 993) 1000
  calc 1000 * (decay n * 993 / 1000)
      = (decay n * 993 / 1000) * 1000 := Nat.mul_comm _ _
    _ ≤ decay n * 993 := h
    _ = 993 * decay n := Nat.mul_comm _ _

/-- Decay is monotone non-increasing. -/
theorem decay_mono (n : Nat) : decay (n + 1) ≤ decay n := by
  have h := decay_step_le n
  have h993 : 993 * decay n ≤ 1000 * decay n :=
    Nat.mul_le_mul_right _ (by decide)
  have := Nat.le_trans h h993
  exact Nat.le_of_mul_le_mul_left this (by decide)

/-- While positive, decay strictly decreases (so it cannot stall above 0). -/
theorem decay_strict_anti (n : Nat) (h : 0 < decay n) :
    decay (n + 1) < decay n := by
  have hstep := decay_step_le n
  omega

/-- Zero is absorbing. -/
theorem decay_zero_stable (n : Nat) (h : decay n = 0) : decay (n + 1) = 0 := by
  show decay n * 993 / 1000 = 0
  rw [h]

/-- The exact geometric envelope: 1000^n · decay n ≤ 993^n · d0. -/
theorem decay_le_geometric (n : Nat) : 1000 ^ n * decay n ≤ 993 ^ n * d0 := by
  induction n with
  | zero => simp [decay]
  | succ k ih =>
    calc 1000 ^ (k + 1) * decay (k + 1)
        = 1000 ^ k * (1000 * decay (k + 1)) := by
          rw [Nat.pow_succ, Nat.mul_assoc]
      _ ≤ 1000 ^ k * (993 * decay k) :=
          Nat.mul_le_mul_left _ (decay_step_le k)
      _ = 993 * (1000 ^ k * decay k) := by
          rw [← Nat.mul_assoc, Nat.mul_comm (1000 ^ k) 993, Nat.mul_assoc]
      _ ≤ 993 * (993 ^ k * d0) := Nat.mul_le_mul_left _ ih
      _ = 993 ^ (k + 1) * d0 := by
          rw [← Nat.mul_assoc, ← Nat.pow_succ']

/-! ### The supply bound — the constitutional headline

    Invariant: 7·(Σ_{i≤n} decay i) + 1000·decay (n+1) ≤ 1000·d0.
    Base: 7·d0 + 1000·decay 1 ≤ 7·d0 + 993·d0 = 1000·d0.
    Step: uses only 1000·decay(n+2) ≤ 993·decay(n+1).
    Consequence: the decay component of issuance is < d0·1000/7 per
    block-slot, i.e. total decay issuance < 100000·d0·1000/7 wei
    ≈ 25,714,285.71 ETT, for ALL time. -/
theorem decaySum_bounded (n : Nat) :
    7 * decaySum n + 1000 * decay (n + 1) ≤ 1000 * d0 := by
  induction n with
  | zero =>
    have hs : decaySum 0 = decay 0 := rfl
    have h0 : decay 0 = d0 := rfl
    have hstep := decay_step_le 0
    omega
  | succ k ih =>
    have hs : decaySum (k + 1) = decaySum k + decay (k + 1) := rfl
    have hstep := decay_step_le (k + 1)
    omega

/-- Clean corollary: 7·Σ decay ≤ 1000·d0, i.e. Σ decay ≤ d0·1000/7. -/
theorem decaySum_le (n : Nat) : 7 * decaySum n ≤ 1000 * d0 :=
  Nat.le_trans (Nat.le_add_right _ _) (decaySum_bounded n)

/-! ### Reward properties -/

/-- The genesis block earns nothing (Art. III: R(0) = 0). -/
theorem reward_zero : reward 0 = 0 := rfl

/-- Every reward is bounded by d0 + tail (2.0 ETT). -/
theorem reward_le (b : Nat) : reward b ≤ d0 + tail := by
  unfold reward
  by_cases h0 : b = 0
  · simp [h0]
  · simp only [h0, if_false]
    have hd : decay (b / eraLen) ≤ d0 := by
      have : ∀ n, decay n ≤ d0 := by
        intro n
        induction n with
        | zero => exact Nat.le_refl _
        | succ k ih => exact Nat.le_trans (decay_mono k) ih
      exact this _
    by_cases hs : b < slowStart
    · simp only [hs, if_true]
      have h1 : (decay (b / eraLen) + tail) * b / slowStart
          ≤ decay (b / eraLen) + tail := by
        have hb : b ≤ slowStart := Nat.le_of_lt hs
        have := Nat.mul_le_mul_left (decay (b / eraLen) + tail) hb
        have h2 := Nat.div_le_div_right (c := slowStart) this
        have h3 : (decay (b / eraLen) + tail) * slowStart / slowStart
            = decay (b / eraLen) + tail :=
          Nat.mul_div_cancel _ (by decide)
        rw [h3] at h2
        exact h2
      exact Nat.le_trans h1 (Nat.add_le_add_right hd _)
    · simp only [hs, if_false]
      exact Nat.add_le_add_right hd _

/-- Slow-start never exceeds the full-schedule reward. -/
theorem reward_slowstart_le (b : Nat) (h : b < slowStart) (h0 : b ≠ 0) :
    reward b ≤ decay (b / eraLen) + tail := by
  unfold reward
  simp only [h0, if_false, h, if_true]
  have hb : b ≤ slowStart := Nat.le_of_lt h
  have := Nat.mul_le_mul_left (decay (b / eraLen) + tail) hb
  have h2 := Nat.div_le_div_right (c := slowStart) this
  have h3 : (decay (b / eraLen) + tail) * slowStart / slowStart
      = decay (b / eraLen) + tail := Nat.mul_div_cancel _ (by decide)
  rw [h3] at h2
  exact h2

/-- Past slow start, once decay has died out the reward is EXACTLY the
    0.2 ETT tail, forever (Art. III's asymptotic promise). -/
theorem reward_eventually_tail (b : Nat)
    (hs : slowStart ≤ b) (hd : decay (b / eraLen) = 0) :
    reward b = tail := by
  unfold reward
  have h0 : b ≠ 0 := by
    intro h; rw [h] at hs; exact absurd hs (by decide)
  have hlt : ¬ b < slowStart := Nat.not_lt.mpr hs
  simp [h0, hlt, hd]

/-- Rewards after block 0 are strictly positive (the tail guarantees a
    mining incentive at every height; slow start divides but the first
    block already clears the floor). -/
theorem reward_pos (b : Nat) (h0 : b ≠ 0) : 0 < reward b := by
  unfold reward
  simp only [h0, if_false]
  by_cases hs : b < slowStart
  · simp only [hs, if_true]
    have hb : 1 ≤ b := Nat.one_le_iff_ne_zero.mpr h0
    have htail : tail ≤ decay (b / eraLen) + tail := Nat.le_add_left _ _
    have h1 : tail * 1 ≤ (decay (b / eraLen) + tail) * b :=
      Nat.mul_le_mul htail hb
    have h2 : slowStart ≤ tail := by decide
    have h3 : slowStart * 1 ≤ (decay (b / eraLen) + tail) * b := by
      calc slowStart * 1 ≤ tail * 1 := Nat.mul_le_mul_right _ h2
        _ ≤ _ := h1
    have := Nat.div_le_div_right (c := slowStart) h3
    have h4 : slowStart * 1 / slowStart = 1 := by decide
    rw [h4] at this
    exact Nat.lt_of_lt_of_le (by decide) this
  · simp only [hs, if_false]
    have : 0 < tail := by decide
    exact Nat.lt_of_lt_of_le this (Nat.le_add_left _ _)

/-! ### Sanity anchors: pin the model to the Go/Python test vectors.
    These are the same values checked by the repo's cross-implementation
    gates; if the Lean model ever drifts from the code, these fail. -/

example : reward 1 = 21505376344086 := by native_decide
example : reward 46500 = 1000000000000000000 := by native_decide
example : reward 92999 = 1999978494623655913 := by native_decide
example : reward 93000 = 2000000000000000000 := by native_decide
example : reward 100000 = 1987400000000000000 := by native_decide
example : decay 1 = 1787400000000000000 := by native_decide
example : decay 100 = 891656037640534722 := by native_decide


/-! ### Kimi-review completions (2026-08-13): the premise, the summation
    link, and the uncle channel — closing the gaps between what the
    comments claimed and what the machine checks. -/

/-- Decay is dead by era 5360 (first zero, computed and machine-checked). -/
theorem decay_dies : decay 5360 = 0 := by native_decide

/-- …and stays dead forever. -/
theorem decay_zero_forever (n : Nat) (h : 5360 ≤ n) : decay n = 0 := by
  induction n with
  | zero => exact absurd h (by decide)
  | succ k ih =>
    cases Nat.lt_or_ge 5360 (k + 1) with
    | inl hlt =>
      have hk : 5360 ≤ k := Nat.le_of_lt_succ hlt
      exact decay_zero_stable k (ih hk)
    | inr hge =>
      have : k + 1 = 5360 := Nat.le_antisymm hge h
      rw [this]; exact decay_dies

/-- THE TERMINAL STATE, unconditionally: from block 536,000,000 on, every
    reward is exactly the 0.2 ETT tail. The "asymptotic promise" of
    Art. III is a concrete, dated fact. -/
theorem reward_terminal (b : Nat) (h : 536000000 ≤ b) : reward b = tail := by
  have hs : slowStart ≤ b := Nat.le_trans (by decide) h
  have he : 5360 ≤ b / eraLen := by
    have := Nat.div_le_div_right (c := eraLen) h
    calc 5360 = 536000000 / eraLen := by decide
      _ ≤ b / eraLen := this
  exact reward_eventually_tail b hs (decay_zero_forever _ he)

/-- Monotone across any era gap. -/
theorem decay_le_of_le {n m : Nat} (h : n ≤ m) : decay m ≤ decay n := by
  induction m with
  | zero => cases Nat.le_zero.mp h; exact Nat.le_refl _
  | succ k ih =>
    cases Nat.lt_or_ge n (k + 1) with
    | inl hlt => exact Nat.le_trans (decay_mono k) (ih (Nat.le_of_lt_succ hlt))
    | inr hge => have : n = k + 1 := Nat.le_antisymm h hge
                 rw [this]; exact Nat.le_refl _

/-- After the slow-start window, rewards never rise again. -/
theorem reward_mono_after_slowstart (b : Nat) (h : slowStart ≤ b) :
    reward (b + 1) ≤ reward b := by
  have h0 : b ≠ 0 := by intro hb; rw [hb] at h; exact absurd h (by decide)
  have h1 : b + 1 ≠ 0 := Nat.succ_ne_zero b
  have hnb : ¬ b < slowStart := Nat.not_lt.mpr h
  have hnb1 : ¬ b + 1 < slowStart := Nat.not_lt.mpr (Nat.le_succ_of_le h)
  unfold reward
  simp only [h0, h1, hnb, hnb1, if_false]
  exact Nat.add_le_add_right
    (decay_le_of_le (Nat.div_le_div_right (Nat.le_succ b))) _

/-- Uniform per-block bound feeding the issuance induction. -/
theorem reward_le_era (b : Nat) : reward b ≤ decay (b / eraLen) + tail := by
  by_cases h0 : b = 0
  · rw [h0, reward_zero]; exact Nat.zero_le _
  · by_cases hs : b < slowStart
    · exact reward_slowstart_le b hs h0
    · unfold reward; simp [h0, hs]

/-- Cumulative base-reward issuance through block B. -/
def issued : Nat → Nat
  | 0 => reward 0
  | b + 1 => issued b + reward (b + 1)

/-- The era-budget invariant: at any height, issuance so far PLUS the
    full budget of the era's remaining blocks stays within
    tail·B + eraLen·(Σ decay through the current era). Each era's
    100000·decay(e) is allocated on entry and consumed at most
    decay(e) per block — the summation link the review demanded. -/
theorem issued_invariant (B : Nat) :
    issued B + (eraLen - 1 - B % eraLen) * decay (B / eraLen)
      ≤ tail * B + eraLen * decaySum (B / eraLen) := by
  induction B with
  | zero =>
    have h1 : issued 0 = 0 := rfl
    have h2 : decaySum 0 = decay 0 := rfl
    have h3 : (0 : Nat) % eraLen = 0 := rfl
    have h4 : (0 : Nat) / eraLen = 0 := rfl
    rw [h1, h3, h4, h2]
    show 0 + (eraLen - 1 - 0) * decay 0 ≤ tail * 0 + eraLen * decay 0
    have : eraLen - 1 - 0 ≤ eraLen := by decide
    calc 0 + (eraLen - 1 - 0) * decay 0
        = (eraLen - 1 - 0) * decay 0 := Nat.zero_add _
      _ ≤ eraLen * decay 0 := Nat.mul_le_mul_right _ this
      _ = tail * 0 + eraLen * decay 0 := by rw [Nat.mul_zero, Nat.zero_add]
  | succ b ih =>
    have hr := reward_le_era (b + 1)
    have hiss : issued (b + 1) = issued b + reward (b + 1) := rfl
    by_cases hb : b % eraLen = eraLen - 1
    · -- era boundary: (b+1) enters era e+1, decaySum grows by decay (e+1)
      have hdiv : (b + 1) / eraLen = b / eraLen + 1 := by
        unfold eraLen at hb ⊢; omega
      have hmod : (b + 1) % eraLen = 0 := by
        unfold eraLen at hb ⊢; omega
      have hds : decaySum (b / eraLen + 1)
          = decaySum (b / eraLen) + decay (b / eraLen + 1) := rfl
      rw [hiss, hdiv, hmod, hds]
      rw [hdiv] at hr
      have ht : tail * (b + 1) = tail * b + tail := Nat.mul_succ tail b
      have hzero : (eraLen - 1 - b % eraLen) * decay (b / eraLen) = 0 := by
        rw [hb, Nat.sub_self, Nat.zero_mul]
      have hsplit : eraLen * (decaySum (b / eraLen) + decay (b / eraLen + 1))
          = eraLen * decaySum (b / eraLen) + eraLen * decay (b / eraLen + 1) :=
        Nat.mul_add _ _ _
      have hEmul : eraLen * decay (b / eraLen + 1)
          = (eraLen - 1 - 0) * decay (b / eraLen + 1) + decay (b / eraLen + 1) := by
        unfold eraLen; omega
      omega
    · -- interior: same era, position advances
      have hdiv : (b + 1) / eraLen = b / eraLen := by
        unfold eraLen at hb ⊢; omega
      have hmod : (b + 1) % eraLen = b % eraLen + 1 := by
        unfold eraLen at hb ⊢; omega
      rw [hiss, hdiv, hmod]
      rw [hdiv] at hr
      have hpos : b % eraLen < eraLen - 1 := by
        unfold eraLen at hb ⊢; omega
      -- position term drops by exactly one decay(e); reward consumes ≤ one
      have : (eraLen - 1 - b % eraLen) * decay (b / eraLen)
          = (eraLen - 1 - (b % eraLen + 1)) * decay (b / eraLen)
            + decay (b / eraLen) := by
        have : eraLen - 1 - b % eraLen
            = (eraLen - 1 - (b % eraLen + 1)) + 1 := by
          unfold eraLen at hpos ⊢; omega
        rw [this, Nat.succ_mul]
      have ht : tail * (b + 1) = tail * b + tail := Nat.mul_succ tail b
      omega

/-- Base-reward issuance bound at every height. -/
theorem issued_le (B : Nat) :
    issued B ≤ tail * B + eraLen * decaySum (B / eraLen) :=
  Nat.le_trans (Nat.le_add_right _ _) (issued_invariant B)

/-- THE SUPPLY THEOREM (base rewards): for every B,
    7·issued(B) ≤ 7·tail·B + 1000·eraLen·d0 — that is, base-reward
    issuance through any height is at most 0.2 ETT per block plus a
    once-for-all-time decay component below eraLen·d0·1000/7 wei
    ≈ 25,714,285.71 ETT. -/
theorem supply_bound (B : Nat) :
    7 * issued B ≤ 7 * (tail * B) + 1000 * (eraLen * d0) := by
  have h1 := issued_le B
  have h2 := decaySum_le (B / eraLen)
  have h3 : 7 * (eraLen * decaySum (B / eraLen))
      = eraLen * (7 * decaySum (B / eraLen)) := Nat.mul_left_comm _ _ _
  have h4 : eraLen * (7 * decaySum (B / eraLen)) ≤ eraLen * (1000 * d0) :=
    Nat.mul_le_mul_left _ h2
  calc 7 * issued B
      ≤ 7 * (tail * B + eraLen * decaySum (B / eraLen)) :=
        Nat.mul_le_mul_left _ h1
    _ = 7 * (tail * B) + 7 * (eraLen * decaySum (B / eraLen)) := Nat.mul_add _ _ _
    _ ≤ 7 * (tail * B) + eraLen * (1000 * d0) := by
        rw [h3]; exact Nat.add_le_add_left h4 _
    _ = 7 * (tail * B) + 1000 * (eraLen * d0) := by
        rw [Nat.mul_left_comm eraLen 1000 d0]

/-- The uncle channel (everettRewards): a block with u ≤ 2 uncles mints
    R + 2u·⌊R/32⌋ ≤ (9/8)·R. So every base-reward bound above scales by
    at most 9/8 for full-chain issuance: decay component < 28.93M ETT,
    tail rate ≤ 0.225 ETT/block. -/
theorem uncle_multiplier (r u : Nat) (hu : u ≤ 2) :
    8 * (r + (2 * u) * (r / 32)) ≤ 9 * r := by
  have hu2 : u = 0 ∨ u = 1 ∨ u = 2 := by omega
  cases hu2 with
  | inl h => subst h; omega
  | inr h2 => cases h2 with
    | inl h => subst h; omega
    | inr h => subst h; omega

/-- Era-boundary anchor the review noted both test suites lacked. -/
example : reward 99999 = 2000000000000000000 := by native_decide

end Everett
