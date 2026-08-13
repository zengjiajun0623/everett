#!/usr/bin/env python3
"""Article IV audit: prove the 1559 base-fee burn on the live devnet.

Full-chain accounting. For every block: credit its miner the constitutional
reward; for every transaction: credit the miner the priority tip, debit the
sender value + gas, credit the recipient the value, and accumulate
burned = gasUsed * baseFee. Then every touched account's modeled balance
must equal its RPC balance EXACTLY, and total burned must be > 0 once a
transaction has occurred. Supply conservation follows: sum(balances) =
sum(rewards) - burned.
"""
import json
import os
import sys
import urllib.request
from collections import defaultdict

RPC = os.environ.get("RPC", "http://127.0.0.1:8545")
ERA, SLOW = 100_000, 93_000
TAIL, D0 = 2 * 10**17, 18 * 10**17


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(RPC, body, {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req))["result"]


def decay(era):
    d = D0
    for _ in range(era):
        d = d * 993 // 1000
    return d


def reward(n):
    if n == 0:
        return 0
    r = TAIL + decay(n // ERA)
    if n < SLOW:
        r = r * n // SLOW
    return r


head = int(rpc("eth_blockNumber", []), 16)
bal = defaultdict(int)
burned = 0
txs = 0
uncles_seen = 0
for n in range(1, head + 1):
    b = rpc("eth_getBlockByNumber", [hex(n), True])
    miner = b["miner"].lower()
    base = int(b["baseFeePerGas"], 16)
    bal[miner] += reward(n)
    # Article III.5: per uncle, floor(R/32) to the uncle's miner and
    # floor(R/32) to this block's miner.
    r32 = reward(n) // 32
    for i in range(len(b.get("uncles", []))):
        u = rpc("eth_getUncleByBlockNumberAndIndex", [hex(n), hex(i)])
        bal[u["miner"].lower()] += r32
        bal[miner] += r32
        uncles_seen += 1
    for tx in b["transactions"]:
        rec = rpc("eth_getTransactionReceipt", [tx["hash"]])
        gas = int(rec["gasUsed"], 16)
        egp = int(rec["effectiveGasPrice"], 16)
        sender = tx["from"].lower()
        val = int(tx["value"], 16)
        bal[miner] += (egp - base) * gas          # tip
        burned += base * gas                       # Article IV
        bal[sender] -= val + egp * gas
        if tx["to"]:
            bal[tx["to"].lower()] += val
        txs += 1

ok = True
for acct, expected in sorted(bal.items()):
    actual = int(rpc("eth_getBalance", [acct, hex(head)]), 16)
    status = "OK " if actual == expected else "FAIL"
    if actual != expected:
        ok = False
    print(f"{status} {acct} modeled={expected} actual={actual} delta={actual-expected}")

print(f"blocks={head} txs={txs} uncles={uncles_seen} burned={burned} wei")
if not ok:
    sys.exit("FAIL: account model diverges from chain state")
if txs and burned <= 0:
    sys.exit("FAIL: transactions occurred but nothing burned")
print("PASS: every account exact; base fees provably destroyed" if txs
      else "PASS (no txs yet): reward accounting exact; send a tx to test the burn")
