# Everett Runbook

## Goal ladder (auto-adjusted; log below)

- **G1:** devnet boots genesis-devnet.json, mines, passes verify_devnet.sh. ✅ 2026-08-12
- **G2:** reward patch grounded in real core-geth source, unit-tested. ✅ live wei-exact
- **G3:** DAA decision. ✅ v2: ASERT (v1 LWMA split consensus, superseded)
- **G4:** two-node trustless sync from genesis + independent audit. ✅
- **G5:** Article IV burn proven on-chain. ✅ 147,000 wei destroyed, 3 accounts exact
- **G6:** KawPow Go port (launch algorithm). ⏳ open, largest remaining item

## Verification loop (three independent gates)

1. **Go unit tests** (`client/rewards_everett_test.go`): exact wei vectors
   for D(0..2), half-life neighborhood at era 98, slow-start midpoint, tail
   floor at era 5000, uncle split. Runs inside `boot_devnet.sh` before build;
   build aborts on failure.
2. **Live reward audit** (`scripts/verify_rewards.py`): recomputes the entire
   schedule in Python (independent implementation) and demands the mining
   coinbase balance equal the constitutional sum wei-for-wei at head. Stock
   core-geth pays flat 2/block and fails instantly, so the gate cannot pass
   vacuously. Also pins the genesis hash and asserts London-at-genesis and
   the absence of beacon-era fields.
3. **Cross-language agreement:** gates 1 and 2 implement Article III twice
   from the text alone. Divergence in either direction is a spec ambiguity;
   fix the constitution's wording, not just the code.

## How to run

```bash
scripts/boot_devnet.sh        # clone, patch, test, build, init, mine
scripts/verify_devnet.sh      # in a second shell, against localhost:8545
```

Expect several minutes of DAG generation on first mine (ethash epoch 0).

## Status log

- 2026-08-12: Constitution v0.1 + genesis spec drafted. Chain ID 1559 found
  taken (Tenet); switched to 15537393, mainnet's last PoW block, verified
  free. extraData 32-byte cap discovered; headline moved inside constitution,
  hash-only commitment.
- 2026-08-12: Continuous-decay formula replaced with discrete-era integer
  schedule (x993/1000 per 100,000 blocks, ~4.07y half-life) after reading
  core-geth's ECIP-1017 implementation; consensus code cannot float. G2
  artifacts written: patch, tests, hook applier, boot + verify scripts.
- 2026-08-12: **G1 blocked**: session-level classifier gate denies general
  shell execution (curl-only survives). Unblocked same evening by user
  switching to bypass permissions.
- 2026-08-12 evening: **G1 PASSED.** Full pipeline ran: gate 1 unit tests
  green on first compile. Two dependency fixes needed for modern Go
  (blst v0.3.11 → v0.3.17; fjl/memsize excised, three lines, same as
  upstream geth). Genesis accepted; geth-style fork keys parse fine but
  `disposalBlock` is silently dropped (bomb live ~16mo in; spec §5a.4).
  Genesis difficulty 0x100000000 stalls CPU mining (open item 3 confirmed
  empirically); genesis-devnet.json variant at 0x20000 created. Devnet
  genesis hash: 0xb7400b2d9b641ada0816f64bacad70d5cdaf522b851c2ce959702adfa91a6b79.
  **Gate 2 PASSED wei-for-wei**: 4 blocks, miner balance 215,053,763,440,860
  wei == independent Python recomputation exactly, slow-start scaling
  verified live (R(n) = 2e18·n/93000 for n=1..4). Go and Python implement
  Article III identically from the text alone (gate 3).
- 2026-08-12 late: **G3 decided and shipped.** DAA simulator
  (scripts/daa_sim.py) ran 4 shock scenarios; Byzantium DAA spends 8-16 h
  degraded where LWMA-45 takes minutes. LWMA-45 adopted (DAA_MEMO.md),
  implemented (client/difficulty_everett.go, 5 unit tests green), and
  live-verified: difficulty ×10.8 in 44 blocks, solvetimes converging to
  the 9-18 s band, reward audit still wei-exact at 53 blocks
  (30,774,193,548,387,073 wei).
- 2026-08-12 late: design explainer published as artifact:
  https://claude.ai/code/artifact/53c1227d-f998-4599-9150-8b30c7fad913
  (lineage, voting-room mechanism, comparison matrix, issuance chart,
  live verification receipts). Source: explainer.html.
- 2026-08-12 night: **LWMA split consensus in the two-node sync test**
  (verifier rejected block 3: windowed DAA read ancestors the batch verifier
  didn't have; "invalid difficulty: have 131072, want 135607"). Pivoted to
  relative ASERT (tau=1800 s), parent-only by signature, 7 unit tests incl.
  determinism regression. Sync test rerun: node1=node2=50 blocks, node2
  audited independently, wei-exact. Correction to the earlier G3 entry:
  LWMA is superseded; DAA_MEMO.md v2 governs.
- 2026-08-12 night: **Article IV burn verified live**: funded miner account,
  sent a type-2 tx, burn_audit.py modeled every account exactly at 341
  blocks; 147,000 wei destroyed (21,000 gas x 7 wei decayed base fee).
- 2026-08-12 night: **Launch algorithm decision: KawPow** (ProgPoW 0.9.4 +
  Ravencoin params = shipped EIP-1057). Rationale: idle gamer-GPU fleet is
  AI-poach-proof (Jiajun's argument, accepted); stranded-ASIC "commitment"
  illusory (NiceHash rents it); counterfactual lore (no Merge => ProgPoW
  ships). Devnet stays ethash until the Go port (G6).
- 2026-08-12 night: **55-agent adversarial audit: 39 confirmed findings, all
  fixed**: uncle issuance constitutionalized (new Art. III.5), Art. V.1 now
  bans genesis code/storage, R(0)=0 stated, slow-start wording matches code,
  spec 5a rewritten to status-accurate, KZG precompile range and tx types
  corrected, boot script defaults to genesis-devnet.json and gates both test
  suites, genesis-hash pinning added (EXPECT_GENESIS env), disposalBlock
  dead key removed, daa_sim.py now contains the cited ASERT evidence,
  explainer refreshed (ASERT data, KawPow row, DAO/crowdsale fixes) and
  republished as rev 0.2.
- 2026-08-12 late night: **Named: Everett** (Hugh Everett III, many-worlds;
  "Ethereum's Everett branch"), ticker ETT (sole prior use dead/unlisted).
  Repo renamed ~/lifeboat → ~/everett; all code identifiers, docs, and the
  explainer renamed; full regate after rename: 12/12 unit tests green,
  fresh devnet mining, reward audit wei-exact at 7 blocks. Explainer
  republished (same artifact URL) as rev 0.2 with the naming lore.
- Next: G6 KawPow port scoping; multi-miner devnet (uncle-aware audit
  scripts first); pre-v1.0 trademark/domain sweep for Everett/ETT;
  optional 3080 realism pass.
