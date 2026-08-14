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

Negative controls, honestly scoped. Two mutations are on record and both
fail their job: KawPow's period (3→4) fails the consensus unit gates
(`TestKawPow`), and the constitution's decay constant (993→990) fails the
constitution-vs-implementation gate. Those runs date from the three-job CI
(consensus, consistency, devnet e2e), which the 2026-08-13 entry below
records as negative-controlled. The two jobs added since, the stratum
sidecar gates and the formal-verification job, have **not** been
negative-controlled: nothing on record shows a real regression making them
red, so read a green run there as "the checks passed", not as "the checks
were shown able to fail". The missing controls would be, e.g., breaking
`toCompact` to show job 3's `TestToCompactRoundTrip` /
`TestShareTargetBoundaries` go red, and flipping a constant in `fv/*.lean`
to show job 5's `lake build` does.

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
12 minutes, zero disconnects, ASERT climbing 131k → 6.4M+ on its
textbook exponential (doubling per minute of fast blocks). Report:
build/STRATUM_E2E_REPORT.md.

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
- **Mac node**: --mine --miner.threads 0 (serves work only), etherbase
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
