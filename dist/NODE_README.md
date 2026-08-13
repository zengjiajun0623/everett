# Everett Node

Ethereum's Everett branch: the counterfactual PoW chain where the Merge was
never the plan. Chain ID 15537393 (mainnet's last proof-of-work block).
Constitution and source: https://github.com/zengjiajun0623/everett

## Run

```bash
tar xzf everett-node-*.tar.gz && cd everett-node-*
./run-node.sh                      # join and sync (trustlessly, from genesis)
```

To mine:

```bash
MINE=1 ETHERBASE=0xYourAddress ./run-node.sh
```

Your node verifies the entire chain from the genesis block using nothing but
this package's genesis file: no checkpoints, no trusted snapshots. First
mining run generates a ~1 GB DAG (a few minutes).

Check your node:

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
  http://127.0.0.1:8545
```

If the bootnode in run-node.sh is unreachable, get a fresh
`enode://...` from whoever sent you this and pass it as
`BOOTNODE=enode://... ./run-node.sh`.

This binary is macOS/arm64; other platforms build from the repo in about
five minutes (`scripts/boot_devnet.sh`).
