# G6 (KawPow) status

Phases from G6_KAWPOW_SCOPING.md, with what is proven and how.

| Phase | State | Evidence |
|---|---|---|
| P1 vendor + parameter diff | **done** | `client/kawpow/reference/go-quai/` (unmodified LGPL source), `G6_P1_NOTES.md` (117 verified facts with source URLs, produced by a 5-agent research fleet) |
| P2 differential vectors | **done, bit-exact** | `client/kawpow_core_test.go`: DAG size schedule (10 vectors), epoch seed chain, epoch-0 cDag (20 words), the Ravencoin smoke vector, and primary hash vectors across period and epoch boundaries. Green locally and in CI on a clean runner. Negative-controlled: flipping the period constant 3→4 fails the suite. |
| P3 engine wiring | **done** | `client/kawpow_engine.go` + `scripts/apply_kawpow_hooks.py`: verifySeal and sealer hooks, light-cache manager, full-DAG generator for node-side mining |
| P4 devnet regate under KawPow | in progress | isolated devnet (chain ID 15537391, `genesis-dev.json`), DAG generating |
| P5 stratum sidecar + GPU | next | design in G6_P1_NOTES.md §4 (wire dialect fully specified from kawpowminer source) |

## Two findings the vectors caught

1. **KawPow needs its own seed hash.** core-geth's `seedHash()` re-derives an
   epoch from a block using the hardcoded 30000-block ethash epoch, so
   passing KawPow's 7500-block epochs through it silently produced the wrong
   seed. `kawpowSeedHash(epoch)` iterates keccak256 directly.
2. **KawPow has its own DAG schedule**, not ethash's: 1 GiB init (not 4 GiB),
   8 MiB growth, 128 KiB cache growth, and 512 dataset parents. The size
   vectors caught this before a single hash was computed.

## Activation policy (deliberate, not an oversight)

The engine is gated on `EVERETT_KAWPOW=1`. Environment variables must never
decide consensus on a public network: two nodes with different environments
would fork. The gate exists so the algorithm can be proven end-to-end in
isolation. **Before Wheeler or mainnet runs KawPow, activation moves into the
chain config** (GENESIS_SPEC 5a.5), where it is part of the genesis every
node agrees on.

## The Wheeler flip: a decision, not a default

Wheeler currently runs ethash and has ~1100 blocks, two miners, and a
distributed client package. Switching its algorithm invalidates all of that.
Two options, both defensible:

- **Re-genesis Wheeler on KawPow.** Faithful to mainnet (which is KawPow from
  genesis). Costs: the chain restarts at 0, distributed packages need a
  rebake, and anyone mid-sync starts over. Testnet resets are normal (Ropsten,
  Görli, Sepolia all did it).
- **Fork Wheeler at a future block.** Rehearses a hard-fork transition
  instead, which mainnet will never do at genesis, so it tests a path that
  does not exist in production.

Recommendation: re-genesis, once P4 and P5 are green and Justin has had a
chance to see the network as it stands. Not to be done unilaterally
overnight: it is the one action here that breaks something someone else was
invited to.
