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

## Status

v0.1 draft, August 2026. A launch-in-waiting by design: the spec exists to be
ready, not to be launched into calm. See Constitution Article VIII and
GENESIS_SPEC section 6 for launch procedure.
