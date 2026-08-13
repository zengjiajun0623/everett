#!/usr/bin/env python3
"""Gate 2 of the verification loop: the miner's balance must equal the
constitutional reward sum EXACTLY, wei for wei, over every mined block.

The schedule is recomputed here, independently of the Go implementation, so
a bug in either one fails the gate. An unpatched core-geth pays a flat
2 ETT/block and fails immediately, which is the point: the check cannot pass
by accident.
"""
import json
import os
import sys
import urllib.request

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
if head == 0:
    sys.exit("FAIL: no blocks mined yet")

genesis = rpc("eth_getBlockByNumber", ["0x0", False])
print("genesis hash (pin this):", genesis["hash"])
expect = os.environ.get("EXPECT_GENESIS")
if expect:
    assert genesis["hash"].lower() == expect.lower(), \
        f"FAIL: genesis hash {genesis['hash']} != pinned {expect}"
assert "baseFeePerGas" in genesis, "FAIL: London not active at genesis"
assert genesis.get("withdrawalsRoot") is None, "FAIL: beacon-era field in PoW genesis"

miner = rpc("eth_getBlockByNumber", ["0x1", False])["miner"]
balance = int(rpc("eth_getBalance", [miner, hex(head)]), 16)
expected = sum(reward(n) for n in range(1, head + 1))

print(f"blocks mined: {head}")
print(f"miner balance: {balance}")
print(f"constitution:  {expected}")
if balance != expected:
    sys.exit(f"FAIL: delta {balance - expected} wei (uncles? fees? wrong schedule?)")
print(f"PASS: {head} blocks match Article III exactly, wei for wei")
