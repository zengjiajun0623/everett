# Everett Runbook

## Goal ladder (auto-adjusted; log below)

- **G1:** devnet boots genesis-devnet.json, mines, passes verify_devnet.sh. ✅ 2026-08-12
- **G2:** reward patch grounded in real core-geth source, unit-tested. ✅ live wei-exact
- **G3:** DAA decision. ✅ v2: ASERT (v1 LWMA split consensus, superseded)
- **G4:** two-node trustless sync from genesis + independent audit. ✅
- **G5:** Article IV burn proven on-chain. ✅ 147,000 wei destroyed, 3 accounts exact
- **G6:** KawPow Go port (launch algorithm). ✅ chain-keyed, GPU-proven, live on Wheeler v2 from genesis

## Verification loop (three independent gates)

1. **Go unit tests** (`client/rewards_everett_test.go` into
   `params/mutations/`, `client/difficulty_everett_test.go` +
   `client/asert_enum_test.go` + `client/kawpow_core_test.go` into
   `consensus/ethash/`, copied there by `scripts/ci_prepare.sh`): exact wei
   vectors for D(0..2), half-life neighborhood at era 98, slow-start
   midpoint, tail floor at era 5000, uncle split, the ASERT vectors and
   exhaustive enumeration, and the KawPow differential vectors. All three
   suites run inside `boot_devnet.sh` before build; build aborts on failure.
   They run through `scripts/gate_test.sh`, which additionally fails when a
   `-run` pattern matches no tests, so a file missing from the prep recipe
   cannot show up as a green gate.
2. **Live reward audit** (`scripts/verify_devnet.sh`): asserts you are
   auditing the chain you meant to (`EXPECT_CHAINID`), asserts
   London-at-genesis and the absence of beacon-era fields, then runs
   `scripts/burn_audit.py`, which recomputes the entire schedule in Python
   (independent implementation) plus uncles and the 1559 burn, and demands
   every directly-modeled account match its RPC balance wei-for-wei
   (contract-touched accounts are named and skipped, never silently
   claimed). Stock core-geth pays flat 2/block and fails instantly, so the
   gate cannot pass vacuously. `scripts/ci_devnet.sh` runs this operator
   script itself, not merely its audit step.
3. **Cross-language agreement:** gates 1 and 2 implement Article III twice
   from the text alone. Divergence in either direction is a spec ambiguity;
   fix the constitution's wording, not just the code.

`scripts/verify_rewards.py` is NOT one of these gates and nothing invokes
it. It is a standalone strict single-miner checker (schedule recomputed in
Python, genesis pinned via `EXPECT_GENESIS`) kept for manual use, and it
fails by design on any multi-miner chain. The consistency gate reads its
source for the Article III constants, so CI keeps its parameters from
drifting without ever executing it. What actually runs on every push is the
five-job list under CI gates below.

## How to run

