# Launch difficulty memo

Closes GENESIS_SPEC §5 open item 3 ("launch difficulty estimation").
Everything below is derived from measured Wheeler v2 data (2026-08-13),
not folklore.

## Measured inputs

| Quantity | Value | Source |
|---|---|---|
| 3080-class KawPow hashrate, epoch 0 | ~42 MH/s | share-rate arithmetic on Wheeler v2 (5.3 shares/s at 8M share difficulty); the 1 GiB epoch-0 DAG runs hotter than Ravencoin's grown epochs |
| Block/share ratio sanity | 5.1% observed vs 4.8% expected | confirms full-difficulty verification, so the hashrate number is trustworthy |
| ASERT absorption, measured | 131k → ~550M (×4,200) in ~75 min | Wheeler v2 launch ramp, τ=1800s |

## The asymmetry that decides everything

ASERT corrects an error factor F in roughly `1800·ln(F)` seconds of
*chain time*, and chain time only advances when blocks are found.

- **Genesis too LOW**: blocks come fast, chain time races, correction is
  quick and cheap. A ×4,200 underestimate cleared in 75 minutes, live.
- **Genesis too HIGH**: blocks crawl. A ×10 overestimate with one
  3080-class card means ~17-minute expected block times while ASERT
  claws down at minutes-per-block pace. A ×100 overestimate could stall
  the chain for a day and hand the narrative to "dead on arrival."

So the genesis difficulty question is not "guess arriving hashpower"
(unknowable within orders of magnitude) but "what is the least
hashpower we are confident shows up, then err LOW from there."

## Recommendation

Current genesis.json guesses `0x100000000` (4.295G ≈ 330 MH/s ≈ eight
3080-class cards at 13 s). That is an *optimistic* floor: if launch day
brings two cards, first blocks average ~50 s and the first hour is
sluggish television.

**Set mainnet genesis difficulty to `0x40000000` (1.074G ≈ 82 MH/s ≈
two 3080-class cards).**

- Two cards (the founder-side minimum: the 3080 + Justin's 3090 exist
  today): ~13 s blocks from block 1. On-target television.
- Twenty cards (~850 MH/s): ~1.3 s blocks initially; ASERT reaches
  equilibrium in ≈ `1800·ln(10)` ≈ 70 minutes of fast blocks. Measured
  behavior, not theory: Wheeler absorbed worse.
- A thousand cards: bursty first half hour, equilibrium inside two
  hours, slow-start (Art. III) keeps the issuance distortion of the
  burst phase negligible (~93k-block ramp dwarfs any 2-hour transient).
- One lone card: ~26 s blocks, self-correcting downward within the
  first hour. Slow but visibly alive; the failure mode is boredom, not
  death.

The launch-day dashboard (tools/dashboard) should be published alongside
the ceremony so the difficulty ramp is watchable in public; the ramp IS
the proof the chain is absorbing real hashpower.

## Non-change

Wheeler keeps its 0x20000 devnet-style floor: testnets should be
joinable by anything, and ASERT demonstrably handles the consequences.
