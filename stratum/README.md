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
  --mine --miner.etherbase 0xPoolPlaceholder \
  --http --http.addr 127.0.0.1 --http.api eth,net,web3
```

Sidecar:

```bash
NODE=http://127.0.0.1:8545 LISTEN=:3333 ../scripts/run_stratum.sh
```

Miner (note `stratum://`, not `http://`, and the address is the payout):

```bash
kawpowminer -U -P stratum://0xYourAddress@<sidecar-host>:3333
```

The payout address rides in the stratum username, so the node's
`--miner.etherbase` becomes a placeholder: solo shares that meet the block
target are submitted as blocks and credited by the node to whatever the
submitted work resolves to. (For per-miner payout accounting, a real pool
would track shares; solo mode does not need to.)

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
- Solo mode: share target = block target, so every accepted share is a
  block. No vardiff.

## Open verification (to confirm on the devnet)

kawpowminer selects its stratum dialect from the URL scheme; `stratum://`
autodetects. If it negotiates NiceHash mode (EthereumStratum/1.0.0) instead
of plain mode, the subscribe/submit shapes differ and this sidecar's
handshake needs a branch for it. The devnet run will show which mode the
miner picks from the first `mining.subscribe`; the fix, if needed, is a
mode branch in `handle`, not a redesign.
