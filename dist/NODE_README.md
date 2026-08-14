# __NETNAME__ node (Everett family)

Everett is Ethereum's counterfactual branch: the PoW chain where the Merge
was never the plan. This package runs the **__NETNAME__** network
(chain ID __NETWORKID__). Wheeler is the testnet, named for John Wheeler,
Everett's doctoral advisor; its coins are valueless by intent, and it runs
the exact consensus rules mainnet will. Constitution and source:
https://github.com/zengjiajun0623/everett

## Run

```bash
tar xzf __NETNAME__-node-*.tar.gz && cd __NETNAME__-node-*
./run-node.sh                      # join and sync (trustlessly, from genesis)
```

Your node verifies the whole chain from the genesis block using nothing but
this package's genesis file: no checkpoints, no trusted snapshots.

## Mine

The chain runs **KawPow**, a GPU algorithm. Real mining means a stock
KawPow miner (kawpowminer, T-Rex) pointed at a `kawpow-stratum` sidecar
that bridges to this node's RPC. The sidecar is not in this package;
build it from the repo (`scripts/run_stratum.sh`, or the Docker stack's
`stratum` service). Then:

```bash
MINE=1 ETHERBASE=0xYourAddress THREADS=0 ./run-node.sh   # serve work, no CPU mining
kawpowminer -U -P stratum+tcp://0xYourAddress@<host>:3333
```

`MINE=1` without `THREADS=0` also CPU-mines KawPow at ~700 H/s, a
bootstrap fallback that is slow by design: do not expect it to land
blocks against GPU hashpower. The first CPU-mining run builds a ~1 GiB
DAG (a few minutes); GPU miners build their own.

Check your node:

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
  http://127.0.0.1:8545
```

If the baked-in bootnode is unreachable, get a fresh `enode://...` from
whoever sent you this and pass it as `BOOTNODE=enode://... ./run-node.sh`.

The binary's platform is in the tarball name (for example
`wheeler-node-darwin-arm64.tar.gz` is macOS on Apple silicon); other
platforms build from the repo in about five minutes
(`scripts/boot_devnet.sh`).
