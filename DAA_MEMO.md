# G3 Decision Memo: Difficulty Adjustment Algorithm

**Date:** 2026-08-12. **Decision v2 (same day): adopt relative ASERT,
half-life 1800 s. LWMA-45 (decision v1, below) was implemented, passed all
unit tests, ran correctly on a single node, and then SPLIT CONSENSUS the
moment a second node tried to sync:** the miner computed difficulty from a
45-header window read out of its database, but during batch header
verification the syncing node's database does not yet contain those
ancestors, so it computed from a shorter, padded window and rejected block 3
("invalid difficulty: have 131072, want 135607"). Any windowed DAA bolted
onto the geth verification pipeline has this hazard; Ethereum's own DAA is
parent-only for exactly this reason.

**The fix is architectural, not a patch: the DAA must be parent-only by
construction.** Relative ASERT qualifies: `D_next = D_parent *
2^(-(st-13)/1800)`, st clamped to [1, 10800], exponent capped at one
halving/doubling per block, floor 131072, computed with the aserti3-2d
fixed-point cubic Bitcoin Cash has run in production since 2020. The Go
implementation takes `(time, parent)` and no chain reader, so the compiler
enforces the property, and a determinism regression test pins it.

ASERT shock performance (same simulator, same scenarios): flood 1.2 h,
production overshoot 1.6 h, 90% exodus 2.5 h, rental waves 1.7 h; steady
state under Poisson noise holds 13.0 s mean with no drift. Slower than
LWMA's sub-hour numbers, far faster than Byzantium's 8-16 h, and it cannot
disagree with itself. Correctness beats convergence speed.

Timestamp-games note: at tau = 1800, a miner lying by the +15 s future
allowance moves difficulty ~0.6% per block, self-correcting on the next
honest timestamp. Acceptable; do not loosen the future-time limit.

---

## Decision v1 (superseded, kept for the record)

**Date:** 2026-08-12. **Decision: adopt LWMA-45, drop Byzantium DAA.**
Evidence: `scripts/daa_sim.py`, deterministic shock simulation.

## The question

Byzantium's DAA (what core-geth ships) adjusts at most +1/2048 (~+0.05%) per
block upward and −99/2048 (~−4.8%) per block downward. It was tuned for a
mature chain with stable hashrate. Everett's launch reality is the opposite:
lumpy stranded-ASIC fleets arriving at once, NiceHash rental waves, and the
risk of mass exit. ETHW's miserable first weeks and every small-PoW-chain
post-mortem trace to exactly this mismatch.

## Simulation results (target 13 s; conv = 50 consecutive blocks in 9-18 s)

| Scenario | DAA | Blocks to converge | Hours degraded | Worst block |
|---|---|---|---|---|
| A: 180× hashrate flood at min difficulty | Byzantium | 17,831 | 8.1 h | 6 s |
| | LWMA-45 | **124** | **0.2 h** | 12 s |
| B: production genesis, ~3.7× overshoot (first solvetime ~48 s) | Byzantium | 1,275 | 9.5 h | 48 s |
| | LWMA-45 | **81** | **0.4 h** | 48 s |
| C: 90% hashrate exodus at equilibrium | Byzantium | 1,576 | 15.7 h | 2.2 min |
| | LWMA-45 | **95** | **0.7 h** | 2.2 min |
| D: 3× NiceHash waves (10× on/off, 300 blk) | Byzantium | 350/wave | 0.3 h | 18 s |
| | LWMA-45 | 85/wave | 0.2 h | 2.1 min |

Reading: Byzantium's upward crawl turns a fleet arrival (A) into 8 hours of
seconds-fast blocks (uncle storms, spam-cheap chain) and turns exodus (C)
into a 16-hour near-stall. LWMA converges in minutes in every scenario. The
one genuine trade shows in D: because LWMA tracks the rental wave up, the
wave's exit leaves a deeper single-block stall (2.1 min vs 18 s) before fast
recovery. That trade is worth it: total degraded time still favors LWMA, and
waves are survivable while 16-hour stalls are chain-killers.

(Sim artifact note: Byzantium's "final blocktime 17.5 s" reflects the
deterministic no-uncle model drifting to its dead-zone edge; real chains with
uncle-rate feedback average ~13 s. Does not affect the comparison.)

## Implementation requirements

1. Replace `CalcDifficulty` for the Everett chain ID with LWMA-45 (linear
   weights over last 45 solvetimes, clamped to [1, 6T]), min difficulty
   131072 retained.
2. Tighten the future-timestamp allowance (geth default +15 s is acceptable;
   do NOT loosen) and clamp negative solvetimes. LWMA is more sensitive to
   timestamp games than Byzantium; the clamp plus FTL is the standard
   mitigation on LWMA chains.
3. Keep `daa_sim.py` as the regression harness; any future DAA tuning must
   rerun the four scenarios and not regress C (exodus) below the current
   LWMA numbers.
4. Optional realism pass: RTX 3080 via getwork against a devnet running each
   DAA, validating the sim's A/B curves with real Poisson noise. Blocked on
   Ampere-era miner software speaking getwork (classic ethminer predates
   sm_86; modern miners want stratum), so this needs a stratum proxy and is
   deferred; the sim is the decision basis.

## Consequence for the uncle argument

Fast blocks during floods (Byzantium's failure mode in A) inflate uncle
rates, which under Article III pay real rewards, so the slow DAA is not
just an inconvenience, it is an issuance leak under attack. LWMA closes it.
