# Everett

**Ethereum as if proof of stake had never been the plan.**

A genesis-ready, machine-verified proof-of-work EVM chain: pre-merge
Ethereum's machine (uncles, EIP-1559 burn, modern EVM) sealed by KawPow,
pointed away from the Merge, launched with an empty genesis state and a
monetary constitution frozen before anyone exists to lobby against it.
Proven, not just promised:

- **Live**: the Wheeler testnet runs the exact mainnet rules: KawPow
  from genesis, ASERT difficulty, GPU-mined, supply audited wei-for-wei
  every five minutes by an independent Python recomputation (uncles and
  the 1559 burn included).
- **Machine-checked**: Article III is formalized in Lean 4 with zero
  sorries ([fv/](fv/)). The supply bound is an inductive invariant
  (base issuance ≤ 0.2·B + ~25.71M ETT decay component, forever; ×9/8
  under the uncle cap), decay provably dies at era 5360, and from block
  536,000,000 every reward is EXACTLY the 0.2 tail. The ASERT
  fixed-point layer is verified by complete enumeration over its finite
  domain. Three independently written implementations (Go, Python,
  Lean) are pinned to one set of vectors; CI re-proves everything on
  every push.

- [CONSTITUTION.md](CONSTITUTION.md) · the monetary constitution. Governs.
- [GENESIS_SPEC.md](GENESIS_SPEC.md) · client, consensus, and launch spec.
- [fv/](fv/) · the theorems. [LAUNCH_DIFFICULTY.md](LAUNCH_DIFFICULTY.md) ·
  launch parameters from measured data. [RUNBOOK.md](RUNBOOK.md) · the
  full build log, failures included.

## Thesis in three sentences

Ethereum's social layer could redirect capital exactly as long as the people
being paid (miners) were outside the room; the Merge moved the payees inside,
and EIP-8363's 72-hour death in August 2026 showed what governance looks like
afterward. Bitcoin has the mirror rigidity: it cannot raise issuance even when
its security budget will someday need it. This chain fixes both failure modes
at genesis: proof of work keeps security providers outvotable, a smooth-decay
schedule with a permanent tail keeps the security budget funded forever, and
zero premine plus a burden-of-proof-against-change amendment rule leaves no
seed for a constituency to grow from.

## Join the Wheeler testnet (permissionless)

Wheeler (chain ID 15537392) is the live testnet running Everett's exact
consensus rules. Its public bootnode:

```
enode://ad614b8cc1737cdaeaa38706ef131c924a37e507bc8d1e76897037056d6c67bfafca8ed4c65e6be76ed319f38c89a6a5f9acb75b8da822146fc6cc4d9d117b5f@71.183.54.11:30303
```

Wheeler runs KawPow (as mainnet will): sync trustlessly with the Docker
stack below or a source build, and mine with any stock KawPow miner
pointed at the bundled stratum service
(`kawpowminer -U -P stratum+tcp://0xYou@<host>:3333`). Nobody's
permission required; that is the point. Wheeler coins are valueless
test material.

**WARNING: a stock geth or core-geth build cannot follow this chain.**
The genesis deliberately carries no custom fields, so an unpatched node
handshakes with Wheeler peers just fine, but it can never verify a
KawPow seal: it syncs zero blocks and silently drops. Run the patched
build, via the Docker stack below or a source build through
`scripts/ci_prepare.sh`. (A stock core-geth node did exactly this
against our bootnode: perfect handshake, zero blocks, gone.)

## Run it yourself

Prerequisites: macOS or Linux with `git`, Go 1.22+ (`brew install go`), and
Python 3. Then:

```bash
git clone https://github.com/zengjiajun0623/everett && cd everett
ETHERBASE=0xYourAddressHere scripts/boot_devnet.sh
```

That one script clones core-geth, applies the Everett consensus patches,
runs the unit-test gates (the build aborts if any fail), builds geth,
initializes the genesis, and starts mining to your address. First run takes
a few minutes (module downloads, build, ~1 GB DAG generation); after that
your chain persists across restarts (`RESET=1` wipes it, `THREADS=n` uses
more cores).

In a second terminal, audit your own chain against the constitution:

```bash
scripts/verify_devnet.sh
```

`verify_rewards.py` recomputes Article III independently in Python and
demands your miner balance match it wei for wei; `burn_audit.py` does full
supply accounting including uncles (Art. III.5) and the 1559 burn (Art. IV).

## Docker / Portainer quickstart

GPU mining stack for a headless server: the node (built from source in
Docker, verification gates included in the build; a failed gate fails the
image) plus an external ethminer over RPC. Portainer-ready; no prebuilt
binaries, no secrets.

```bash
docker build -f docker/node.Dockerfile    -t everett-node:local .
docker build -f docker/stratum.Dockerfile -t everett-stratum:local .
docker build -f docker/miner.Dockerfile   -t everett-miner:local .
docker compose -f docker/docker-compose.yml up -d --build
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  http://127.0.0.1:8545     # 0xed14ef devnet, 0xed14f0 Wheeler
```

Full walkthrough (Portainer GUI build + deploy, env table, verification,
safety notes): [docker/README.md](docker/README.md).

## Status

v0.1, August 2026. A launch-in-waiting by design: the spec exists to be
ready, not to be launched into calm. Every constitutional article has been
verified live on Wheeler (rewards, uncles, ASERT, and the first burn:
147,000 wei provably destroyed in block 1818) and the schedule is
machine-checked in Lean. Remaining before an Article VIII ceremony:
independent bootnode infrastructure, the name sweep, and a date. See
Constitution Article VIII and GENESIS_SPEC section 6 for launch procedure.
