# Everett

**Ethereum as if proof of stake had never been the plan.**

A genesis-ready specification for a fresh-start proof-of-work EVM chain:
pre-merge Ethereum's machine (ethash, uncles, EIP-1559 burn, modern EVM),
pointed away from the Merge, launched with an empty genesis state and a
monetary constitution frozen before anyone exists to lobby against it.

- [CONSTITUTION.md](CONSTITUTION.md) — the monetary constitution. Governs.
- [GENESIS_SPEC.md](GENESIS_SPEC.md) — client, consensus, and launch spec.

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

Grab the node package from whoever pointed you here (or build from source
below), then `./run-node.sh` to sync trustlessly from genesis, or
`MINE=1 ETHERBASE=0xYou ./run-node.sh` to mine. Nobody's permission
required; that is the point. Wheeler coins are valueless test material.

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
Docker, verification gates included in the build — a failed gate fails the
image) plus an external ethminer over RPC. Portainer-ready; no prebuilt
binaries, no secrets.

```bash
docker build -f docker/node.Dockerfile  -t everett-node:local .
docker build -f docker/miner.Dockerfile -t everett-miner:local .
docker compose -f docker/docker-compose.yml up -d --build
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  http://127.0.0.1:8545     # 0xed14ef devnet, 0xed14f0 Wheeler
```

Full walkthrough (Portainer GUI build + deploy, env table, verification,
safety notes): [docker/README.md](docker/README.md).

## Status

v0.1 draft, August 2026. A launch-in-waiting by design: the spec exists to be
ready, not to be launched into calm. See Constitution Article VIII and
GENESIS_SPEC section 6 for launch procedure.