```bash
scripts/boot_devnet.sh        # clone, patch, test, build, init, mine (RPC :8547)
RPC=http://127.0.0.1:8547 scripts/verify_devnet.sh   # in a second shell
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

Five jobs run on every push and PR:

1. **consensus unit gates**: Article III schedule vectors, ASERT vectors
   (including the batch-sync determinism regression), and the KawPow
   differential vectors against Ravencoin's reference values. Each runs
   through `scripts/gate_test.sh`, which fails unless a stated minimum
   number of tests actually PASSED: `go test -run` exits 0 with "no tests to
   run" when the pattern matches nothing, and every gate here selects tests
   by name from files copied into the tree by the prep recipe.
2. **constitution vs implementation**: `scripts/check_consistency.py`
   asserts the monetary parameters appear identically in CONSTITUTION.md,
   GENESIS_SPEC.md, the Go client, and both Python auditors, then sweeps
   the constitution's reward formula against a Python transcription of
   the Go client's control flow, wei-for-wei over every boundary (0, 1,
   slow-start edges, era edges, deep tail). The Go binary itself is not
   executed here (its constants are pattern-checked; its behavior is
   exercised by the consensus unit gates and the live audits).
   This exists because the 55-agent audit found exactly that drift.
3. **stratum sidecar gates**: `go vet` plus the sidecar unit tests under
   the race detector, so the production mining transport no longer ships
   untested.
4. **devnet end-to-end**: builds, mines a real chain, asserts the genesis
   hash and empty state root are unchanged, then runs the full supply audit.
5. **formal verification**: builds the Lean 4 proofs (`fv/`, `lake build`
   under the pinned elan toolchain) and greps the whole `fv/` tree
   (`grep -rn --include='*.lean'`) for `sorry`, so the machine-checked
   Article III claims gate every push too. The glob used to be `fv/*.lean`,
   which stops at the top level: a proof file in a subdirectory could have
   carried a `sorry` while the job reported success.

Negative controls, honestly scoped, job by job. The blanket form of this
claim ("All negative-controlled", the 2026-08-13 entry below) was written
when the CI had three jobs and one of those three never had a control at
all, so the enumeration is the only honest form. Three of the five jobs have
a mutation on record that turns them red:

- **1, consensus unit gates**: KawPow's period 3→4 fails `TestKawPow`.
- **2, constitution vs implementation**: the constitution's decay constant
  993→990 fails the sweep, and since 035d9ea an era off-by-one fails it at
  blocks 99,999 and 199,999. That second control only exists because the
  job's "two independent implementations" turned out to be one implementation
  twice, so until then the sweep could not disagree with itself.
- **3, stratum sidecar gates**: reverting the worker-name capture in
  `submit()` makes `TestProtocolConcurrent` fail under `-race`. That is the
  data race which had already shipped through this very job while it ran the
  detector over tests that never started the server. Recorded in the test's
  own header comment, re-verified in dc404fc and ed5a046 (4,563 and 4,613
  forward-path executions per run).

The other two have NOTHING on record. **4, devnet end-to-end** and **5,
formal verification** have never been shown to go red on a real regression,
so read a green run there as "the checks passed", not as "the checks were
shown able to fail". The e2e job is the one to watch, because it looks like
the strongest gate in the set (it mines a real chain and audits supply
wei-exact) and so gets credited by association: none of the three recorded
mutations reaches it, and the constitution-text one cannot, since `ci_devnet.sh`
recomputes the expected supply from `burn_audit.py`'s own constants and never
reads CONSTITUTION.md. The missing controls would be, e.g., flipping the Go
client's tail constant so the audit's delta goes non-zero, and flipping a
constant in `fv/` to show `lake build` fails.

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
  audit's drift findings, and a devnet e2e job. "All negative-controlled" is
  what this entry said, and it was too broad: the consensus and consistency
  gates each have a recorded mutation, the e2e job never did. Scoped job by
  job in the CI gates section above.
- **Windows lesson, twice:** Windows tears down child processes when the
  launching session exits. Both the WSL node and the GPU miner need
  scheduled tasks (`WheelerNode`, `EverettGpuSoak`).

## 2026-08-13 (late): stratum sidecar written and built, NOT yet run live

Written to fix the getwork churn (936 mining suspensions, production
stalling near difficulty 4M):

- `stratum/kawpow-stratum.go` (~300 lines) implements the KawPow stratum
  dialect from G6_P1_NOTES.md §4.2. Consensus-free by design: the node
  verifies every submit (light KawPow path), the sidecar only translates
  transports and tracks jobs. **Compiles clean.**
- `stratum/kawpow-stratum_test.go`: round-trip test for the compact-bits
  encoder (kawpowminer parses `bits` with SetCompact) plus hex handling.
- `stratum/README.md`: protocol table, run instructions, and the one open
  question: whether kawpowminer negotiates plain mode or NiceHash mode
  from a `stratum://` URL. If NiceHash, `handle` needs a mode branch.
- `scripts/run_stratum.sh` to build+run; `scripts/ship_stratum_e2e.sh` runs
  the whole proof in ONE shell invocation (build, unit test, launch,
  raw-client protocol smoke test, GPU miner via scheduled task, N minutes
  of sampling, metrics vs the getwork baseline, cleanup, and a written
  report at build/STRATUM_E2E_REPORT.md).

Three bugs found and fixed in review before any run:
1. `json.Encoder` used concurrently by the job broadcaster and the submit
   handler, so frames could interleave. Added a per-client write mutex.
2. Fragile `fmt.Sscanf("%x")` parsing of target/height, replaced with
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

## 2026-08-13 (day): PR #1 merged (Docker/Portainer packaging, Justin), plus hardening follow-up

First external contribution. Justin (MidnightOnMars) shipped a Docker +
Portainer stack: node image that builds core-geth + Everett patches from
source WITH the verification gates in the build (a failing gate fails the
image), an ethminer v0.19.0 CUDA image for GPU mining over getwork, compose
stack, and a full GUI walkthrough. His build evidence (RTX 3090): both
images from scratch, 12/12 gates in-build, wei-exact verify_devnet.sh from
host AND in-container, plus a live Wheeler join. Corroborated on our side:
the "mystery" external peer from last night mines to the compose stack's
default throwaway etherbase 0x1000…0001: it was Justin's stack, and
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
2. Image replicated superseded boot_devnet.sh prep (no KawPow). Now mirrors
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
quirk; ethminer getwork credits the node's etherbase, proven by the live
Wheeler balances).

## 2026-08-13 (afternoon): stratum sidecar LIVE-PROVEN, six-run debugging campaign

The one-command e2e (`scripts/ship_stratum_e2e.sh`) is green: RTX 3080
mining an Everett KawPow devnet through the sidecar, ~1,000+ blocks in
12 minutes, ASERT climbing 131k → 6.4M+ on its textbook exponential
(doubling per minute of fast blocks). Report: build/STRATUM_E2E_REPORT.md.
This entry also claimed "zero disconnects", which is withdrawn: that run's own
log tail records a miner disconnect at 14:27:15 (stratum/E2E_REPORT.md), and the
miner-derived columns of that report were instrument error. The block count
and the difficulty progression above came from the node and the sidecar's own
log, so they stand; for a run where every number has a stated source, see the
re-verified table added in fdb4788.

Getting there took six live runs, each buying one real lesson (all now
encoded in code comments, stratum/README.md, and the e2e script):

1. **URL scheme**: bare `stratum://` autodetects EthereumStratum/2.0.0 →
   NiceHash → Eth-Proxy and never tries mode 0; the miner then hashes and
   wastes every solution. `stratum+tcp://` forces the dialect we speak.
2. **schtasks lifecycle**: /run on a still-Running instance is a silent
   no-op; a sleep-wrapper keeps instances alive after the miner dies, and
   /create /f orphans them beyond /end. The task now runs a batch file
   whose process tree IS the miner; the e2e fail-fasts if no miner
   process exists 15s after launch.
3. **Windows quoting**: an inline /tr "cmd /c ... 2^>file" passes a junk
   argument instead of redirecting (caret is literal inside the quoted
   ssh string); the death logs went nowhere for two runs.
4. **The node stalls submitWork for seconds** after a block burst; one
   synchronous forward in the reply path froze all acks past
   kawpowminer's 2-second watchdog. Sidecar now acks instantly, forwards
   async (≤4 in flight, 8s timeout), and never waits on the node.
5. **kawpowminer crashes (0xC0000005) on disconnect-while-hashing**: the
   watchdog disconnect wasn't graceful degradation, it was fatal.
6. **The kernel's search boundary is notify `bits`, not set_target**:
   the decisive finding. With block bits in the job, the GPU hunted at
   131k while displaying the 8M share target: 1,639 solutions in 7s,
   watchdog, crash. bits now encodes the share target; -sharediff
   (default 8M) is mandatory vardiff, not tuning.

Also fixed en route: `{"id":N}` responses with a false result dropped by
json omitempty (rejected shares got a malformed reply); a unit test that
asserted impossible top-24-bit fidelity for sign-bit compact mantissas;
the e2e silently ignoring unit-test failures.

Wheeler note: the getwork transport limitation documented in
GPU_MINING.md stands; the sidecar is now the proven mining path for the
KawPow era. It should ship in the Docker stack as a third service before
the Wheeler flip.

## 2026-08-13 (evening): WHEELER V2, the KawPow flip, executed

Jiajun's call: "flip wheeler to kawpow and let justin know." Done end to
end in one session (commit 9e1181f, CI green):

- **Chain-keyed activation** (GENESIS_SPEC 5a.5 CLOSED): new hook 5 in
  apply_kawpow_hooks.py inserts `ethash.SetKawPowChainID(chainID)` into
  eth/backend.go once the chain config loads. Wheeler + mainnet = KawPow
  from genesis; dev chain keeps EVERETT_KAWPOW env choice; all other
  chain IDs forced off. Unit-tested (TestKawPowActivation). The env-var
  era is over: consensus never depends on local environment.
- **Re-genesis**: genesis-wheeler.json v2, extraData "EVERETT WHEELER V2
  KAWPOW", genesis 0xabd9bac321cc9176f1a540d8cab9bea6ce27a4621aeb6199642891141d5e8934,
  chain ID unchanged (15537392). v1 (ethash, ~4.6k blocks) retired.
- **Bootnode identity preserved**: nodekey copied out before the datadir
  wipe and restored, so the published enode ad614b8c…@71.183.54.11:30303
  remains valid, Justin reconfigures nothing.
- **Mac node**: --mine --miner.threads 0 (believed at the time to serve
  work only; round 4 established that core-geth reads 0 as "use every
  core" and disables local mining only on a negative value, so this node
  was also CPU-mining KawPow for that period), etherbase
  Jiajun 0xf3F5…CBA2, kawpow-stratum on :3333 (log: build/stratum-wheeler.log),
  3080 mines via scheduled task WheelerGPU (mine_wheeler.cmd). First v2
  block mined 19s after the sidecar came up. Log line to look for:
  "Everett proof-of-work selected chainID=15,537,392 kawpow=true".
- **pc3080 WSL node**: join_wheeler_wsl.sh upgraded to ci_prepare parity
  (KawPow files + all 5 hooks + TestKawPow gate) and auto-migrates v1
  datadirs (genesis-hash check → wipe → re-init). Rebuilt, synced v2
  trustlessly from the LAN bootnode (public IP hairpin doesn't work from
  inside the LAN, so use 192.168.1.172 there; the sed + schtasks /end
  dance is in the session log). Sync/verify node; the PC's hashpower is
  its GPU via stratum.
- **Justin notified** on PR #1 (comment 5285009689): migration steps
  (pull, rebuild image, wipe volume, restart), the ethminer-can't-mine-v2
  warning, and the stratum recipe.

Devnet (:8555) and its sidecar retired; second local Wheeler node (30305)
retired. Old wheeler.log content is v1 history.

Addendum 2026-08-13: Mac mini CPU-mines Wheeler symbolically (2 threads,
~0.5% of network hashpower; --miner.threads 2 on the node). The 1 GiB
mining DAG built in 41s and, thanks to the kpDatasetMu lock split, block
verification never paused during the build. Dashboard tags block origin
by nonce prefix (gpu·stratum vs mac·cpu).

## 2026-08-13 (late): ops hardening + burn proof + launch-difficulty memo

Four-item sprint after the flip, all landed:
1. launchd agents (ops/launchd/, install.sh) for node/stratum/dashboard/
   nat-pmp, reboot-proof; migrated live without dropping the GPU miner.
2. kawpow-stratum shipped as a Docker compose service (stratum.Dockerfile);
   Justin notified (PR #1); his 3090 has a one-command mining path.
3. FIRST WHEELER TRANSACTION (block 1818, tx 0xda02e3b0…): Art IV burn
   live-verified: 147,000 wei provably destroyed, audit exact for every
   account including the throwaway's reward-minus-gas. Recipe: personal
   API via --rpc.enabledeprecatedpersonal (IPC only), rotate etherbase to
   throwaway for one block, rotate back, self-transfer.
4. LAUNCH_DIFFICULTY.md: mainnet genesis recommendation 0x40000000 from
   measured data; GENESIS_SPEC item 3 resolved (applied at v1.0 freeze).

Remaining before an Art VIII ceremony: VPS bootnode (Jiajun's account),
name/trademark sweep, ceremony logistics (T-30 publication, constitution
hash into genesis extraData, difficulty change at freeze).

## 2026-08-13 (night): formal verification tier (machine-checked constitution)

Jiajun's call: "shall we formally verify our implementation on the geth
client?" Scoped to our consensus delta (verifying geth wholesale is a
research program, and our risk lives in the delta anyway).

1. ASERT fixed-point layer: proven by COMPLETE ENUMERATION over its
   finite domain (client/asert_enum_test.go, runs inside the standard
   TestASERT gates, ~10ms). First run falsified my own assumed error
   bound: true max relative error 0.0105%, matching aserti3-2d's
   documented ~0.013%; monotonicity, factor range, floor all hold at
   every one of 131,073 exponents.
2. Article III in Lean 4 (fv/EverettSchedule.lean, core Lean only, zero
   sorries): decay envelope + strict decrease + zero-absorption; THE
   SUPPLY THEOREM via an era-budget invariant: base-reward issuance
   through any height ≤ 0.2 ETT·B + eraLen·d0·1000/7 wei (~25.71M ETT decay
   component, ~28.93M under the 9/8 uncle multiplier, both proven);
   decay dead at era 5360 → from block 536,000,000 every reward is
   EXACTLY 0.2 ETT (terminal state is a dated fact); rewards never rise
   post-slow-start. Eight native_decide anchors pin the model to the
   Go/Python vectors: three independent implementations, one
   machine-checked spec.
3. Kimi adversarial review (house gate) found 6 real findings: a
   summation gap, an undischarged premise, the uncle channel, a
   README ×100000 slip, two comment inaccuracies. ALL closed as
   theorems or corrections; review log in fv/README.md.
4. CI: formal-verification job (elan + lake build) gates every push.

KawPow needs no new apparatus: differential vectors vs the Ravencoin
reference in the gates, plus every live block is a cross-implementation
check (kawpowminer's full-DAG path vs our light verify).

## 2026-08-13 (midnight): full audit before the Vitalik send, 26 findings, all resolved

Jiajun: "should you run a complete review/audit to see if there's
anything break?" Six-lens adversarial workflow (41 agents) over the
day's commits + live-system sweep. Live systems: all green. Repo: 26
confirmed findings, 8 blockers, fixed in e0d9241 (full inventory in
that commit message). Highlights: the enumeration proofs ran NOWHERE
despite front-page claims (every prep copied every test file except the
new one); boot_devnet built a KawPow-free geth (prep now unified on
ci_prepare, "never fork the prep again"); two sidecar wedge bugs
(blocking writes under the global lock; deadlines + culling +
concurrent broadcasts now); a committed 8.6MB binary under the
"no prebuilt binaries" claim; hook 6 chain-keys `geth import`; a dozen
claims updated to match the code (incl. the stratum README recommending
the exact URL scheme its own dialect section proves broken). CI green
on all four jobs after; sidecar redeployed live, miner reconnected in
<1s. Lesson, again: the system was healthy; the CLAIMS had drifted.
Audit cadence should precede every external send.

Addendum (cross-model audit): Jiajun ran a DeepSeek version audit in
parallel. It independently REPRODUCED the build (identical binary
version string to the live peer banner), the genesis hash via geth's own
GenesisToBlock, and all gates (the strongest third-party confirmation
yet), and caught what our audit missed: only Docker was pinned;
ci_prepare.sh and the WSL join cloned unpinned HEAD. Fixed in 6e37670
(pin everywhere + drift assertion in the consistency gate) plus
SECURITY.md for the CVE posture. Three AI systems have now audited this
chain (Claude, Kimi, DeepSeek); each found something the others missed.
The AI-native review thesis, demonstrated on ourselves.

## 2026-08-14 (backfilled): hermetic gates, then audit round 1, 44 findings

The two entries below and this one were written on 2026-08-14, after the
fact. The trail above stopped at the midnight audit while three more commits
landed the same night, and SECURITY.md sends reviewers here for the full
audit record: a gap in this file is a false claim on the front door. Round 3
found it, so it is logged as a finding, not tidied away.

1. **e24cbdd, hermetic verification gates**, from the second DeepSeek
   re-audit and demonstrated on this host: the e2e devnet node died
   instantly on port collisions with the live Wheeler node (30303/8545/8551
   all defaults), the gate then polled the default 8545, the LIVE node
   answered, and the gate validated the wrong chain, since its only genesis
   assertion (empty state root) holds for every Everett chain. Fixed with
   dedicated ports, a process-liveness check on every poll, and chain
   identity (`eth_chainId` plus the exact genesis hash) in `ci_devnet.sh`;
   an `EXPECT_CHAINID` guard in `verify_devnet.sh` and optionally in
   `burn_audit.py`; and a pin assertion on an existing `build/core-geth`.
2. **d16b375, audit round 1: 44 adversarially confirmed findings** over nine
   lenses (shell, stratum, consensus Go, Python tooling, docker+CI,
   docs-vs-reality, Lean FV, live ops, hygiene), each reproduced by an
   independent verifier before the fix. The consensus one: `kawpow_core`
   computed the DAG-offset modulus and fetch indices in 32-bit, which wraps
   at a 16 GiB DAG (epoch 1921, roughly 5.9 years in) and would have split
   the node from every stock GPU miner; both are 64-bit now, with a
   regression test pinning cpp-kawpow semantics past the wrap point. Also:
   gates moved to `COREGETH_DIR=build/ci`, never the tree the launchd
   production node execs from; `ship_stratum_e2e.sh` made hermetic after the
   old version could kill the production sidecar and the GPU miner; stored
   XSS in the dashboard's peer and miner strings; an authorize/submit race
   and FIFO job eviction in the sidecar; the Art VIII runner guard keyed on
   chain-ID content rather than filename.

## 2026-08-14 (backfilled): audit round 2, 30 findings, the round about deployment

450a225. Round 2 attacked round 1's own fix commit, and its sharpest finding
was not code. **The live Wheeler node was still executing PRE-FIX consensus
code.** Round 1 had correctly moved the verification gates into an isolated
tree (`build/ci/core-geth`) so a gate could never disturb production, which
also severed the only path by which verified code reached the running node:
the 64-bit KawPow DAG fix was proven in a tree the node does not use, and a
green gate said nothing about the binary launchd execs. Deployment became an
explicit, verified act, `scripts/deploy_node.sh`: prep, build, assert the
binary matches the repo's consensus sources, restart, prove the chain
continues, audit. Production went onto the fixed binary that night; chain
continued 3965 to 3966, audit wei-exact.

Also in the round:
1. `verify_devnet.sh`'s new London check was a Python syntax error (a
   backslash inside an f-string expression) on every Python. It survived a
   full audit round because NO gate ran that script. `ci_devnet.sh` now runs
   the operator script itself, so the flow every joiner is told to run is
   covered by the e2e gate.
2. `ship_stratum_e2e.sh`'s over-escaped PowerShell made every pc3080 metric
   read 0 or empty, i.e. the report fabricated the ideal result (4,015 real
   accepted shares recorded as 0). The harness now proves its own devnet and
   algorithm, computes a hashrate it can defend, and FAILS on zero blocks or
   zero accepted shares. The committed artifact from the broken run carries
   a dated correction notice (`stratum/E2E_REPORT.md`) rather than a quiet
   deletion of the numbers.
3. Article VIII had no guard on the distribution channel: `NET=everett`
   produced a tarball that started the reserved mainnet unconditionally. The
   dist runner and `make_dist.sh` now carry the same ceremony guard as the
   docker runner, and `make_dist.sh` refuses to package an unpinned,
   unpatched, or stale binary.
4. The same uint32 wrap class as round 1, this time in
   `kawpowGenerateDataset`'s word offset.

## 2026-08-14: audit round 3, 25 findings, 1 critical

Run against 450a225, which is round 2's own fix commit. The critical finding
is round 2's shape one level up: **`deploy_node.sh` could report "OK ... on
the new binary" while the OLD process kept running.** `launchctl unload` and
`launchctl load` exit 0 even when they do nothing (the round reproduced this
against a nonexistent plist path: both print "failed: 5: Input/output error"
and return 0), so `set -euo pipefail` never fires, and the script's only
evidence of success was the chain height advancing, which a still-running
old node produces perfectly. The script now proves process identity: the
geth pid must have changed, and the sha256 of the binary the new pid is
executing must equal the sha256 of the binary just built.

Three more from the same family:
1. The name-selected Go gates could pass vacuously. `go test -run X` exits 0
   with "ok ... [no tests to run]" when the pattern matches nothing, and
   every consensus gate selects tests by name from files the prep recipe
   copies into the tree, so a missed copy or a rename reads as green (the
   midnight audit had already hit exactly that: the ASERT enumeration tests
   were in no prep recipe at all and the gates stayed green).
   `scripts/gate_test.sh` now wraps all three CI gates and the same three in
   `boot_devnet.sh`, and fails unless a stated minimum number of tests
   actually PASSED.
2. The Lean sorry-gate globbed `fv/*.lean`, which stops at the top level: a
   proof file in a subdirectory could carry a `sorry` with the job still
   green. It greps the tree now.
3. `apply_kawpow_hooks.py` was idempotent by MARKER, not by content: once a
   marker was present the hook was skipped, so an edited hook body could
   never reach an existing tree. Not theoretical. The production core-geth
   tree was found carrying a stale hook body (a comment line, so no
   consensus impact), which is exactly the drift the new `--verify` mode
   detects; both trees verify current again.

The standing lesson, and the thread through all three rounds: a verification
step must measure something only success can produce. A height that
advances, an exit status of 0, a marker that exists, a green `go test` with
no tests in it, a metric read from a path that does not exist: each of those
is equally satisfied by the failure it was supposed to catch.

## 2026-08-14 (backfilled): the eight commits after round 3, 15 findings

Round 3's fix commit landed at 00:24 and the night did not stop there. Five
more cross-model passes ran between 00:30 and 01:38, DeepSeek three and Kimi
two, first over round 2's commit and then over each fixed tip as it landed.
Backfilled on the same reasoning as the entry above: SECURITY.md sends
reviewers to this file for the full audit record, so a log that stops at the
last tidy round is a false claim on the front door. Commit by commit, in the
order they landed.

1. **035d9ea, DeepSeek cross-model audit (isolated clone, read-only), 3
   findings.** Round 3 had made `apply_kawpow_hooks.py` idempotent by CONTENT
   and left its two siblings idempotent by MARKER, so an edited reward or DAA
   hook body could never reach an existing tree while `deploy_node.sh`
   reported the binary was built from the current patch set: the round-3
   finding surviving in the two files the round-3 fix did not touch.
   `apply_hook.py` and `apply_daa_hook.py` compare the inserted TEXT now and
   carry `--verify`, and deploy runs all three instead of grepping for an
   identifier. Second: `boot_devnet.sh`, the README's headline command, bound
   the PRODUCTION ports (30303/8545/8551), so on an operator host it either
   died on "address already in use" or, with production briefly down,
   squatted the ports and held the live node in a launchd crash loop. It is
   30306/8547/8554 now, env-overridable. Third: `check_consistency.py`'s "two
   independent reward implementations" were the same five lines with the
   operands reordered, so the wei-for-wei sweep could not disagree with
   itself and a shared misreading of Article III would stay green. The second
   model is derived a different way now, cumulative issuance differenced
   across two heights. Writing it surfaced a fact worth keeping: the schedule
   floors once PER ERA, so a closed-form D0*993^k/1000^k with a single final
   floor is a DIFFERENT schedule and diverges from era 10. The per-era
   convention is the law, and the model applies it explicitly.
2. **ab6514c, the new race gate's first outing, and it caught its own
   author.** The concurrency test added in round 3 to make the "vet + race
   tests" job mean what its name says was itself racy, and CI found it on the
   first run: the deferred restore of the `-node` flag ran while forward
   goroutines spawned by `submit()` were still reading it inside `nodeCall`.
   Test-harness only (`nodeURL` is written once by `flag.Parse` at startup),
   but a flaky gate is worse than no gate. The restore drains first now,
   acquiring every `forwardSlot` to prove no forward is in flight, since
   `submit()` holds a slot for the whole call. Deterministic, not a sleep;
   five uncached `-race` runs at `-cpu=1,2,8`.
3. **dd45357, `verify_devnet.sh`'s guard variables were not exported.** `RPC`
   and `EXPECT_CHAINID` were plain assignments, so a bare run passed neither
   to the `burn_audit.py` it invokes and the audit fell back to its own
   defaults instead of inheriting the chain guard the script had just
   checked. Harmless where they are set in the environment (CI, an explicit
   prefix), wrong in the one path a first-time operator takes. Surfaced while
   reading Kimi's review notes on the invocation chain. Also confirmed that
   round: a fresh clone of the published repo builds and passes all three
   consensus gates (5/11/7 real tests, per `gate_test.sh`).
4. **dc404fc, Kimi cross-model audit, 2 findings** (of three; the third, no
   connection cap or read deadline on the stratum listener, was already
   closed at HEAD by round 3). The sidecar forwarded the miner-supplied
   header without checking it against the job's: a submit pairing job A with
   job B's header, both live inside the node's stale window, could be
   accepted for B while the sidecar marked A done, after which every later
   share for A, including a genuine block-winning nonce, would take the done
   early-ack and never reach the node. A block lost in silence while the
   miner is told "accepted". Rejected with a log line now; deployed and
   watched, zero rejections from the real kawpowminer. Second: the
   dashboard's `ThreadingHTTPServer` read request lines from blocking sockets
   with no timeout, so idle LAN connections pinned a thread and a descriptor
   each until the process ran out and stopped answering while still looking
   alive. Verified by attack: 60 silent connections, answers in 0.02s
   throughout, all 60 reaped after the timeout window. The header check also
   exposed that round 3's own test submitted a header not matching its job,
   which would have made the concurrency test a no-op under the new
   validation.
5. **5b97486, DeepSeek round 2: `MINER_THREADS=0` was mining on every core.**
   core-geth reads `--miner.threads 0` as "use every core" and disables local
   mining only on a NEGATIVE value (`consensus/ethash/sealer.go`: `if threads
   == 0 { threads = runtime.NumCPU() }`, then `if threads < 0 { threads = 0
   }`). `MINER_THREADS=0` is documented and shipped as the compose default to
   mean "serve work to the GPU miner, hash nothing", so the default docker
   stack was quietly CPU-mining KawPow on the whole box and building a ~1 GiB
   DAG in RAM, and `ship_stratum_e2e.sh`'s own node had the same intent and
   the same bug, i.e. every GPU-throughput number it measured was competing
   with an all-core CPU miner. The entrypoint translates 0 to -1 now. The
   live Wheeler node was never affected: its plist asks for 2 threads
   deliberately. Second: the dashboard's chain expectation was pinned to
   Wheeler, so the documented default invocation against any other chain
   (devnet today, mainnet on launch day, which LAUNCH_DIFFICULTY.md plans
   this dashboard to watch) showed a permanent red audit FAIL on a healthy
   node. It resolves from the node at startup now unless pinned explicitly,
   so the guard still catches a node changing identity underneath a running
   dashboard.
6. **fdb4788, the e2e report re-run so that every number in it is measured.**
   Leaving `stratum/E2E_REPORT.md` at "three of these numbers are instrument
   error" is a worse artifact than fixing it, so the rewritten harness was
   actually run and its results appended with the provenance stated per row:
   139 blocks in a 2-minute window, 169 accepted shares (the metric that
   previously always read 0), 11.3 MH/s computed from shares actually
   delivered, supply audit exact. Short window, and the GPU was shared with
   production Wheeler mining, so the rate is about half the card's solo
   figure; the point is that each number now has a source. The run doubles as
   live validation of the harness fixes from rounds 2 and 3: it booted its
   own devnet on dedicated ports, proved KawPow from the node's log rather
   than assuming it, ran both miners side by side on pc3080 (production
   :3333, the run :3334) with PID-scoped cleanup reaping only its own, and
   left zero processes behind.
7. **23c2efc, DeepSeek round 2 against the new tip, 2 findings.** Re-running
   the same reviewer on the fixed tree paid off: the miner-threads bug was in
   a THIRD runner. `dist/run-node.sh` passed `THREADS` straight through, so
   the shipped package's own documented flow (`MINE=1 THREADS=0`, "serve
   work, no CPU mining") CPU-mined KawPow on every core. The lesson recorded
   there: "fixed" means fixed in every runner, and only two of three had been
   swept. Second: the container inited only when chaindata was absent, with
   no check that the volume's chain matched `GENESIS`, so switching `GENESIS`
   on an existing volume, which is exactly how the README says to move a
   stack from devnet to Wheeler, served the OLD chain under the NEW
   `--networkid`: every handshake fails on the genesis mismatch and the node
   sits at zero peers on old blocks with no error while the operator believes
   they joined. The entrypoint records the chain at init and refuses a
   mismatch, probing once for volumes made by older images. Both verified
   with a stubbed geth that records its arguments.
8. **ed5a046, Kimi round 2, 6 findings, most of them defects in the same
   night's own hardening.** The stratum pre-auth deadline re-armed on EVERY
   received line, before parsing, so a socket dripping one junk byte a minute
   never expired, and 128 of them would fill the connection cap round 3 had
   just added and lock out every real miner: the new cap turned into the new
   denial of service. The unauthorized budget is absolute from connect time
   now. The dashboard carried the identical flaw, because Python's
   `settimeout()` bounds silence rather than the connection, so a client
   dripping a byte every 9 seconds held its thread indefinitely; a hard
   per-connection deadline closes the socket outright (25 dripping
   connections, all reaped, 0.02s answers throughout). `boot_devnet.sh` was a
   FOURTH runner passing `--miner.threads 0` through as "serve work only".
   The genesis-mismatch guard round 3 added to `boot_devnet.sh` failed OPEN:
   it required BOTH probes to succeed before refusing, so it skipped exactly
   when something was already wrong; either probe coming back empty is a
   refusal now. `make_dist.sh` never ran the hook verifications that
   `apply_kawpow_hooks`'s own docstring and this file both said it ran, and a
   hooks-only change leaves the pin and all four cmp'd files untouched, so
   the packager would have shipped a binary with stale injected consensus
   code while printing "packaged:"; all three verifies run before packaging
   now. And miner-controlled strings were logged unquoted, so a newline
   inside a jobID or header forged whole log lines, including fake
   `BLOCK: job ...` entries, which is the exact shape the e2e harness counts
   as blocks: every miner-supplied field is `%q`-quoted now, and malformed
   submits (bad nonce or mix shape) are rejected before the forward instead
   of being acked true and forwarded anyway.

What this campaign added to the standing lesson above. Every round after the
first found its defects in the PREVIOUS round's fixes: round 3's hook
hardening in the two appliers it skipped, round 3's connection cap in the
deadline that made it fillable, round 3's own new race test racing itself,
round 3's genesis guard in `boot_devnet.sh` failing open, and the same
core-geth `--miner.threads` semantic caught in a second, third, and fourth
runner across three separate commits. The recurring shape is the one
named above and it did not change: a guard that measures something the
failure also produces. A height that advances under an old binary, a marker
that exists next to a stale body, a cross-check whose second model was the
first one with its operands reordered, a socket timeout that bounds silence
instead of connection lifetime, a mismatch guard that skips when its own
probe fails. Two working rules came out of it: a fix is not landed until it
is landed in every runner that has the same intent, and a new guard is
itself unaudited code that belongs in the next round's scope.

## 2026-08-14: first external node joins; the GPU miner wedges silently

**Wheeler got its first independent participant.** 79.112.90.198 (Romania,
darwin-arm64) connected inbound running CoreGeth/v1.12.23-unstable-10f1ea74,
our exact pin, and synced from genesis to the chain tip (block 7,499, head
0x8669228b..., total difficulty 1,931,987,981,088) in about 90 seconds. It
is a verifier, not a miner: it independently checked every KawPow seal
without asking anyone's permission, which is the property the whole project
exists to demonstrate. Three earlier attempts that same night (Linode, and
two others) all ran STOCK builds, handshook, synced zero blocks and dropped,
because the genesis deliberately carries no custom fields: an unpatched
client cannot tell it is on a chain it cannot verify. The README now carries
a tested join recipe and, more usefully, the signature of that failure
(height stuck at 0x0 while peer count is non-zero).

**The same hour, the chain stalled for 27 minutes and nothing noticed.** The
GPU miner wedged: nvidia-smi showed 100% utilization and 190W, the TCP
session to the sidecar stayed ESTABLISHED, and zero shares arrived. The
sidecar behaved correctly throughout, holding job 00000b10 for height 7500
and waiting. Restarting the WheelerGPU scheduled task cleared it instantly
and blocks resumed within seconds.

Two lessons, both now fixed in code:

1. **Every monitor here watched correctness, not liveness.** burn_audit kept
   printing PASS, the gates stayed green, the dashboard rendered fine. A
   stalled chain is not an invalid chain, so a correctness monitor is blind
   to it by construction. scripts/liveness_watch.sh (launchd
   com.everett.liveness, every 60s) now alarms over iMessage when the head
   block is older than 300s or the RPC is unreachable, once per episode,
   with a recovery message. At the 13s target a 300s gap is ~23 missed
   blocks, so it fires on breakage, not variance.
2. **Stale log files cost most of the diagnosis time.** kawpowminer's live
   log is wheeler.err (written by mine_wheeler.cmd); the directory also held
   strat.err, strat2.err, soak.err, m2/m3/m4.err and miner.err from earlier
   sessions. strat.err looked current and plausible and was 22 hours stale,
   so it told a story about "block 2619" while the chain was at 7,499. The
   stale files are archived to kawpowminer/old-logs; only wheeler.err
   remains. A monitoring surface that keeps decoys next to the real thing is
   worse than no monitoring surface.

Also corrected here: pc3080 was briefly suspected of lagging because
admin_peers reported an old head for it. That reading was wrong. A peer's
advertised head only updates when that peer ANNOUNCES a block, and a
non-mining verifier never does, so its advertised head sits frozen at
session start. pc3080 was at the network head the whole time, confirmed by
querying it directly (7,499, identical hash and total difficulty).

## 2026-08-14: cross-model rounds close, the tree is simplified, and the
## sidecar learns to say no

Eight commits after round 4, in the order they landed.

1. **80f8ef1, Kimi round 3.** Three findings, and two of them were bugs
   round 4 had already fixed independently (the container guard's hex
   parsing, and the authorized miner's read deadline). Two reviewers
   arriving separately at the same two defects, both already closed, is the
   first genuine convergence signal of the campaign: 44 findings, then 30,
   25, 7, and now one. The one new item was real: burn_audit marked an
   account inexact only when the transaction carried VALUE, but any call
   into contract code can move value invisibly to basic RPC (a zero-value
   withdraw pays the SENDER), so the audit would have failed forever on a
   healthy chain. A permanently red proof is worse than an honestly scoped
   one, because it hides the next real divergence behind alarm fatigue.
2. **943cb74, a join recipe that works.** The Wheeler section named the
   bootnode and warned that a stock client cannot follow the chain, then
   sent the reader to sections that boot a local DEVNET. There was no
   command to actually join. That is the likely reason three separate
   hosts connected to the bootnode overnight with stock builds and
   silently bounced. The README now carries the sequence, verified by
   running it: a fresh datadir synced 7,499 blocks from the bootnode.
   It also names the failure signature, which is what would have saved the
   three who bounced: height stuck at 0x0 while peer count is non-zero
   means an unpatched client.
3. **b2be646, the liveness alarm** (see the incident entry above).
4. **e6e7b38, the dashboard is light by default.** The categorical trio was
   revalidated against the light surface rather than inherited: the old
   teal reached only 2.94:1 on white. Two bugs were invisible until the
   switch: the tooltip hardcoded a near-black background (dark on dark),
   and the y-axis labels were clipped because the gutter was narrower than
   the widest label.
5. **19a64d1, simplification: 2,371 lines deleted.** The vendored
   go-quai reference (2,233 lines) was unreachable by every build, test and
   CI path, could not compile here, and forced an LGPL exception into
   LICENSE. Two superseded G6 planning docs and a third copy of the
   bootnode enode went with it, and join_wheeler_wsl.sh now delegates to
   ci_prepare.sh rather than re-implementing its twelve steps.
   docker/node.Dockerfile deliberately KEEPS its copy, because delegating
   forces `COPY . /src` before the core-geth fetch and a README typo would
   then bust the clone layer and re-run the 40-minute KawPow gate. The
   duplication is instead GATED: check_consistency.py now fails if the two
   recipes copy different client files or apply different hooks, and it is
   negative-controlled against the real historical bug (removing
   asert_enum_test.go from the Dockerfile's list, the omission that once
   let a consensus gate pass while running zero tests). Two deletion
   candidates were rejected on inspection: verify_rewards.py is read by the
   consistency job for Article III constants, and G6_P1_NOTES.md and
   DAA_MEMO.md are cited by shipped code as normative specs.
6. **1cf37d4, DeepSeek round 5** (its first completed run after two silent
   deaths; the cause was prompt bloat, and a lean prompt fixed it). The
   sidecar validated a submit's SHAPE but never checked it against the
   target, while a comment claimed it did. That comment was false: checking
   it IS the node's KawPow work. So any LAN client could read the broadcast
   job header, spam well-formed garbage, occupy every forward slot, and
   make the node burn a full light verification on each, while doing no
   proof of work itself. core-geth's remote sealer handles submits, new
   work and getWork on ONE goroutine, so the honest miner's winning share
   queues behind the junk. Also: the dashboard's Supply tile summed the
   audit's per-account balances, which equals supply only while every
   holder appears in a transaction; burn_audit now reports
   supply = issued - burned.
7. **f276dfe, the first fix for that was wrong, and production said so.**
   A one-in-flight latch shipped, and within a minute the honest GPU had
   been skipped once: a 25 MH/s rig at the 8M share target submits about
   three shares a second and a node call takes milliseconds, so the rig's
   own submits overlap, and the latch dropped the second one. A dropped
   submit can be the block-winning one. Replaced with a per-client token
   bucket (30/s sustained, 60 burst) that separates honest from hostile by
   RATE rather than by luck. Caught by watching the log after deploying,
   not by reasoning.
8. **7f21d26, and the token bucket was multipliable.** Reviewed with fresh
   eyes (a different model reading the same repo), the per-client budget
   turned out to be bypassable by opening more clients: ten connections
   from one address cut the honest miner's delivery from three submits to
   one. maxPerIP = 4 removes the multiplier. The loopback exemption made
   the cap untestable by construction, since every test connection is
   loopback, so it is a package var the test switches off.

The standing lesson from the whole campaign, stated once: **a guard is
worth exactly what its failure mode is worth, and the newest guard is
always the least reviewed code in the tree.** Three consecutive rounds
found their bug in the previous round's fix. Two of those were caught only
because a different model read the code, and one because a log was watched
after a deploy rather than a test being trusted.

## 2026-08-14: audit round 4, 6 code findings, five in the night's own guards

6e96e89, run against ed5a046 on the theory that the newest code is the least
reviewed. It was: five of the six are defects in guards written a few hours
earlier, which is the rule at the end of the entry above being paid out on
its first test.

1. The container's volume-genesis guard from 23c2efc was a PERMANENT NO-OP.
   `eth.chainId()` has no console output formatter in the pinned tree, so it
   returns the raw RPC quantity (`0xed14f0`, confirmed against the live
   node), and the validator accepted only decimal digits. It therefore
   discarded every real answer, wrote no marker, and compared nothing, for
   exactly the legacy volumes it was written to protect. Hex is normalized
   now.
2. The fail-closed genesis guard added to `boot_devnet.sh` in ed5a046
   BRICKED the script on this host: both probes start a full geth, which
   binds the default authrpc 8551 before it evaluates `--exec`, so on a host
   already running a node the probe died before printing and the new
   fail-closed check misdiagnosed it as an unreadable datadir, telling the
   operator to stop production, after tens of minutes of gates. Both probes
   use dedicated ports now, which the script's own exec line already did. A
   guard that fails closed has to be right about WHY it is failing.
3. `deploy_node.sh`'s replacement identity proof was a tautology: round 3
   replaced "the height advanced" with "the sha256 of the running binary
   matches the one built", but it hashed the file at `$GETH`, the same file
   step 3 had just built and hashed, so it could not disagree. It also chose
   the lowest pid matching the tree, which a devnet started from that tree
   satisfies. It asks launchd which pid it manages now, and compares the
   INODE the process holds open as its text image against the inode just
   built. Verified live.
4. The stratum `idleTimeout` was unreachable until a miner's THIRD line,
   because the loop arms it at the top of an iteration only if the session
   was already authorized, so a rig that authorized and then waited for its
   first job was dropped 60s after connecting. Production at ~11 MH/s hid
   it; a small rig or a restarting node would not. The generous window is
   armed the moment authorize is handled.
5. `run_stratum.sh`'s live-sidecar guard and `ci_prepare.sh`'s in-use check
   used pgrep patterns anchored only at the start, so the e2e harness's
   `kawpow-stratum-e2e` binary satisfied the production guard and would
   refuse a recovery with a false statement. Both ends anchored now.
6. The production core-geth tree had drifted one commit behind `client/`
   again (comment-only, no consensus impact, but `make_dist.sh` would have
   refused to package it). Redeployed: byte-identical to HEAD, chain
   continued 4661 to 4665, audit wei-exact.

The docs lens of the same round found the identical class on the front door,
so it is logged here rather than quietly fixed: SECURITY.md told reviewers
the status log "runs to the current commit" while the log stopped eight
commits back (the entry above is that backfill), its negative-control
paragraph accounted for four of the five CI jobs and so credited the devnet
e2e gate by omission, `stratum/README.md` still cited the 12-minute run for
"zero disconnects" after the report itself retracted the phrase, and
`client/GETH_INTEGRATION.md` still printed the bare `go test -run` form as
"exactly what CI runs", untouched since round 1 and so false from the moment
round 3 put `gate_test.sh` in front of every gate: the canonical integration
doc was teaching new integrators the vacuous-pass shape round 3 had just
removed.
