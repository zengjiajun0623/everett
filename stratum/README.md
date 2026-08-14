# kawpow-stratum

A solo stratum sidecar that lets stock KawPow GPU miners mine an Everett
node continuously, fixing the getwork churn documented in `../GPU_MINING.md`
(getwork's poll-per-connection pattern caused ~936 mining suspensions in a
soak and stalled block production as difficulty climbed).

## What it is

A ~300-line Go proxy with a node on one side and miners on the other:

```
kawpowminer/T-Rex  --stratum-->  kawpow-stratum  --eth_getWork/submitWork-->  geth
```

It is **consensus-free by design**: it never hashes or validates proof of
work. The node does KawPow verification on `eth_submitWork` (the light path
proven bit-exact against Ravencoin). The sidecar only translates transports
and tracks jobs.

## Run

Node (KawPow, work API reachable):

```bash
EVERETT_KAWPOW=1 geth --datadir <dir> --networkid <id> \
  --mine --miner.etherbase 0xYourAddress \
  --http --http.addr 127.0.0.1 --http.api eth,net,web3
```

Sidecar:

```bash
NODE=http://127.0.0.1:8545 LISTEN=:3333 ../scripts/run_stratum.sh
```

Miner (note `stratum+tcp://` (forces the mode-0 dialect this sidecar speaks), not `http://` and not bare `stratum://`):

```bash
kawpowminer -U -P stratum+tcp://0xYourAddress@<sidecar-host>:3333
```

**Payout goes to the node's `--miner.etherbase`, not to the stratum
username.** Solo shares that meet the block target are forwarded verbatim
as `eth_submitWork`, which seals the block template the node already
assembled with its own etherbase as coinbase. The `0xYourAddress` in the
miner URL is accepted for miner-client compatibility and shows up in the
sidecar's logs, but it never reaches the node: to receive rewards, set
`--miner.etherbase` on the node to your address. (A real pool would track
per-miner shares for payout accounting; solo mode does not need to.)

## Protocol (mode 0 / "kawpow stratum")

Implemented per `../G6_P1_NOTES.md` §4.2, cross-checked against kawpowminer's
`EthStratumClient` and kralverde's reference proxy:

| Direction | Method | Shape |
|---|---|---|
| miner → | `mining.subscribe` | → `[null, extranonce]` |
| miner → | `mining.authorize` | → `true` |
| node → | `mining.set_target` | `[target64]` before each notify |
| node → | `mining.notify` | `[jobId, header64, seed64, target64, clean, height, bits]` |
| miner → | `mining.submit` | `[user, jobId, 0xnonce16, 0xheader64, 0xmix64]` → `bool` |

- `height` is consensus-critical: the miner derives `prog_seed = height/3`
  and its DAG from `seed`. Both come straight from `eth_getWork`.
- `bits` is the target in Bitcoin compact form (the miner parses it with
  SetCompact); `toCompact` is unit-tested for round-trip fidelity.
- Vardiff solo mode: miners receive a fixed share target (`-sharediff`,
  default 8M) so the submission rate stays sane at any chain difficulty;
  the node judges every forwarded share against the real block target.

## Dialect selection (RESOLVED 2026-08-13, cost one 12-minute run)

**The miner URL must use the `stratum+tcp://` scheme.** Verified on the
devnet with kawpowminer 1.2.4 on an RTX 3080:

- `stratum+tcp://0xADDR@host:3333` forces plain mode-0 stratum, the
  dialect this sidecar speaks. subscribe → authorize → notify → submit all
  worked first try; the GPU's first job produced a burst of accepted
  blocks.
- Bare `stratum://` AUTODETECTS: the miner walks EthereumStratum/2.0.0 →
  EthereumStratum/1.0.0 (NiceHash) → Eth-Proxy and never tries mode 0.
  It then half-works in the worst way: the Eth-Proxy login gets no valid
  answer, the session goes dead, but broadcast `mining.notify` frames
  still reach the socket, so the GPU hashes at full speed and wastes
  every solution ("Solution 0x… wasted. Waiting for connection...").

The sidecar now answers any unknown method with an explicit JSON-RPC
error naming the fix (`connect with stratum+tcp://`) and logs the method,
so a dialect mismatch is loud on both ends instead of a silent stall.
Speaking NiceHash 1.0.0 natively (different subscribe shape, extranonce
nonce composition) stays future work: pools need it, solo miners don't.

## Three more findings the first live runs paid for (2026-08-13)

1. **The kernel's boundary is the notify `bits` field, not
   `mining.set_target`.** kawpowminer echoes set_target on screen
   ("Difficulty: 8.00 Mh") but its CUDA search uses the compact-bits
   param: with block bits there, a 3080 found 1,639 solutions in 7
   seconds against a supposedly-8M share target. bits must encode the
   SHARE target; block bits carry nothing the miner needs.
2. **Vardiff is mandatory, not an optimization** (`-sharediff`, default
   8M). At trivial chain difficulty the miner drowns in its own
   submission queue, trips its own 2-second response watchdog,
   disconnects, and then dies of a teardown-while-kernel-running race
   (0xC0000005). A calm share rate avoids the entire cascade. No block
   is ever lost: below-sharediff chain difficulty makes every share a
   block; above it the share bar still passes every block solution.
3. **Never wait on the node in the reply path.** The node stalls
   `eth_submitWork` for seconds while digesting a block burst; one
   synchronous forward froze all miner replies past the same watchdog.
   Shares are acked instantly, forwards run async (max 4 in flight,
   8-second RPC timeout, drop-when-saturated).

Proof: 12-minute e2e (stratum/E2E_REPORT.md), RTX 3080, ~1,000+
blocks, zero disconnects, ASERT climbing 131k → multi-M on schedule.
