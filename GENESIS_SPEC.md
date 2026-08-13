# Everett Genesis Specification

**Version 0.1 draft. Companion to CONSTITUTION.md, which governs.**

## 1. Client

- Base: **core-geth** (the maintained ethash-capable geth lineage used by ETC).
  Rationale: modern geth deleted PoW at the Merge; core-geth is the shortest
  path to a production PoW EVM client. A reth-based second client is a
  post-launch goal (client diversity), not a launch requirement.
- All PoS-era machinery removed or absent: no beacon/Engine API dependency for
  consensus, no deposit contract, no withdrawal processing (EIP-4895), no
  beacon block root in EVM (EIP-4788).

## 2. Consensus parameters

| Parameter | Value | Rationale |
|---|---|---|
| Algorithm | **KawPow at launch** (decided 2026-08-12); ported, chain-keyed, and live on Wheeler v2 (§5a.5 resolved; dev chain 15537391 remains ethash-or-KawPow selectable for experiments) | GPU-first, ASIC-resistant (ProgPoW family, production-hardened by Ravencoin). Rationale: the idle gamer-GPU fleet (10/20/30-series cards with no AI market value) is the one hashpower pool the AI boom cannot poach; ASIC "commitment" proved illusory since the stranded fleet rents itself out via NiceHash; and in the counterfactual timeline this chain memorializes, Ethereum ships ProgPoW instead of deferring it for the Merge. |
| Target block time | ~13 s | Ethash-native cadence; inherits well-tested uncle/difficulty behavior. |
| Difficulty adjustment | **Relative ASERT, half-life 1800 s** (decision v2, see DAA_MEMO.md); difficulty bomb moot (ASERT replaces the whole formula) | Parent-only by construction. LWMA-45 was adopted first and split consensus during the second-node sync test (windowed DAAs read ancestors the batch verifier doesn't have yet). ASERT converges in 1.2-2.5 h across all four shock scenarios and cannot diverge between miner and verifier. |
| Uncle rules | Pre-merge validity rules (max 2, depth limit); rewards per Constitution Art. III.5: flat `R/32` per uncle (ETC Era-2 style), NOT pre-merge's depth-scaled payouts | Validity unchanged from pre-merge; reward amounts are constitutional and differ from pre-merge Ethereum's. |
| Genesis header params | gasLimit 36,000,000 (0x2255100, miner-votable under pre-merge rules) · baseFeePerGas 1 gwei · nonce 0x42 (homage) · timestamp set at launch | Consensus-relevant genesis values, documented here per Art. VIII.1. |
| Chain ID | 15537393 (verified free on chainlist; 1559 is taken by Tenet) | Mainnet's final proof-of-work block number. The chain ID is the block where the old plan ended. |

## 3. Monetary parameters (fixed by Constitution Art. III-IV)

| Parameter | Value |
|---|---|
| Block reward at genesis | 0, scaling linearly over blocks 1-93,000 (~14 days) |
| Decay term D(0) | 1.8 ETT |
| Era length | 100,000 blocks (~15 days at 13 s) |
| Per-era decay | × 993/1000, integer floor division (ECIP-1017-style exact math) |
| Effective half-life | ~98.7 eras ≈ 4.07 years at target block time |
| R_tail | 0.2 ETT per block, perpetual |
| Cumulative issuance from decay term | 100,000 × 1.8/0.007 ≈ 25.7M ETT (asymptotic) |
| Tail issuance | ~485k ETT/yr at 13 s blocks |
| Base fee | EIP-1559, burned |
| Priority fee | To miner |
| Uncle rewards | winner +R/32 per uncle, uncle miner R/32 (ETC Era-2 scheme), same schedule |

Supply shape: ~25M from the decaying term over the first decades, plus linear
tail forever, minus burn. Inflation rate declines monotonically toward zero;
absolute security spend never does.

## 4. EVM and transaction surface at genesis

Launch at Cancun-equivalent EVM, minus anything requiring a beacon chain:

**Included:** all Shanghai/Cancun opcodes (PUSH0, TSTORE/TLOAD, MCOPY),
EIP-6780 SELFDESTRUCT semantics, EIP-7702 set-code transactions, transaction
types 0/1/2/4, standard precompiles 0x01-0x09 (0x0A is the EIP-4844 KZG
point-evaluation precompile and is excluded with the rest of the blob layer).

**Excluded:** EIP-4844 blob transactions and the KZG point-evaluation
precompile (blob layer assumes a consensus-layer sidecar; this is an L1-first
chain), EIP-4788, EIP-4895, PREVRANDAO semantics (opcode 0x44 returns
difficulty, as pre-merge; contracts must not treat it as randomness, which
they never should have anyway).

## 5. Open items

1. **DAA responsiveness. RESOLVED 2026-08-12 (v2):** relative ASERT
   (half-life 1800 s) implemented, unit-tested, and live-verified with a
   two-node sync. The v1 choice (LWMA-45) was implemented first and split
   consensus during batch sync; see DAA_MEMO.md for both decisions.
2. **Rentable-hashpower 51% exposure.** Ethash is the most liquid rentable
   hashpower market in existence (NiceHash), and ETC absorbed three rental
   51% attacks in August 2020 alone. The constitution forbids checkpoints,
   so mitigations are social only: deep exchange confirmations, reorg
   monitoring, and enough genesis difficulty that rental attacks cost real
   money. Accepted risk, documented, not engineered away. The courted ASIC
   fleet cuts both ways: stranded fleets are concentrated, and one warehouse
   may be a majority of early hashrate.
3. **RESOLVED 2026-08-13 — launch difficulty.** See LAUNCH_DIFFICULTY.md,
   derived from measured Wheeler v2 data (42 MH/s per 3080-class card at
   epoch 0; ASERT absorbed a ×4,200 error in 75 live minutes).
   Recommendation: mainnet genesis difficulty **0x40000000** (≈ two
   3080-class cards at 13 s) — the correction asymmetry means err LOW:
   an underestimate clears in minutes of fast blocks, an overestimate
   stalls the chain. genesis.json still says 0x100000000; the change is
   deliberately deferred to the v1.0 freeze so the ceremony commit
   carries it.
4. **Client maintenance funding.** Article V forbids the treasury that would
   otherwise fund perpetual client work, and every upstream geth CVE must be
   evaluated and ported forever. The assumed model is Bitcoin-style external
   patronage (sponsor companies, grants from outside the protocol).
   Unresolved, and structural: the constitution deliberately deprives the
   chain of the resource that would pay its own mechanics.
5. **Second client.** reth-with-ethash tracked as post-launch milestone.
6. **Name and ticker. RESOLVED 2026-08-12:** Everett, for Hugh Everett III;
   the chain is Ethereum's Everett branch. Ticker ETT (sole prior use,
   EncryptoTel, is dead and unlisted). Full trademark/domain/handle sweep
   owed before the v1.0 freeze.

