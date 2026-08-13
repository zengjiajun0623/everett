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

## Status

v0.1 draft, August 2026. A launch-in-waiting by design: the spec exists to be
ready, not to be launched into calm. See Constitution Article VIII and
GENESIS_SPEC section 6 for launch procedure.
