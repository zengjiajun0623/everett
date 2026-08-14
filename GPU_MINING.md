# Mining Everett with a GPU

> **HISTORICAL NOTE 2026-08-13: the getwork experiments below led to the stratum sidecar, which is now the recommended mining transport (stratum/README.md). Kept for the gotchas and measurements.**


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
  --http.vhosts localhost,127.0.0.1,<node-hostname>
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
- **The miner's Host header must be allowlisted, and `'*'` is the wrong way
  to do it.** geth rejects requests whose Host header is not in
  `--http.vhosts`, and the miner then reports `Solution ... wasted. Waiting
  for connection`. List the host the miner actually dials:
  `--http.vhosts localhost,127.0.0.1,<node-hostname>`, the same shape
  `docker/run-node.sh` ships (`node,localhost,127.0.0.1`). If the miner
  dials the node by IP address there is nothing to add at all: geth serves
  any IP-literal Host header unconditionally (`node/rpcstack.go`), and the
  allowlist only governs hostnames. Do not use `'*'`: it accepts every Host
  header and reopens the DNS-rebinding hole the check exists to close, so
  any page browsed on a machine that can route to this RPC could drive it.

## What the node does and does not do

The node **never builds the multi-gigabyte DAG**. GPU miners generate it
themselves from the seed hash; the node keeps only a ~16 MiB light cache
per epoch and verifies with it. Node-side CPU mining exists as a bootstrap
fallback and is slow by design (~700 H/s versus tens of MH/s on a GPU);
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

## Transport finding: getwork proves it, stratum is needed to run it

The run above used geth's built-in getwork API. It works, and it is the
fastest way to prove the algorithm end to end, but it is not the production
transport:

- ethminer-family getwork clients poll by opening a fresh HTTP/1.0
  connection per request. Each cycle logs `Disconnected → Suspend mining →
  Established → Resume mining`. Over the soak run that was **936 suspend
  cycles**, so the GPU mines in fits rather than continuously.
- At low difficulty this is invisible (the chain advanced 11 → 264 in
  minutes). As ASERT raised difficulty ~30x, the share of each cycle spent
  actually hashing became the limit and block production stalled around
  difficulty 4M, with 1,621 solutions found but many of them for jobs that
  had already gone stale.

So: **getwork for demonstration and solo experiments, stratum for real
mining.** The stratum dialect kawpowminer/T-Rex expect is fully specified
in G6_P1_NOTES.md §4 (message shapes, extranonce discipline, the
consensus-critical `height` field, share validation), including which
open-source proxies are worth adapting. Building that sidecar is the next
G6 task; the algorithm underneath it is already proven.