## 5b. Networks

| Network | Chain ID | Genesis | Purpose |
|---|---|---|---|
| **Everett** (mainnet) | 15537393 · mainnet's last PoW block | genesis.json · empty extraData until the v1.0 freeze commits the constitution hash | Reserved for the Article VIII launch ceremony. Do not start it casually. |
| **Wheeler** (testnet) | 15537392 · the penultimate PoW block, the rehearsal | genesis-wheeler.json · extraData tags "EVERETT WHEELER V2 KAWPOW", genesis hash `abd9ba…5e8934` | Named for John Wheeler, Everett's advisor. Identical consensus rules via the family hooks; coins valueless by intent. v1 (ethash, extraData "EVERETT WHEELER TESTNET") ran 2026-08-13 to ~4.6k blocks and was retired at the **v2 re-genesis 2026-08-13: KawPow from genesis**, rehearsing mainnet's real algorithm. |
| **dev** (local/CI) | 15537391 | genesis-dev.json · 0x20000 difficulty floor so CPU miners work | Throwaway devnets and CI e2e. Never sign anything you care about on it. The legacy genesis-devnet.json (chainId 15537393, colliding with reserved mainnet — an EIP-155 replay hazard for any key reused there) is deprecated: kept in-tree for stacks already running it, not for new devnets. |

## 5a. Client patches (delta from stock core-geth)

The monetary constitution lives in client code, not genesis config. Status
as of 2026-08-12 evening: items 1-4 are implemented, unit-tested, and
live-verified on the devnet (wei-exact reward audit through 341 blocks
including a 1559 burn; two-node trustless sync from genesis).

1. **DONE** — Reward schedule per Art. III: block-number-driven discrete
   eras (`era = block/100,000`, ×993/1000 per era, 0.2 ETT tail), slow
   start `min(block, 93,000)/93,000`, uncle issuance per Art. III.5.
   `params/mutations/rewards_everett.go`, five unit tests.
2. **DONE** — Relative ASERT DAA (decision v2, DAA_MEMO.md), parent-only by
   construction: `consensus/ethash/difficulty_everett.go`, seven unit
   tests including the batch-sync determinism regression. ASERT replaces
   the entire Byzantium formula, so the difficulty bomb is moot; the inert
   `disposalBlock` key (silently dropped by the geth-style config path) has
   been removed from the genesis files.
3. **DONE** — Hook appliers (`scripts/apply_hook.py`,
   `scripts/apply_daa_hook.py`), idempotent, anchored on upstream function
   signatures.
4. **DONE** — Test gates wired into `boot_devnet.sh` (TestEverett +
   TestASERT run before every build; build aborts on failure).
5. **DONE 2026-08-13** — KawPow launch algorithm: ported bit-exact
   (Ravencoin test vectors, differential gate `TestKawPow` in CI and in
   the Docker image build), GPU-proven live (RTX 3080, stock kawpowminer,
   both getwork and the stratum sidecar — see `stratum/E2E_REPORT.md`).
   Activation is **chain-keyed** (`SetKawPowChainID`, hook 5 in
   `apply_kawpow_hooks.py`): Wheeler and mainnet run KawPow from genesis,
   the dev chain (15537391) keeps an `EVERETT_KAWPOW=1` env choice for
   experiments, and every other chain ID is forced off — consensus never
   depends on local environment on a public network. Wheeler flipped to
   KawPow at its v2 re-genesis 2026-08-13.
6. **OPEN** — Later EVM surface: Shanghai/Cancun opcodes without
   withdrawals (ETC's Spiral upgrade is the precedent) and EIP-7702
   (type-4 transactions) without EIP-4844: fork-bundle surgery, not
   configuration.

## 6. Launch procedure (per Constitution Art. VIII)

1. Publish constitution, this spec, client binaries and source, and genesis
   JSON at T minus 30 days or more.
2. Genesis extra-data: `keccak256(CONSTITUTION.md v1.0)`, exactly 32 bytes.
   Ethash caps extra-data at 32 bytes, so the headline cannot live there; it
   is carried inside the constitution text (Art. VIII.3) and committed
   through the single hash. Zeros stand in until the v1.0 freeze.
3. Genesis state: empty. No balances, no contracts.
4. Anyone with a KawPow miner (stock kawpowminer/T-Rex via the stratum sidecar) and the client participates from block 1.
   The authors of this document hold no advantage beyond conviction.
