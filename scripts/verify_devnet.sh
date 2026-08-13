#!/usr/bin/env bash
# Verification loop, gate 2: interrogate the running devnet over RPC and
# prove it matches the constitution. Independent of the Go code by design:
# the schedule is recomputed in Python and compared against on-chain state.
set -euo pipefail
RPC="${RPC:-http://127.0.0.1:8545}"
call() { curl -s -X POST -H 'Content-Type: application/json' --data "$1" "$RPC"; }

echo "== chainId (expect 0xed14f1 = 15537393) =="
call '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'; echo

echo "== genesis: London active (baseFeePerGas present), no withdrawalsRoot =="
call '{"jsonrpc":"2.0","id":2,"method":"eth_getBlockByNumber","params":["0x0",false]}'; echo

echo "== supply audit (exact, independent recomputation; uncle- and tx-aware) =="
python3 "$(cd "$(dirname "$0")" && pwd)/burn_audit.py"
# verify_rewards.py remains as the strict single-miner G2 gate (plus genesis
# pinning via EXPECT_GENESIS); it intentionally fails on multi-miner chains.
