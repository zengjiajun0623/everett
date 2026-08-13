# Mining Everett with a GPU

Everett runs **KawPow**, the algorithm Ravencoin has used since 2020 (and
the one Ethereum approved as EIP-1057 and never shipped). That means stock,
unmodified GPU miners work: no custom software, no patched binaries.

Verified 2026-08-13 on an RTX 3080 with **kawpowminer 1.2.4**, unmodified,
against an Everett devnet.

## Quick start

1. Grab a KawPow miner. Verified: `kawpowminer` (open source,
   https://github.com/RavenCommunity/kawpowminer/releases, CUDA and OpenCL
   builds for Windows and Linux). T-Rex and TeamRedMiner also speak KawPow.
2. Run an Everett node with the work API open:

```bash
EVERETT_KAWPOW=1 geth --datadir <dir> --networkid <id> \
  --mine --miner.etherbase 0xYourAddress \
  --http --http.addr 0.0.0.0 --http.port 8545 --http.api eth,net,web3 \
  --http.vhosts '*'
```

3. Point the miner at it (`-U` for CUDA, `-G` for OpenCL):

```bash
kawpowminer -U -P http://0xYourAddress@<node-ip>:8545
```

## The two gotchas, both learned the hard way

- **The address in the URL is not optional.** Without
  `0xYourAddress@`, the ethminer-family getwork client fetches work, mines,
  finds solutions, and silently never submits them: the log fills with
  `Sol:` lines and the chain never advances. With the address, submissions
  flow and blocks land.
- **`--http.vhosts '*'`** (or your node's hostname). geth rejects requests
  whose Host header is not allowlisted, and the miner then reports
  `Solution ... wasted. Waiting for connection`.

## What the node does and does not do

The node **never builds the multi-gigabyte DAG**. GPU miners generate it
themselves from the seed hash; the node keeps only a ~16 MiB light cache
per epoch and verifies with it. Node-side CPU mining exists as a bootstrap
fallback and is slow by design (~700 H/s versus tens of MH/s on a GPU) —
that asymmetry is the point of a GPU-first chain.

## Observed first run

An RTX 3080 joined a devnet whose only miner was a Mac mini CPU. Effect:

| Block | Difficulty |
|---|---|
| 1 | 131,072 (floor) |
| 50 | 154,812 |
| 100 | 195,096 |
| 150 | 245,863 |
| 200 | 309,850 |
| 264 | 416,624 |

ASERT absorbing a roughly four-orders-of-magnitude hashrate arrival exactly
as simulated in DAA_MEMO.md: a smooth exponential climb, no oscillation, no
stall. The supply audit stayed wei-exact throughout (264 blocks, 66 uncles,
every account matching Article III including the III.5 uncle terms).
