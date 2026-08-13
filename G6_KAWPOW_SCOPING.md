# G6 Scoping: the KawPow Port

**Date:** 2026-08-12. Goal: replace devnet-placeholder ethash with KawPow
(ProgPoW 0.9.4 + Ravencoin parameters = the shipped form of EIP-1057) as
Everett's launch algorithm, per the 2026-08-12 consensus decision.

## Source material (verified)

- **go-quai** (`dominant-strategies/go-quai`, `consensus/progpow/`): a
  complete Go ProgPoW implementation, ~79 KB across `algorithm.go` (41 KB,
  the DAG/keccak-f800/random-math core), `algorithm_progpow.go` (12 KB),
  `progpow.go` (18 KB, the consensus.Engine), `sealer.go` (6 KB), plus
  tests. This is the port base; go-quai runs its own parameter set, so
  every constant must be diffed against KawPow's.
- **Ravencoin C++ reference** (`RavenProject/Ravencoin`, `src/crypto/
  kawpow` lineage) and **kawpowminer**: the authoritative KawPow constants
  and, critically, test vectors for differential testing.
- KawPow deltas from generic ProgPoW 0.9.4 to confirm during P1 (from the
  Ravencoin spec; verify against source, do not trust this memo): period
  length 3 blocks (vs 10), Ravencoin-specific kiss99 initialization
  constants ("KAWPOW" seeding), epoch length 7500 blocks, and header-hash
  domain separation.

## Architecture

New `consensus/kawpow` package in the core-geth fork implementing
`consensus.Engine`, sitting beside ethash rather than patching it:

1. **Rewards: no work.** `Finalize` calls `mutations.AccumulateRewards`,
   and our hook keys on chain ID, not engine, so Article III applies
   under any engine unchanged.
2. **DAA: small work.** The ASERT hook currently lives on
   `ethash.CalcDifficulty`; the kawpow engine gets the same three-line
   guard calling the same parent-only `everettCalcDifficulty`. Move that
   function to a shared package so both engines import one copy.
3. **Seal/VerifySeal: the real port.** Adapt go-quai's algorithm files to
   KawPow constants; keep light-verification (cache + cDAG) for header
   validation, full DAG for mining.
4. **Genesis config:** a `"kawpow": {}` engine block replacing
   `"ethash": {}`; everything else in genesis.json is engine-agnostic.

## Verification loop (the gate structure that caught the LWMA bug, reused)

- **P2 differential gate:** the Go implementation must reproduce
  Ravencoin/kawpowminer test vectors bit-exactly (seed, header, nonce →
  mix hash + final hash) before any devnet work. This is the equivalent
  of the wei-exact reward audit: an independent reference implementation
  to disagree with.
- **P4 full regate:** every existing gate reruns under kawpow: 12 unit
  tests, wei-exact reward audit, burn audit, and the two-node sync test,
  which is non-negotiable now that we know what windowed/DB-dependent
  logic does during batch verification.
- **P5 hardware gate:** T-Rex and kawpowminer speak KawPow stratum
  natively, so the RTX 3080 realism pass finally becomes practical: a
  small Go stratum sidecar translates miner stratum to the node's work
  RPC (Ravencoin-ecosystem open-source proxies are prior art). This tests
  ASERT under ~40 MH/s of real hashrate, the experiment sim scenario A
  approximates.

## Effort estimate

Two to four focused weeks solo: P1 vendor+diff (days), P2 vectors (days,
the highest-risk step: constant mismatches hide here), P3 engine (days),
P4 regate (a day, automated), P5 sidecar+GPU (days). Fits the
launch-in-waiting posture: no deadline, correctness gates throughout.

## Risks

- **Constant drift:** go-quai's ProgPoW is not KawPow; a single wrong
  kiss99 seed produces a chain only we can mine. The P2 differential gate
  exists for exactly this.
- **DAG size:** irrelevant at launch (fresh chain, epoch 0, ~1 GB DAG, so
  every 4 GB gamer card works), grows slowly thereafter; revisit the
  growth schedule during P1 diffing.
- **Verification cost:** ProgPoW light-verify is milliseconds per header,
  heavier than ethash but fine; batch-sync throughput should be measured
  in P4, not assumed.
- **License:** go-quai is LGPL-3.0 like core-geth; compatible, tracked in
  LICENSE.
