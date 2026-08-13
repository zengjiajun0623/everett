# G6_P1_NOTES.md · Everett: KawPow port of go-quai ProgPoW

Status: research notes, phase G6/P1. Date 2026-08-12.

Base for the port: `dominant-strategies/go-quai` @ main = `7faedb3ec9209ea16002e023e9bfe683cd13bf02`. The `consensus/progpow` package contains exactly five files: `algorithm.go`, `algorithm_progpow.go`, `progpow.go`, `progpow_test.go`, `sealer.go` (verified via the GitHub contents API [gq-pkg]). Header validation and difficulty live under `core/`, not in the engine package.

KawPow authority: there is no standalone KawPow spec or KIP. `https://github.com/RavenCommunity/kawpow` returns 404 and no spec document surfaced in search. The effective spec is the ProgPoW 0.9.4 README [pp-spec] plus Ravencoin's constant overrides, with `RavenProject/Ravencoin` `src/crypto/ethash` [rvn-pp] and `RavenCommunity/cpp-kawpow` [ck] as reference implementations. KawPow's complete delta vs ProgPoW 0.9.4 is: PERIOD 10 → 3, epoch length 30000 → 7500, and the RAVENCOINKAWPOW keccak padding replacement [pp-spec].

---

## 1. Parameter diff: go-quai ProgPoW vs KawPow

### 1.1 Full table

