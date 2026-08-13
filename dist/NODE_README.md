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

To mine:

```bash
MINE=1 ETHERBASE=0xYourAddress ./run-node.sh
```

Your node verifies the whole chain from the genesis block using nothing but
this package's genesis file: no checkpoints, no trusted snapshots. First
mining run generates a ~1 GB DAG (a few minutes).

Check your node:

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
  http://127.0.0.1:8545
```

If the baked-in bootnode is unreachable, get a fresh `enode://...` from
whoever sent you this and pass it as `BOOTNODE=enode://... ./run-node.sh`.

This binary is macOS/arm64; other platforms build from the repo in about
five minutes (`scripts/boot_devnet.sh`).
