# The Everett Monetary Constitution

**Version 0.2 draft.** The network is named **Everett**, for Hugh Everett
III, author of the many-worlds interpretation. In his physics, every
unrealized possibility is a branch that is somewhere real. This chain is
Ethereum's Everett branch: the timeline in which the Merge was never the
plan. The unit of account is the **ETT**.

This network is a counterfactual made runnable: **Ethereum as if proof of
stake had never been the plan.** It restores the machine of early-2022
Ethereum (ethash, uncles, the 1559 burn) and discards the destination that
machine was being marched toward. No historical Ethereum was ever this chain;
the difficulty bomb ticking in every pre-merge client was the old plan's
signature. Here the bomb is gone and nothing replaces it.

This document is the constitution of the network. Its hash is committed in the
genesis block. It exists because of a single lesson, learned twice:

> A protocol that can amend its own monetary policy will eventually have that
> policy amended by whoever it pays. Ethereum cannot cut its issuance because
> its stakers vote. Bitcoin cannot raise its issuance because its holders
> worship. Both rigidities were chosen by accident. Ours is chosen on purpose,
> and written down before anyone exists to lobby against it.

## Article I. Definition

1. The network is the chain of blocks that (a) descends from the genesis block
   committing to this constitution and (b) validates under rules consistent
   with Articles II through VI.
2. Any client, fork, or chain that deviates from Articles II through VI is by
   definition a different network, regardless of hashpower, market
   capitalization, or social support. This constitution cannot be amended into
   something else; it can only be abandoned for something else, under a
   different name.

## Article II. Consensus

1. Consensus is proof of work, permanently.
2. The protocol shall never enshrine stake in any form: no staking, no
   delegation, no protocol-recognized bond, no yield paid to capital for being
   capital. Security providers must remain external to the ledger they secure,
   so that they can be outvoted.
3. No checkpointing authority, no finality committee, no trusted setup for
   consensus. The heaviest valid chain from genesis is the chain.

## Article III. Monetary Schedule

1. Block reward: `R(block) = R_tail + D(era)` where `era = floor(block /
   100,000)`, `D(0) = 1.8` ETT, `D(n) = floor(D(n-1) * 993 / 1000)`, and
   `R_tail = 0.2` ETT. All arithmetic is integer arithmetic in wei.
   `R(0) = 0`: the genesis block is unmined and pays nothing.
2. The schedule is discrete and integer-exact because consensus code must be
   deterministic: floating point has no place in money. The 0.7% step every
   100,000 blocks approximates a smooth four-year half-life at the 13-second
   target (about 4.07 years), fine-grained enough (a step every ~15 days)
   that there are no halving events, no supply-shock politics, no cliff for
   miner revenue. Calendar timing drifts with realized block times, as
   Bitcoin's does.
3. The tail emission is permanent. The security budget never goes to zero and
   is never subject to a vote. Annual issuance trends toward a fixed absolute
   amount (approximately 485,000 ETT per year at 13-second blocks), so the
   inflation rate declines asymptotically toward zero as supply grows, without
   ever creating a fee-cliff crisis.
4. Slow start: the block reward is scaled by `min(block, 93,000) / 93,000`,
   rounding down; full reward applies from block 93,000 (about 14 days in).
   Early-information advantage is deliberately blunted: week one pays out
   roughly a quarter of a steady-state week in aggregate.
5. Uncle issuance: a block referencing `k` valid uncles (`k <= 2`, pre-merge
   validity rules) additionally issues `floor(R/32)` to each uncle's miner
   and `floor(R/32)` per uncle to the block's own miner, where `R` is that
   block's `R(block)`. Total issuance for a block is therefore
   `R * (1 + k/16)`. No issuance beyond clauses 1 through 5 exists.
6. These parameters, clauses 1 through 5, are unamendable under Article VII.
7. Pre-merge Ethereum kept issuance amendable and used that power well,
   cutting miner pay twice. That flexibility was safe only because miners
   were politically weak outsiders. This constitution declines to bet that
   security providers stay politically weak forever. The schedule is frozen
   not because Ethereum misused the dial, but because every dial eventually
   finds a hand.

## Article IV. Fee Burn

1. EIP-1559 fee mechanics apply from genesis: the base fee is burned.
2. Burned fees benefit all holders equally and are the only mechanism by which
   supply decreases. At sufficient usage the network may be net deflationary;
   at low usage the tail keeps security funded. Neither outcome requires
   anyone's permission.
3. Priority fees go to the miner of the block. Nothing else does.

## Article V. No Privileged Allocations

1. Zero premine. Zero dev fund. Zero foundation allocation. Zero treasury.
   Zero token sale. The genesis state is empty: no balances, no contract
   code, no storage.
2. Every unit of ETT that ever exists is either mined under Article III or
   already burned under Article IV.
3. Founders, authors of this constitution, and client developers acquire ETT
   the same way everyone else does. This is not generosity; it is the removal
   of the seed from which constituencies grow. A protocol treasury is a
   constituency with a budget.

## Article VI. Neutrality

1. The protocol shall contain no address allowlists, no blocklists, no
   transaction censorship, and no mechanism by which one may be added.
2. Valid transactions are ordered by fee and by miner discretion. Miner
   discretion is bounded by competition, not by protocol enforcement.

## Article VII. Amendment and Supremacy

1. Articles II through VI are immutable. No process exists to change them.
   A change to them is an exit, per Article I.2.
2. Everything else (EVM semantics, gas schedules, performance, networking,
   difficulty adjustment tuning) is amendable by rough consensus of client
   maintainers and node operators, provided the change is compatible with
   Articles II through VI.
3. Where a technical amendment arguably touches Articles II through VI, the
   presumption is that it does, and it is rejected. The burden of proof runs
   against change. This asymmetry is deliberate: this network holds monetary
   policy as its product, and product does not iterate.

## Article VIII. Launch Fairness

1. The complete genesis specification, client source, and this constitution
   shall be public for no fewer than 30 days before genesis.
2. Genesis time is announced in advance and is the same for everyone.
3. The genesis block's extra-data field commits the 32-byte keccak256 hash of
   this constitution. Ethash caps extra-data at 32 bytes, so the headline
   lives here, inside the constitution itself, and is committed through the
   hash. Provisional text, to be replaced with the launch-triggering headline
   before the v1.0 freeze: "Defiant 08/Aug/2026 Aave and ether.fi founders
   lead opposition to Ethereum staking yield burn."
