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
- 2026-08-12 late night: **GitHub repo created** (private):
  github.com/zengjiajun0623/everett, clean two-commit history, build tree
  excluded. G6 scoping memo committed (go-quai progpow port base verified,
  differential-vector gate design).
- 2026-08-13 early: **Article III.5 live-verified.** burn_audit.py upgraded
  to uncle-aware accounting; two-miner devnet; tip-fork via
  removePeer/addPeer produced an uncle on cycle 1; both miners' balances
  modeled exactly (deltas 0) at 286 blocks including the R/32 uncle reward
  and R/32 inclusion bonus. Every constitutional article with observable
  behavior is now live-verified.
- 2026-08-13 early: **turnkey path hardened** for "run it locally": boot
  script now scripts the modern-Go compat fixes (blst bump, memsize
  excision) so a fresh clone builds; chain persists across restarts
  (RESET=1 wipes); ETHERBASE/THREADS env vars; README quickstart added.
  Fresh-clone reproducibility gate: full pipeline from a deleted build
  tree, result logged in the entry below.
- 2026-08-13: **Wheeler testnet live** (chain ID 15537392, distinct genesis
  753626..169c4d via tagged extraData). Family hooks (isEverettFamily) give
  Wheeler identical consensus rules; audit passes under the testnet ID.
  Parametrized dist tooling (NET=wheeler|everett make_dist.sh); Wheeler
  package sim-verified (synced to head via bootnode discovery). Bootnode
  currently LAN; Tailscale installed, awaiting login: then rebake with
  `NET=wheeler BOOTNODE=enode://<key>@<ts-ip>:30303 scripts/make_dist.sh`
  (key in dist/wheeler-bootnode.txt). Mainnet chain ID 15537393 reserved
  for the Art. VIII ceremony: never start it casually.
- 2026-08-13: **Wheeler went public.** Repo public. Bootnode reachable on
  the open internet at 71.183.54.11:30303 via NAT-PMP mappings (router
  granted them programmatically; UPnP was off, NAT-PMP on). External
  reachability verified from three continents (check-host.net). Renewal
  loop: scripts/nat_renew.sh (hourly PMP leases, nohup'd on the bootnode
  Mac; restart it after reboots). Package rebaked with the public enode;
  README carries permissionless join instructions. Tailscale path retired
  (kept as fallback). Jiajun mining to his own EOA (0xf3F5...CBA2).
- 2026-08-13: **Two-miner network.** Second real node on pc3080 (WSL2,
  distro sp1; the old Ubuntu distro was a vhdx-less corpse, unregistered).
  Lesson encoded in scripts/join_wheeler_wsl.sh: WSL kills background VMs
  when the launching session exits, so the node runs via a Windows
  scheduled task (WheelerNode) executing geth in the foreground. First
  PC-mined block: 970 (etherbase 0x2E0fA0...91f7). Full supply audit exact
  across three accounts at 972 blocks. Fun fact: the M-series Mac mini
  out-hashes the desktop CPU at ethash (memory bandwidth) 27:3 over the
  last 30 blocks. Also observed: foreign nodes (mainnet geth, Polygon bor)
  discovering us via the shared discv4 DHT and bouncing off the
  networkid/genesis handshake, as designed.
- Next: Justin's node (package sent; persistent watcher armed for the
  first external peer); G6 KawPow port; VPS bootnode; block explorer;
  pre-v1.0 trademark sweep.

## CI gates (GitHub Actions, .github/workflows/ci.yml)

Three jobs run on every push and PR:

1. **consensus unit gates** — Article III schedule vectors, ASERT vectors
   (including the batch-sync determinism regression), and the KawPow
   differential vectors against Ravencoin's reference values.
2. **constitution vs implementation** — `scripts/check_consistency.py`
   asserts the monetary parameters appear identically in CONSTITUTION.md,
   GENESIS_SPEC.md, the Go client, and both Python auditors, and that the
   two independent reward implementations agree wei-for-wei over a sweep
   including every boundary (0, 1, slow-start edges, era edges, deep tail).
   This exists because the 55-agent audit found exactly that drift.