| Parameter | go-quai ProgPoW | KawPow | Port action |
|---|---|---|---|
| PROGPOW_LANES | 16 (`progpowLanes`) [gq-app] | 16 [rvn-hpp][kpm-h] | none |
| PROGPOW_REGS | 32 (`progpowRegs`) [gq-app] | 32 [rvn-hpp][kpm-h] | none |
| PROGPOW_DAG_LOADS | 4 (`progpowDagLoads`) [gq-app] | 4 (miner define; node computes 256/(4·16)=4) [kpm-h][rvn-pp] | none |
| PROGPOW_CACHE_BYTES | 16·1024 = 16 KiB, 4096 words (`progpowCacheBytes/Words`) [gq-app] | 16·1024, 4096 words (`l1_cache_size`) [rvn-hpp] | none |
| PROGPOW_CNT_DAG (outer loops) | 64 (`progpowCntDag`) [gq-app] | 64 (hard-coded loop; miner define) [rvn-pp][kpm-h] | none |
| PROGPOW_CNT_CACHE | 11 (`progpowCntCache`) [gq-app] | 11 [rvn-hpp][kpm-h] | none |
| PROGPOW_CNT_MATH | 18 (`progpowCntMath`) [gq-app] | 18 [rvn-hpp][kpm-h] | none |
| DAG item granularity | 256-byte item (`progpowMixBytes`), dataset passed as size/256 items [gq-app] | 256-byte `hash2048`, `num_items = full_dataset_num_items/2` (128-byte base items) [rvn-pp][rvn-eth] | none (equivalent) |
| **PROGPOW_PERIOD** | **10** (`progpowPeriodLength`) [gq-app] | **3** (`period_length`; Ravencoin's deviation from 0.9.4's 10) [rvn-hpp] | **change** |
| **Period/epoch basis** | header `PrimeTerminusNumber`, not zone height [gq-app][gq-eng] | block height; prog_seed = height/3, epoch = height/7500 [rvn-pp][ck-src] | **decide** (§5) |
| **Epoch length** | `C_epochLength` = BlocksPerMonth·3/4 = 388800 prime blocks [gq-alg][gq-par] | 7500 (`ETHASH_EPOCH_LENGTH`) [rvn-ethh][kpm-h] | **change** |
| **Dataset init size** | 1<<32 = 4 GiB (`datasetInitBytes`) [gq-alg] | 1<<30 = 1 GiB (`full_dataset_init_size`) [rvn-eth] | **change** |
| **Dataset growth/epoch** | 1<<26 = 64 MiB [gq-alg] | 1<<23 = 8 MiB [rvn-eth] | **change** |
| Cache init size | 1<<24 = 16 MiB (`cacheInitBytes`) [gq-alg] | 1<<24 = 16 MiB [rvn-eth] | none |
| **Cache growth/epoch** | 1<<21 = 2 MiB [gq-alg] | 1<<17 = 128 KiB [rvn-eth] | **change** |
| Epoch-0 dataset bytes | `datasetSizes[0]` = 4294962304 [gq-alg] | 1073739904 [ck-eth] | **regenerate tables** |
| Epoch-0 cache bytes | `cacheSizes[0]` = 16776896 [gq-alg] | 16776896 [ck-eth] | same at epoch 0 only; schedules diverge from epoch 1 |
| Size search rule | largest size with size/hashBytes (cache) resp. size/mixBytes (dataset) prime, step down 2·64 / 2·128 [gq-alg] | largest prime num_items for 64-byte cache items / 128-byte dataset items (`ethash_find_largest_prime`) [rvn-eth] | none (same rule, new init/growth inputs) |
| datasetParents | 512 (already double geth's 256) [gq-alg] | 512 (`full_dataset_item_parents`; this is the 0.9.4 DAG tweak vs ethash's 256) [rvn-eth][pp-spec] | none |
| cacheRounds | 3 [gq-alg] | 3 (`light_cache_rounds`) [rvn-eth] | none |
| Seed hash | keccak256 iterated over 32 zero bytes, block/epochLength times [gq-alg] | identical mechanism (`ethash_calculate_epoch_seed`) [rvn-eth] | none (epoch length change flows through) |
| Keccak permutation | f[800], 25×uint32 state, 22 rounds, standard truncated RC/rot/pi [gq-app] | f[800], 22 rounds, no padding, same standard constants [rvn-kf][kpm-cu] | none |
| **Initial keccak absorb** | st[0..7]=header, st[8..9]=nonce lo/hi, st[10..17]=result (zeroed at entry), st[18..24]=0 [gq-app] | st[0..7]=header, st[8..9]=nonce lo/hi, **st[10..24]=RAVENCOINKAWPOW[0..14]** [rvn-pp][ck-src] | **change** |
| **Intermediate seed carry** | 64-bit seed via byte-swap quirk (st[0] BE → ret[4:8], st[1] BE → ret[0:4], LE-read) [gq-app] | 256-bit carry: all 8 output words go to the final keccak; words 0,1 are the KISS99 `hash_seed` directly [rvn-pp] | **change** |
| **Final keccak absorb** | st[0..7]=headerHash, st[8..9]=seed64, st[10..17]=mix, st[18..24]=0 [gq-app] | **st[0..7]=initial-keccak output words 0..7, st[8..15]=mix, st[16..24]=RAVENCOINKAWPOW[0..8] ("RAVENCOIN")** [rvn-pp][ck-src] | **change** |
| Final output | st[0..7] each LE, 32 bytes [gq-app] | LE words 0..7 [rvn-pp] | none |
| mixHash | result[0..7] LE, 32 bytes [gq-app] | mix_hash words [rvn-pp] | none |
| KISS99 | z=36969·(z&0xffff)+(z>>16); w=18000·(w&0xffff)+(w>>16); jsr xorshift 17/13/5; jcong=69069·jcong+1234567; out=((z<<16)+w)^jcong)+jsr [gq-app] | identical [rvn-kiss] | none |
| FNV | fnv1a offset 0x811c9dc5, prime 0x1000193, (h^d)·prime [gq-app] | identical [rvn-bit] | none |
| fillMix / init_mix seeding chain | z=fnv1a(basis,seed_lo), w=fnv1a(·,seed_hi), jsr=fnv1a(·,lane), jcong=fnv1a(·,lane), chained via pointer [gq-app] | z=fnv1a(0x811c9dc5,hash_seed[0]); w=fnv1a(z,hash_seed[1]); jsr=fnv1a(w,l); jcong=fnv1a(jsr,l) [rvn-pp] | none (same chain; but inputs change, see quirk note below) |
| progpowInit / mix_rng_state chain | z=fnv1a(basis,lo), w=fnv1a(·,hi), jsr=fnv1a(·,lo), jcong=fnv1a(·,hi), then Fisher-Yates of 32-entry dst/src seqs via kiss99 [gq-app] | identical chain and shuffles [rvn-pp][kpm-cpp] | none |
| merge() ops | r%4: (a·33)+b, (a^b)·33, rotl32(a,((r>>16)%31)+1)^b, rotr32 variant [gq-app] | identical [rvn-pp] | none |
| math() ops | r%11: +, ·, mulhi, min, rotl, rotr, &, \|, ^, clz+clz, popcount+popcount [gq-app] | identical [rvn-pp] | none |
| Inner loop shape | 18 math iterations, cache access only when i<11; cache offset = mix[l][src] % 4096 [gq-app] | same 0.9.2/0.9.3-style counts [rvn-hpp] | none |
| DAG access per loop | gOffset = mix[loop%16][0] % items; 4×64B reads at word indices (gOffset·16)·4+{0,16,32,48}; per lane 4 words at ((lane^loop)%16)·4; word 0 merges into mix[l][0] [gq-app] | leader = mix[r%16][0] % (num_items/2); lane reads 4 sequential words at ((lane^r)%16)·4; first merged word targets reg 0 [rvn-pp] | none |
| Lane reduction / result fold | FNV-1a from 0x811c9dc5 over 32 regs; result[lane%8] folds laneResults [gq-app] | unchanged vs 0.9.4 spec (KawPow's only deltas are period/epoch/padding) [pp-spec] | none |
| cDag / L1 cache | first 16 KiB of dataset; built as 256× generateDatasetItem 64B items → 4096 LE uint32 [gq-alg] | first 16 KiB of DAG, filled from `calculate_dataset_item_2048` [rvn-hpp][rvn-eth] | none (verify byte-identity with L1 vector, §3.3) |

### 1.2 The keccak rework, precisely

This is the only nontrivial algorithm surgery. In go-quai [gq-app]:

- `keccakF800Short(headerHash, nonce, result)` absorbs header(8w) + nonce(2w) + result(8w, zero-initialized by `progpow()`) with st[18..24]=0, runs 22 rounds (`for r<21` plus explicit round 21), then writes st[0] big-endian into ret[4:8] and st[1] big-endian into ret[0:4] and returns `LittleEndian.Uint64(ret)`. Net effect: the 64-bit seed is words 0 and 1 swapped and byte-reversed (derived from the stated write/read order).
- `keccakF800Long(headerHash, seed, result)` absorbs header(8w) + seed64(2w) + mix(8w), st[18..24]=0, 22 rounds (`for r<=21`), returns st[0..7] LE.

KawPow [rvn-pp][ck-src]:

- Initial: st[0..7]=header, st[8..9]=nonce lo/hi, st[10..24] = `ravencoin_kawpow[0..14]` = {0x72,0x41,0x56,0x45,0x4E,0x43,0x4F,0x49,0x4E,0x4B,0x41,0x57,0x50,0x4F,0x57} (ASCII "RAVENCOINKAWPOW", one char per uint32). One permutation. Output words 0,1 = `hash_seed` for lane init; words 0..7 are carried whole.
- Final: st[0..7] = the carried 8 words (NOT headerHash), st[8..15]=mix, st[16..24] = `ravencoin_kawpow[0..8]` ("RAVENCOIN" only). One permutation; final hash = LE words 0..7.

Port consequences:

1. Replace the 64-bit seed carry with an 8-word (`[8]uint32`) carry; delete the swap/byte-reverse quirk entirely. `fillMix` consumes carry words 0 and 1 directly as (seed_lo, seed_hi). The FNV chain order is already identical on both sides.
2. Initial keccak no longer takes `result`; drop the result[8] zero-init absorb from `progpow()`.
3. Final keccak signature changes from (headerHash, seed64, mix) to (carry8, mix); headerHash no longer appears in the final absorb.
4. Add the `ravencoin_kawpow[15]` constant array. Do NOT invent an Everett-specific string if stock miners must work: the constant is baked into closed-source miners (T-Rex) and every kawpow kernel; changing it forks the algorithm away from all existing mining software.
5. Cleanup: unify both round loops to `for r := 0; r < 22`. go-quai's two loop forms are already equivalent to 22 rounds; the constants (`keccakfRNDC`, `keccakfROTC`, `keccakfPILN`) are standard and identical to KawPow's, keep them [gq-app][rvn-kf][kpm-cu].

---

## 2. Port checklist, file by file

### 2.1 `consensus/progpow/algorithm_progpow.go` [gq-app]

- [ ] `progpowPeriodLength`: 10 → 3.
- [ ] Add `ravencoinKawpow [15]uint32` constant.
- [ ] Rewrite `keccakF800Short` → returns `[8]uint32` carry; absorb per §1.2; remove `result` param and the output byte-swap quirk.
- [ ] Rewrite `keccakF800Long` → takes carry8 + mix; absorb per §1.2.
- [ ] `progpow()`: thread the carry through (hash_seed = carry[0..1] into `fillMix`; full carry into final keccak). Keep the lane reduction (FNV-1a 0x811c9dc5 over 32 regs, fold into result[lane%8]) and mixHash serialization unchanged.
- [ ] Leave untouched: `kiss99`, `fnv1a`, `fillMix` chain, `progpowInit` chain + Fisher-Yates, `merge`, `progpowMath`, `progpowLoop` (18 math / 11 cache / cache offset % 4096), DAG access formulas, `progpowLight` (generateDatasetItem(cache, index/16, keccak512)), `progpowFull` (cDag = first 4096 dataset words).
- [ ] Period basis: `period = number / 3` where `number` must be the exact value miners will receive as the mining.notify height field (§4.2, §5).

### 2.2 `consensus/progpow/algorithm.go` [gq-alg]

- [ ] `datasetInitBytes`: 1<<32 → 1<<30. `datasetGrowthBytes`: 1<<26 → 1<<23. `cacheGrowthBytes`: 1<<21 → 1<<17. `cacheInitBytes` (1<<24), `mixBytes` (128), `hashBytes` (64), `hashWords` (16), `datasetParents` (512), `cacheRounds` (3), `loopAccesses` (64): unchanged.
- [ ] `C_epochLength`: sever from `params.BlocksPerMonth`; hard constant 7500.
- [ ] Regenerate `datasetSizes`/`cacheSizes` lookup tables for the KawPow schedule (or drop tables and always compute). `calcCacheSize`/`calcDatasetSize` prime-search logic is unchanged and matches ethash; only init/growth inputs change. Pin against cpp-kawpow's size vectors (§3.4 layer 0): epoch 0 must give cache 16776896 and dataset 1073739904.
- [ ] `seedHash`, `generateCache`, `generateDatasetItem`, `generateCDag`: no changes. All four mechanisms already match KawPow (keccak256 seed chain; keccak512 fill + 3 RandMemoHash rounds; 512 FNV parents; cDag = first 16 KiB of dataset). Verify cDag byte-identity with the L1 vector (§3.3).
- [ ] `maxProgpowCacheBytes` (64 MiB): the go-quai comment ties it to the KawPow transition; recompute policy for Everett. Derived: KawPow cache(e) = 16 MiB + e·128 KiB reaches 64 MiB near epoch 384 ≈ block 2,880,000; either raise the bound over time or accept it as a far-future ceiling.
- [ ] Optional: delete the unused `hashimoto`/`hashimotoLight`/`hashimotoFull` leftovers (verification uses `progpowLight`, not `hashimotoLight`).

### 2.3 `consensus/progpow/progpow.go` [gq-eng]

- [ ] Bump `algorithmRevision` (cache files are named `cache-R%d-%x`) so stale ProgPoW-schedule caches on disk are never reused under the new schedule.
- [ ] `cache.generate()`: flow unchanged (seedHash/cacheSize at epoch·7500+1, always builds cDag); new epoch length flows through. LRU + speculative future-epoch generation unchanged.
- [ ] `validateProgpowHeader`: remove the `blockNumber <= KawPowForkBlock + KawPowTransitionPeriod` (= 1301100) upper bound; that gates go-quai's own ProgPoW sunset, not Everett's. Keep the PrimeTerminusNumber nil/uint64 check and the cacheSize <= maxProgpowCacheBytes check (re-derived per §2.2).
- [ ] `ComputePowLight`: currently keys cache/datasetSize/period entirely off `header.PrimeTerminusNumber()`. Keep or rekey per the §5 decision; whatever is chosen must equal the stratum notify height.
- [ ] Keep the 10000-entry `hashCache` LRU and header atomic caching as-is. Note `ModeTest` forces a 1024-byte cache: KawPow vectors will NOT reproduce under ModeTest; vector tests must build the real epoch-0 cache (16 MiB, cheap).

### 2.4 `consensus/progpow/sealer.go` [gq-sl]

- [ ] Mechanics unchanged: `progpowLight(size, cache, sealHash, nonce, primeTerminusNumber, cDag)` per attempt; lazy per-epoch cDag generation picks up the new epoch length automatically.
- [ ] `MineToThreshold(…, params.WorkSharesThresholdDiff=3, …)` seals to a workshare target 2^3 easier than the block target via `CalcWorkShareThreshold` [gq-cons]. This is a quai-ism; keep or drop per Everett design, and note it maps neatly onto stratum share targets (§4.2).
- [ ] The CPU sealer becomes a devnet/test tool once GPU miners connect via stratum; keep it.

### 2.5 `consensus/progpow/progpow_test.go`

- [ ] Replace vectors wholesale with the KawPow set (§3). Test entry points are the pure functions (`progpowLight` with plain heights), not the engine, to avoid PrimeTerminus plumbing in unit tests.

### 2.6 `params/protocol_params.go` [gq-par]

- [ ] `KawPowForkBlock` (1171500) and `KawPowTransitionPeriod` (129600, so ProgPoW valid through PT 1301100): these encode go-quai's own ProgPoW → KawPow handoff. Everett defines its own fork schedule (or ships KawPow from genesis); remove or repurpose.
- [ ] Any epoch-length derivation from `DurationLimit`/`BlocksPerDay`/`BlocksPerMonth` must not feed the PoW epoch anymore (KawPow's 7500 is absolute, not time-derived).

### 2.7 `core/` (dispatch and seal verification)

- [ ] `core/headerchain.go` `GetEngineForHeader`: currently returns the Kawpow engine iff `header.AuxPow() != nil && PrimeTerminusNumber >= 1171500`, else the Progpow engine [gq-hc]. Rewire for Everett's single-engine or fork rule. Note for P2: go-quai main evidently already contains a KawPow engine behind this dispatch; audit `consensus/kawpow` (not covered by these findings) before writing code, it may already be most of this port.
- [ ] `core/headerchain_validation.go` `verifySeal` needs no algorithm changes: it calls the engine's `ComputePowHash` (which enforces mixHash equality via `ErrInvalidMixHash`) then checks powHash <= 2^256/difficulty [gq-hcv]. The engine interface stays `{Seal, ComputePowHash, ComputePowLight, SetThreads}` with no VerifySeal [gq-cons].

---

## 3. Test-vector plan

### 3.1 Sources, ranked

1. **Primary**: `RavenCommunity/cpp-kawpow` `test/unittests/progpow_test_vectors.hpp` [ck-vec]: 13 cases `{block_number, header_hash, nonce, mix_hash, final_hash}`. Last touched by commit 058f5457f0 (2020-03-25) after the 0.9.4 update commit 67a80ef972 (2020-03-11). Ravencoin core vendors a byte-identical copy (`src/crypto/ethash/progpow_test_vectors.hpp`, diff-verified) consumed by `src/test/kawpow_tests.cpp` [rvn-tst], so node and standalone lib share one vector set.
2. Auxiliary vectors from `cpp-kawpow` `test_progpow.cpp` and `test_ethash.cpp` (§3.3) [ck-tpp][ck-eth].
3. Independent third-party vector from `MintPond/hasher-kawpow` `test.js` [mp-h] (§3.3, caveats).
4. **Do not use**: upstream `chfast/ethash` v0.5.2 progpow vectors. At the same heights they differ completely (block 0/nonce 0 gives mix f4ac2027…, final b3bad9ca… vs KawPow's 6e97b47b…/e601a725…), and upstream chains each header from the previous final hash while cpp-kawpow headers are independent [chfast][ck-vec]. Any accidental import of these is a silent wrong-algorithm test.
5. `kawpowminer` has NO hash vectors (test/kernel.cu is a generated kernel dump for prog_seed 600, test/result.log a benchmark log); do not mine it for vectors [kpm-tst].

Nonce parsing: `nonce_hex` is a plain big-endian uint64 hex string, parsed with `stoull(hex, 16)` [ck-vec]. Header/mix/final are 32-byte hex.

### 3.2 Primary vector table (all 13, from [ck-vec])

Epoch = h/7500 and period = h/3 columns are derived here for harness convenience.

| # | Block | Epoch | Period | Header hash | Nonce | Expected mix_hash | Expected final_hash |
|---|---|---|---|---|---|---|---|
| 1 | 0 | 0 | 0 | 0000000000000000000000000000000000000000000000000000000000000000 | 0000000000000000 | 6e97b47b134fda0c7888802988e1a373affeb28bcd813b6e9a0fc669c935d03a | e601a7257a70dc48fccc97a7330d704d776047623b92883d77111fb36870f3d1 |
| 2 | 49 | 0 | 16 | 63155f732f2bf556967f906155b510c917e48e99685ead76ea83f4eca03ab12b | 0000000007073c07 | d36f7e815ee09e74eceb9c96993a3d681edf2bf0921fc7bb710364042db99777 | e7ced124598fd2500a55ad9f9f48e3569327fe50493c77a4ac9799b96efb9463 |
| 3 | 50 | 0 | 16 | 9e7248f20914913a73d80a70174c331b1d34f260535ac3631d770e656b5dd922 | 00000000076e482e | d6dc634ae837e2785b347648ea515e25e5d8821ae0b95e1c2a9c2d497e0dcfbd | ab0ad7ef8d8ee317dd12d10310aceed7321d34fb263791c2de5776a6658d177e |
| 4 | 99 | 0 | 33 | de37e1824c86d35d154cf65a88de6d9286aec4f7f10c3fc9f0fa1bcc2687188d | 000000003917afab | fa706860e5e0e830d5d1d7157e5bea7f5f8a350c7c8612ac1d1fcf2974d64244 | aa85340690f2e907054324a5021937910e15edfd1ef1577231843e7d32ec3a61 |
| 5 | 29950 | 3 | 9983 | ac7b55e801511b77e11d52e9599206101550144525b5679f2dab19386f23dcce | 005d409dbc23a62a | 5359807b77a74878269c3a3044df8618a576ce8dc52e1c48d927d4a60e7c6b79 | 022019e5408683f7f8326b4e46b42864a3a069f17b6151e434fcaedecaadd918 |
| 6 | 29999 | 3 | 9999 | e43d7e0bdc8a4a3f6e291a5ed790b9fa1a0948a2b9e33c844888690847de19f5 | 005db5fa4c2a3d03 | d15de3f9bfedd9b6d0f498273eb3b437115bdc8326c96c6457ac06deb5c9f389 | 4e93630b81198752f876b24380999189b7b9366c08222ac05e4237b87114f305 |
| 7 | 30000 | 4 | 10000 | d34519f72c97cae8892c277776259db3320820cb5279a299d0ef1e155e5c6454 | 005db8607994ff30 | de0348b69bf91dfe2c3d3dba6f0132e9048a5284e57b8d9d20adc5f3dc0d3236 | c7953d848cda6e304f77b4c6d735645c8e8508a5e74c9e9814ef37b19087cd6c |
| 8 | 30049 | 4 | 10016 | 8b6ce5da0b06d18db7bd8492d9e5717f8b53e7e098d9fef7886d58a6e913ef64 | 005e2e215a8ca2e7 | 975c6a9decc89cba7ace69338d4de8510d9619aef42b1d35d0bef7e0ce0614a9 | c262d8055e288d04b951a844bfca8ba529f5b4d652b408e3942727d7dd90957a |
| 9 | 30050 | 4 | 10016 | c2c46173481b9ced61123d2e293b42ede5a1b323210eb2a684df0874ffe09047 | 005e30899481055e | 362f2fabdb9699d3634b6499703f939f378ee4eac803396c2b0ed0fe1d154972 | 4cd7e6e79e0b63d42b2b06716a919ccc7834077ec727a9ea94edcdaff2fefab8 |
| 10 | 30099 | 4 | 10033 | ea42197eb2ba79c63cb5e655b8b1f612c5f08aae1a49ff236795a3516d87bc71 | 005ea6aef136f88b | b1196457261bd05ccb387a8ff3fd02687bf496bd7943d89419465289669e27aa | 39d1ebfa783b61a6fa8e9747d0f9f134efae5cfba284a2c80e8deabae6b98676 |
| 11 | 59950 | 7 | 19983 | 49e15ba4bf501ce8fe8876101c808e24c69a859be15de554bf85dbc095491bd6 | 02ebe0503bd7b1da | df3dbb1669fd35dbb0ae96bbea2d498f0c6992cbddd092aeace42dd933505f95 | b8984cf4021c4433f753654848d721f33a0792b4417241f0cf7c7c2db011a54a |
| 12 | 59999 | 7 | 19999 | f5c50ba5c0d6210ddb16250ec3efda178de857b2b1703d8d5403bd0f848e19cf | 02edb6275bd221e3 | 5017df70e97ca35638cf439cdbe54f30383d335e18eb4a74d6e166736f1038fa | 4cf1fa62f25b577ac822a6a28d55f8b7e3ae7fe983abd868ae00927e68c41016 |
| 13 | 170915 | 22 | 56971 | 5b3e8dfa1aafd3924a51f33e2d672d8dae32fa528d8b1d378d6e4db0ec5d665d | 0000000044975727 | efb29147484c434f1cc59629da90fd0343e3b047407ecd36e9ad973bd51bbac5 | e7e6bb3b2f9acd3864bc86f72f87237eaf475633ef650c726ac80eb0adf116b6 |

Coverage notes: epoch boundary pair (#6 at 29999/e3 vs #7 at 30000/e4), same-period pairs (#2/#3 both period 16; #8/#9 both period 10016), and a large-DAG case (#13, epoch 22).

### 3.3 Auxiliary vectors

- **Smoke vector** (present in BOTH Ravencoin `kawpow_tests.cpp` and cpp-kawpow `test_progpow.cpp`): block 30000, header `ffeeddccbbaa9988776655443322110000112233445566778899aabbccddeeff`, nonce `0x123456789abcdef0` → mix `177b565752a375501e11b6d9d3679c2df6197b2cab3a1ba2d6b10b8c71a3d459`, final `c824bee0418e3cfb7fae56e0d5b3b8b14ba895777feea81c70c0ba947146da69` [rvn-tst][ck-tpp]. Run this first (verify-first-unit).
- **L1 cache / cDag vector**: first 20 LE uint32 words of the epoch-0 L1 cache (first 16 KiB of DAG) = {2492749011, 430724829, 2029256771, 3095580433, 3583790154, 3025086503, 805985885, 4121693337, 2320382801, 3763444918, 1006127899, 1480743010, 2592936015, 2598973744, 3038068233, 2754267228, 2867798800, 2342573634, 467767296, 246004123} [ck-tpp][rvn-tst]. Compare against go's `generateCDag` output directly.
- **Search vector**: epoch 0, block 0, empty header, boundary `00ffffff…ff`, start nonce 300, 100 iterations → finds solution nonce 395; start nonce 700 → finds nothing [ck-tpp][rvn-tst]. Port as a sealer-loop test.
- **Epoch seed chain** (`test_ethash.cpp` epoch_seed_test_cases): epoch 0 → 32 zero bytes; 1 → 290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563; 171 → a9b0e0c9aca72c07ba06b5bbdae8b8f69e61878301508473379bb4f71807d707; 2048 → 20a7678ca7b50829183baac2e1e3c43fa3c4bcbc171b11cf5a9f30bebd172920; 29998 → 1222b1faed7f93098f8ae498621fb3479805a664b70186063861c46596c66164; 29999 → ee1d0f61b054dff0f3025ebba821d405c8dc19a983e582e9fa5436fc3e7a07d8 [ck-eth]. (Standard ethash seed chain; KawPow only remaps block → epoch as h/7500.)
- **Size schedule** (`test_ethash.cpp` dataset_size_test_cases, {epoch, cache, dataset}): {0, 16776896, 1073739904}, {14, 18611392, 1191180416}, {17, 19004224, 1216345216}, {56, 24116672, 1543503488}, {158, 37486528, 2399139968}, {203, 43382848, 2776625536}, {211, 44433344, 2843734144}, {272, 52427968, 3355440512}, {350, 62651584, 4009751168}, {412, 70778816, 4529846144} [ck-eth].
- **Independent pool-side vector** (MintPond hasher-kawpow test.js): header `63543d3913fe56e6720c5e61e8d208d05582875822628f483279a3e8d9c9a8b3`, height 262523, nonce uint64 `0x88a23b0033eb959b` → mix `89732e5ff8711c32558a308fc4b8ee77416038a70995670e3eb84cbdead2e337`, final `0000000718ba5143286c46f44eee668fdf59b8eba810df21e4e2f4ec9538fc20` [mp-h]. Caveats: the addon takes the nonce as a little-endian 8-byte buffer (test.js byte-reverses the hex), and which chain block 262523 refers to is UNVERIFIED; treat as a bonus cross-check, not a gate.

### 3.4 Differential-test design (layered, fail at the first divergent layer)

- **Layer 0, pure constants**: table-driven Go tests of `cacheSize`/`datasetSize` against the 10 size vectors and `seedHash` against the 6 epoch-seed vectors. No hashing involved; catches schedule mistakes before anything expensive.
- **Layer 1, cache and cDag**: generate the real epoch-0 cache (16 MiB; do NOT use ModeTest's 1024-byte cache, vectors will not reproduce) and cDag; compare the first 20 words with the L1 vector. One check covers keccak512 fill, 3 RandMemoHash rounds, 512-parent item generation, and cDag assembly.
- **Layer 2, full hashes**: run `progpowLight(datasetSize(h), cache, header, nonce, h, cDag)` with plain heights for the smoke vector then all 13 primary vectors; assert both mix and final. Order the table so #1 runs first; abort the suite on first failure with intermediates dumped (below).
- **Layer 3, search/seal**: the search vector through the mining loop (boundary compare, nonce iteration), asserting nonce 395 found from 300 and nothing from 700.
- **Layer 4, negative tests** (mirroring cpp-kawpow's harness): decrement final_hash byte 31 → verification must fail; increment mix byte 7 → must fail [ck-tpp]. Maps to the engine's `ErrInvalidMixHash` and the headerchain's powHash target check.
- **Layer 5, cross-implementation fuzz**: build cpp-kawpow's test binary as the oracle; feed identical (height, header, nonce) triples to the Go port and the C++ lib and diff mix/final. Reuse cpp-kawpow's deterministic generator recipe (ETHASH_TEST_GENERATION, nonce = b³·977 + b²·997 + b·1009) for reproducible corpora; add random small heights across period boundaries (h ≡ 0,1,2 mod 3) and the 7500 epoch boundary. Optional third opinion: `kryptex/hasher-kawpow` (Python) or `MintPond/hasher-kawpow` (Node) [mp-h][kx-h].
- **Bisection hooks**: behind a build tag, expose (a) initial keccak output words 0..7, (b) lane-0 registers after fillMix, (c) mix[0][0] after each of the 64 loops, (d) laneResults/result before the final keccak. On a layer-2 failure, diff these against an instrumented cpp-kawpow build to localize the divergence to keccak-absorb vs RNG-seeding vs loop vs reduction in one run.

Reference harness shape (what cpp-kawpow itself does): `context = create_epoch_context(get_epoch_number(h)); result = progpow::hash(context, h, header, nonce); compare hex(mix), hex(final)` [ck-tpp].

---

## 4. Stratum sidecar plan

### 4.1 Goal and shape

Stock KawPow miners speak "stratum" = kawpowminer's STRATUM mode 0 (`stratum+tcp`); the miner-side authority is `EthStratumClient.cpp` [kpm-es], scheme-to-mode mapping in `PoolURI.cpp` [kpm-uri] (stratum1 = eth-proxy, stratum2 = EthereumStratum/1.0.0 NiceHash, stratum3 = 2.0.0; bare scheme = autodetect). Everett ships a **sidecar**: stratum server on one side, Everett node work API on the other. Recommended implementation: **Go, importing the ported `consensus/progpow` package directly for local share verification.** That is the structural advantage over every existing repo: kralverde's proxy has no local PoW check at all (forwards every submit to submitblock), and kawpow-stratum-pool needs an external kawpowd HTTP service or a `getkawpowhash` daemon RPC [kral][ksp-jm].

### 4.2 Wire dialect (implement exactly this)

| Direction | Method | Params / result |
|---|---|---|
| miner → | `mining.subscribe` | `["agent/version"]` (single string). Reply result MUST be an array of size > 1: `[null, extranonce_hex]`; kawpowminer takes result[1] as extranonce [kpm-es] |
| miner → | `mining.authorize` | `[address.worker, password]` → `true` (kawpowminer sends id=3) [kpm-es] |
| pool → | `mining.set_target` | `[target_64hex]`; send before every notify (kralverde pattern) [kral][kpm-es] |
| pool → | `mining.notify` | 7 elements, exact order: `[jobId, headerHash_64hex, seedHash_64hex, target_64hex, cleanJobs_bool, height_int, bits_hex]` [kpm-es][ksp-bt][kral] |
| miner → | `mining.submit` | exact order: `[address.worker, jobId, 0x + nonce_16hex, 0x + headerHash_64hex, 0x + mixHash_64hex]` → bool. Full 64-bit nonce including the extranonce prefix; mixhash included [kpm-es] |
| miner → | `eth_submitHashrate` | `[0xrate, 0xid]`; accept and optionally aggregate [kral] |

Rules and gotchas, all source-verified:

- **Extranonce = nonce prefix.** kawpowminer accepts 2..8 hex chars (max 4 bytes), right-pads to 16 with '0', and uses it as the high-order start value of the 64-bit nonce space [kpm-es]. Assign per connection: 2-byte big-endian counter (kralverde) or 3 random bytes (kawpow-stratum-pool `crypto.randomBytes(3)`) [kral][ksp-jm]. On submit, enforce the prefix; note kawpow-stratum-pool enforces only the first 4 hex chars (2 bytes) even though it issues 3 bytes [ksp-jm].
- **Validation sizes**: nonce exactly 16 hex chars, mixhash exactly 64 [ksp-jm]. Accept `0x` prefixes tolerantly (kralverde strips optional prefixes; kawpow-stratum-pool blindly strips 2 chars, so miners always send `0x`) [kral][ksp-st].
- **height is consensus-critical**: the miner computes prog_seed = height/3 from the notify height field and generates its kernel from it [rvn-pp][kpm-cpp]. Everett MUST send the exact number the node's period/epoch are keyed on. If the port keeps PrimeTerminusNumber keying, notify height = PrimeTerminusNumber, or every share goes stale/invalid at period boundaries.
- **seedHash**: keccak256-iterated from 32 zero bytes, iterations = epoch = number/7500; miners use it for DAG selection. Derive it from the same number as height. Recompute backwards on reorgs across an epoch boundary (kralverde does) [kral].
- **headerHash**: opaque 32-byte value the miner absorbs into keccak-f800. In Ravencoin it is `reverse(sha256d(80-byte header))` where the 80-byte header is version+prevHash+merkleRoot+nTime+nBits+height (height sits in Bitcoin's nonce slot) [kral][ksp-bt]. For Everett it is simply `header.SealHash()`, the same value `progpowLight` receives; no double-SHA needed. Miners never parse it.
- **target/bits**: solo mode can send the block target verbatim from the node (kralverde uses getblocktemplate's `target` and `bits` unchanged; share target = block target, no vardiff) [kral]. `bits` is parsed by kawpowminer with `SetCompact` [kpm-es], so supply Everett difficulty in compact encoding. Vardiff later = per-miner `mining.set_target`; `mining.set_difficulty` exists only in the NiceHash dialect [kpm-es]. Quai's workshare target (2^3 easier via `CalcWorkShareThreshold`) is a natural built-in share target if Everett keeps workshares [gq-sl][gq-cons].
- **No `mining.set_extranonce` / `mining.extranonce.subscribe`** in the plain dialect (that is NiceHash mode 2, which also submits only the nonce suffix without 0x and without mixhash). Do not mix the dialects [kpm-es][kral].
- **Submit pipeline**: (1) prefix + size checks; (2) recompute `progpowLight(sealHash, nonce, number)` in-process, reject on mixhash mismatch (cheap DoS filter, same check as `ComputePowHash`'s `ErrInvalidMixHash`); (3) result <= share target → accept share; (4) result <= block target → set nonce (`types.EncodeNonce`) + MixHash on the WorkObject and submit to the node; log node responses per submit (kralverde keeps `./submit_history/`) [kral][gq-eng][gq-sl].
- **Byte order at block assembly** (Ravencoin-specific, keep in mind when designing Everett serialization): stratum carries nonce/mixhash in display order; Ravencoin block serialization appends both byte-reversed after the 80-byte header, then varint txcount + txs [kral][ksp-jm].

### 4.3 Reusable repos

| Repo | Lang | License | Use as | Caveats |
|---|---|---|---|---|
| kralverde/ravencoin-stratum-proxy [kral] | Python, single file ~696 lines | **none** | Primary behavioral reference for the solo flow (subscribe/notify/submit/block assembly); most-forked (19★/21 forks) | No license → do not vendor code, reimplement. No local PoW verification. Last push 2024-03-04. NBMiner reported erroring against it |
| RavenCommunity/kawpow-stratum-pool [ksp-st][ksp-jm][ksp-bt] | Node | (not verified) | Reference for share-validation rules, extranonce discipline, canonical notify/getJobParams, block serialization | Full-pool complexity; PoW check needs external kawpowd/getkawpowhash |
| hans-schmidt/kawpow_personal_stratum_server [kpss] | Node | GPL-2.0 | Second solo reference; multi-instance pattern | Author: "not production-ready"; GPL contaminates reused code |
| MintPond/ref-stratum-ravencoin [mp-ref] | Node | MIT | Clean-room reference stratum for testing/experimentation | Node v10 era; uses compiled KawPOW verification |
| MintPond/hasher-kawpow [mp-h], kryptex/hasher-kawpow [kx-h] | Node / Python | | Off-the-shelf hash/verify bindings for test tooling and cross-checks | LE nonce buffer convention in MintPond addon |
| traysi/kawpow-stratum-pool, Satoex/kawpow-stratum-pool, LabyrinthCore/kawpow-stratum [gh-search] | Node | | Secondary references only | Forks/alternates of the above |
| oliverw/miningcore [mc] | C# | MIT | **Do not use** | Archived 2023-10-20; coins.json has zero raven/kawpow/progpow/firopow entries (grep-verified); kawpow was only a crowdfunding discussion (#1334) |

Ranking judgment (kralverde first as reference, KPSS second, adapt kawpow-stratum-pool validation logic) is my call; the repo properties above are verified.

### 4.4 Miner test matrix

- **kawpowminer** [kpm]: open source, the dialect's source of truth; first target.
- **T-Rex** [trex]: closed source (binaries code-mangled), 1% dev fee, kawpow via `-a kawpow -o stratum+tcp://…`; dialect conformance is interop-verified (works against kralverde proxy and kawpow-stratum-pool pools), not source-verified.
- **TeamRedMiner, Gminer, TT-Miner**: reported working against kralverde's proxy / KPSS [kral][kpss].
- **NBMiner**: reported erroring against kralverde's proxy; investigate before claiming support [kral].
- **lolMiner: no KawPow support.** Feature request issue #1750 (2022) unanswered, algorithm table and 1.93-1.98a release notes omit kawpow/RVN [lol]. Do not list it.

### 4.5 Sidecar test plan

1. **Golden JSON tests**: notify construction from a fixed work fixture, byte-for-byte against the canonical 7-element shape (`getJobParams` in [ksp-bt]); submit parsing against kawpowminer's exact param order [kpm-es].
2. **Verification unit tests**: feed the §3.2 vectors through the sidecar's share-check path (sealHash=vector header, height=vector block) and assert accept/reject at contrived targets, plus the §3.4 layer-4 negative mutations.
3. **Devnet loop**: Everett devnet at low difficulty, sidecar attached, kawpowminer pointed at `stratum+tcp://`; assert accepted share → submitted block → `verifySeal` passes on-chain.
4. **Cross-miner pass**: repeat with T-Rex and one of TeamRedMiner/Gminer.
5. **Boundary soak**: run across period boundaries (heights ≡ 0 mod 3) and an epoch boundary (shrink epoch length in a test build if waiting for 7500 devnet blocks is impractical) to smoke out height/seedHash keying mismatches, the number-one failure mode from §4.2.

---

## 5. Open decisions (need a call before P2 code)

1. **Period/epoch keying**: keep go-quai's PrimeTerminusNumber keying (then stratum notify height carries PT and epoch cadence is in prime blocks) or rekey to plain header height for maximal miner-ecosystem intuition. Either works; the invariant is one number feeding period, epoch, seedHash, and notify height consistently.
2. **Domain constant**: keep `RAVENCOINKAWPOW` for stock-miner compatibility (recommended; closed miners hard-code it) vs an Everett constant that forks the algorithm and orphans all existing mining software.
3. **Fork shape**: KawPow from genesis vs a transition window (go-quai's KawPowForkBlock/TransitionPeriod machinery is a template if a handoff is wanted).
4. **Workshares**: keep `MineToThreshold`/`CalcWorkShareThreshold` (2^3 easier) and align stratum share targets to it, or plain block-target solo first.
5. **maxProgpowCacheBytes policy** under the 128 KiB/epoch schedule (§2.2).

---

## References

- [gq-app] https://raw.githubusercontent.com/dominant-strategies/go-quai/main/consensus/progpow/algorithm_progpow.go
- [gq-alg] https://raw.githubusercontent.com/dominant-strategies/go-quai/main/consensus/progpow/algorithm.go
- [gq-eng] https://raw.githubusercontent.com/dominant-strategies/go-quai/main/consensus/progpow/progpow.go
- [gq-sl] https://raw.githubusercontent.com/dominant-strategies/go-quai/main/consensus/progpow/sealer.go
- [gq-par] https://raw.githubusercontent.com/dominant-strategies/go-quai/main/params/protocol_params.go
- [gq-cons] go-quai consensus/consensus.go (Engine interface, CalcWorkShareThreshold)
- [gq-hcv] https://raw.githubusercontent.com/dominant-strategies/go-quai/main/core/headerchain_validation.go
- [gq-hc] https://raw.githubusercontent.com/dominant-strategies/go-quai/main/core/headerchain.go
- [gq-pkg] https://api.github.com/repos/dominant-strategies/go-quai/contents/consensus/progpow
- [rvn-hpp] https://github.com/RavenProject/Ravencoin/blob/master/src/crypto/ethash/include/ethash/progpow.hpp
- [rvn-pp] https://github.com/RavenProject/Ravencoin/blob/master/src/crypto/ethash/lib/ethash/progpow.cpp
- [rvn-eth] https://github.com/RavenProject/Ravencoin/blob/master/src/crypto/ethash/lib/ethash/ethash.cpp
- [rvn-ethh] https://github.com/RavenProject/Ravencoin/blob/master/src/crypto/ethash/include/ethash/ethash.h
- [rvn-kf] https://github.com/RavenProject/Ravencoin/blob/master/src/crypto/ethash/lib/keccak/keccakf800.c
- [rvn-bit] https://github.com/RavenProject/Ravencoin/blob/master/src/crypto/ethash/lib/ethash/bit_manipulation.h
- [rvn-kiss] https://github.com/RavenProject/Ravencoin/blob/master/src/crypto/ethash/lib/ethash/kiss99.hpp
- [rvn-tst] https://github.com/RavenProject/Ravencoin/blob/master/src/test/kawpow_tests.cpp and https://github.com/RavenProject/Ravencoin/blob/master/src/crypto/ethash/progpow_test_vectors.hpp
- [ck] https://github.com/RavenCommunity/cpp-kawpow
- [ck-vec] https://raw.githubusercontent.com/RavenCommunity/cpp-kawpow/master/test/unittests/progpow_test_vectors.hpp
- [ck-tpp] https://github.com/RavenCommunity/cpp-kawpow/blob/master/test/unittests/test_progpow.cpp
- [ck-eth] https://github.com/RavenCommunity/cpp-kawpow/blob/master/test/unittests/test_ethash.cpp
- [ck-src] https://github.com/RavenCommunity/cpp-kawpow/blob/master/include/ethash/progpow.hpp , https://github.com/RavenCommunity/cpp-kawpow/blob/master/include/ethash/ethash.h , https://github.com/RavenCommunity/cpp-kawpow/blob/master/lib/ethash/progpow.cpp
- [chfast] https://raw.githubusercontent.com/chfast/ethash/v0.5.2/test/unittests/progpow_test_vectors.hpp
- [pp-spec] https://github.com/ifdefelse/ProgPOW/blob/master/README.md
- [kpm] https://github.com/RavenCommunity/kawpowminer
- [kpm-h] https://github.com/RavenCommunity/kawpowminer/blob/master/libprogpow/ProgPow.h
- [kpm-cpp] https://github.com/RavenCommunity/kawpowminer/blob/master/libprogpow/ProgPow.cpp
- [kpm-cu] https://github.com/RavenCommunity/kawpowminer/blob/master/libethash-cuda/CUDAMiner_kernel.cu
- [kpm-es] https://raw.githubusercontent.com/RavenCommunity/kawpowminer/master/libpoolprotocols/stratum/EthStratumClient.cpp
- [kpm-uri] https://raw.githubusercontent.com/RavenCommunity/kawpowminer/master/libpoolprotocols/PoolURI.cpp
- [kpm-tst] https://github.com/RavenCommunity/kawpowminer/blob/master/test/kernel.cu and https://github.com/RavenCommunity/kawpowminer/blob/master/test/result.log
- [kral] https://github.com/kralverde/ravencoin-stratum-proxy and https://github.com/kralverde/ravencoin-stratum-proxy/blob/master/stratum-converter.py
- [ksp-st] https://raw.githubusercontent.com/RavenCommunity/kawpow-stratum-pool/master/lib/stratum.js
- [ksp-jm] https://raw.githubusercontent.com/RavenCommunity/kawpow-stratum-pool/master/lib/jobManager.js
- [ksp-bt] https://raw.githubusercontent.com/RavenCommunity/kawpow-stratum-pool/master/lib/blockTemplate.js
- [kpss] https://github.com/hans-schmidt/kawpow_personal_stratum_server
- [mp-ref] https://github.com/MintPond/ref-stratum-ravencoin
- [mp-h] https://github.com/MintPond/hasher-kawpow and https://github.com/MintPond/hasher-kawpow/blob/master/test.js
- [kx-h] https://github.com/kryptex/hasher-kawpow
- [trex] https://github.com/trexminer/T-Rex
- [lol] https://github.com/Lolliedieb/lolMiner-releases and https://github.com/Lolliedieb/lolMiner-releases/issues/1750
- [mc] https://github.com/oliverw/miningcore , https://raw.githubusercontent.com/oliverw/miningcore/master/src/Miningcore/coins.json , https://github.com/oliverw/miningcore/discussions/1334
- [gh-search] https://api.github.com/search/repositories?q=kawpow+stratum