3. **devnet end-to-end** — builds, mines a real chain, asserts the genesis
   hash and empty state root are unchanged, then runs the full supply audit.

Every gate has been negative-controlled: mutating KawPow's period (3→4) or
the constitution's decay constant (993→990) makes the corresponding job
fail, so a green run means something.

## 2026-08-13 (overnight): G6 KawPow, end to end

- **P1** research fleet produced G6_P1_NOTES.md (117 sourced facts): the
  complete ProgPoW→KawPow diff, the 13 Ravencoin reference vectors, and
  the stratum dialect spec.
- **P2 bit-exact.** `client/kawpow_core.go` reproduces Ravencoin's vectors
  exactly: size schedule, epoch seeds, epoch-0 cDag, smoke vector, and the
  primary hash vectors across period and epoch boundaries. Two bugs the
  vectors caught: KawPow needs its own seedHash (core-geth's assumes
  30000-block ethash epochs) and its own DAG schedule (1 GiB init, 8 MiB
  growth, 512 parents). Negative-controlled (period 3→4 fails the suite).
- **P3** engine wiring: light verification (the node never builds a DAG),
  full-DAG node-side mining fallback, and the work-API seed-hash fix.
  Gated on EVERETT_KAWPOW; chain-config activation still owed before any
  public network flips (GENESIS_SPEC 5a.5).
- **P4** isolated devnet (chain ID 15537391, genesis-dev.json): first
  KawPow block sealed in 3m13s on CPU, verified through the light path
  while mined through the full path, supply audit wei-exact.
- **P5 GPU: DONE, thesis demonstrated.** Stock kawpowminer 1.2.4 on an
  RTX 3080 drove the chain 11 → 264 with no custom software. Two gotchas
  cost an hour and are now documented in GPU_MINING.md: the address must
  appear in the getwork URL or the client silently never submits, and
  --http.vhosts must allow the miner's Host header. ASERT absorbed the
  ~10,000x hashrate arrival smoothly (131,072 → 416,624 over 264 blocks),
  matching the simulation. 66 uncles, all paid per Art. III.5, audit exact.
- **CI added** (.github/workflows/ci.yml), green on GitHub: consensus unit
  gates, a constitution-vs-implementation consistency gate born from the
  audit's drift findings, and a devnet e2e job. All negative-controlled.
- **Windows lesson, twice:** Windows tears down child processes when the
  launching session exits. Both the WSL node and the GPU miner need
  scheduled tasks (`WheelerNode`, `EverettGpuSoak`).

## 2026-08-13 (late): stratum sidecar — written, built, NOT yet run live

Written to fix the getwork churn (936 mining suspensions, production
stalling near difficulty 4M):

- `stratum/kawpow-stratum.go` (~300 lines) implements the KawPow stratum
  dialect from G6_P1_NOTES.md §4.2. Consensus-free by design: the node
  verifies every submit (light KawPow path), the sidecar only translates
  transports and tracks jobs. **Compiles clean.**
- `stratum/kawpow-stratum_test.go`: round-trip test for the compact-bits
  encoder (kawpowminer parses `bits` with SetCompact) plus hex handling.
- `stratum/README.md`: protocol table, run instructions, and the one open
  question — whether kawpowminer negotiates plain mode or NiceHash mode
  from a `stratum://` URL. If NiceHash, `handle` needs a mode branch.
- `scripts/run_stratum.sh` to build+run; `scripts/ship_stratum_e2e.sh` runs
  the whole proof in ONE shell invocation (build, unit test, launch,
  raw-client protocol smoke test, GPU miner via scheduled task, N minutes
  of sampling, metrics vs the getwork baseline, cleanup, and a written
  report at build/STRATUM_E2E_REPORT.md).

Three bugs found and fixed in review before any run:
1. `json.Encoder` used concurrently by the job broadcaster and the submit
   handler — frames could interleave. Added a per-client write mutex.
2. Fragile `fmt.Sscanf("%x")` parsing of target/height — replaced with
   `big.Int.SetString` and `strconv.ParseUint`.
3. Job broadcast held the global lock during network writes, so one slow
   miner stalled job propagation to all. Now snapshots under the lock and
   sends outside it.

Also fixed in the engine: `kawpowFullFor` built the 1 GB mining DAG while
holding `kpMu`, the same mutex verification uses, so a mining node would
freeze block verification for minutes. Now uses its own `kpDatasetMu`; the
two locks are never held simultaneously (no deadlock cycle). Compiles.

**BLOCKED, not broken:** the live run needs shell execution, and the
session's safety classifier stopped servicing anything beyond trivial
commands (known long-transcript failure; the fix is `/compact`, which only
the user can run). Everything above is on disk and uncommitted.

**To finish (one command after `/compact` or in a fresh session):**

```bash
bash ~/everett/scripts/ship_stratum_e2e.sh
```

## 2026-08-13 (day): PR #1 merged — Docker/Portainer packaging (Justin), plus hardening follow-up

First external contribution. Justin (MidnightOnMars) shipped a Docker +
Portainer stack: node image that builds core-geth + Everett patches from
source WITH the verification gates in the build (a failing gate fails the
image), an ethminer v0.19.0 CUDA image for GPU mining over getwork, compose
stack, and a full GUI walkthrough. His build evidence (RTX 3090): both
images from scratch, 12/12 gates in-build, wei-exact verify_devnet.sh from
host AND in-container, plus a live Wheeler join. Corroborated on our side:
the "mystery" external peer from last night mines to the compose stack's
default throwaway etherbase 0x1000…0001 — it was Justin's stack, and
burn_audit.py shows its rewards wei-exact (4,558 blocks, 226 uncles,
3 miners, delta=0 for all three).

Review: 4-lens adversarial workflow (supply-chain, consensus-consistency,
docker mechanics, docs) + CI on the PR branch (approved first-contributor
run; all 3 jobs green). No consensus files touched; Hunter's Boost URL
repoint preserves SHA1 verification; RPC host-published to localhost only.
Merged as 37005ee (merge commit, authorship preserved).

Confirmed findings → fixed in follow-up commit on main:
1. Devnet default was legacy genesis-devnet.json = chain ID 15537393, the
   RESERVED mainnet ID (replay hygiene). Now defaults to genesis-dev.json
   (15537391) everywhere; legacy file ships for compat, marked as such.
2. Image replicated superseded boot_devnet.sh prep — no KawPow. Now mirrors
   ci_prepare.sh: kawpow files + hooks + TestKawPow gate in the build.
3. core-geth clone unpinned (consensus binary from moving HEAD). Now pinned
   via COREGETH_COMMIT=10f1ea74… (the gate-verified tree); build-arg
   overridable. Fetch-by-SHA verified against GitHub.
4. --http.vhosts '*' reopened the DNS-rebinding hole; now
   node,localhost,127.0.0.1 (HTTP_VHOSTS env to extend).
5. Docs: env table conflated compose defaults with image defaults; fake
   `docker compose exec node eth_getWork` command → curl; missing -f flags;
   Ubuntu 24.04 apt package is docker-compose-v2 (not docker-compose-plugin);
   chain-ID copy throughout; getwork-churn transport note pointing at
   stratum/. Also fixed OUR stale verify_devnet.sh echo that still taught
   0xed14f1 as the devnet chainId.

Refuted (no action): "unpinned = dishonest pinned-versions table" (table
was explicit about it), "miner URL needs 0xaddress@" (kawpowminer-only
quirk; ethminer getwork credits the node's etherbase — proven by the live
Wheeler balances).
