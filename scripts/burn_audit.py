#!/usr/bin/env python3
"""Article IV audit: prove the 1559 base-fee burn on the live devnet.

Scope limit, stated honestly: this models value flows visible to basic
JSON-RPC. Any account touched by contract code is marked inexact and
SKIPped rather than asserted, because internal transfers need
debug_traceTransaction to see. Third-party payouts from a contract to an
account this audit never saw touched remain uncoverable by that means.

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


# EXPECT_CHAINID (optional) refuses to audit the wrong chain — the
# dashboard and CI set it; a bare manual run keeps the old behavior.
_expect = os.environ.get("EXPECT_CHAINID")
if _expect:
    _got = int(rpc("eth_chainId", []), 16)
    assert _got == int(_expect), f"wrong chain: eth_chainId={_got}, expected {_expect}"

head = int(rpc("eth_blockNumber", []), 16)
bal = defaultdict(int)
inexact = set()  # contract accounts whose value may have moved internally
burned = 0
issued = 0     # every wei the chain minted: block rewards + uncle rewards
txs = 0
uncles_seen = 0
for n in range(1, head + 1):
    b = rpc("eth_getBlockByNumber", [hex(n), True])
    miner = b["miner"].lower()
    base = int(b["baseFeePerGas"], 16)
    bal[miner] += reward(n)
    issued += reward(n)
    # Article III.5: per uncle, floor(R/32) to the uncle's miner and
    # floor(R/32) to this block's miner.
    r32 = reward(n) // 32
    for i in range(len(b.get("uncles", []))):
        u = rpc("eth_getUncleByBlockNumberAndIndex", [hex(n), hex(i)])
        bal[u["miner"].lower()] += r32
        bal[miner] += r32
        issued += 2 * r32
        uncles_seen += 1
    for tx in b["transactions"]:
        rec = rpc("eth_getTransactionReceipt", [tx["hash"]])
        gas = int(rec["gasUsed"], 16)
        egp = int(rec["effectiveGasPrice"], 16)
        # A REVERTED tx (status 0) burns and tips exactly like a
        # successful one, but its value transfer never happens. Modeling
        # the transfer anyway made one reverted tx fail the audit forever.
        okstatus = int(rec.get("status") or "0x1", 16) == 1
        sender = tx["from"].lower()
        val = int(tx["value"], 16) if okstatus else 0
        bal[miner] += (egp - base) * gas          # tip
        burned += base * gas                       # Article IV
        bal[sender] -= val + egp * gas
        if tx["to"]:
            to = tx["to"].lower()
            bal[to] += val
            # ANY call into code can move value invisibly to basic RPC, not
            # just one carrying value: a zero-value withdraw() pays the
            # SENDER from the contract's balance. Gating this on val != 0
            # left both accounts modeled exactly and wrong, so the audit
            # would have failed forever on a healthy chain, which is worse
            # than admitting the model's limit. The sender is marked too,
            # because it is the usual payee of such a call.
            if rpc("eth_getCode", [to, "latest"]) not in ("0x", None):
                inexact.add(to)
                inexact.add(sender)
        elif okstatus and rec.get("contractAddress"):
            # Contract creation: the endowment lands on the new address.
            ca = rec["contractAddress"].lower()
            bal[ca] += val
            inexact.add(ca)
        txs += 1

ok = True
for acct, expected in sorted(bal.items()):
    actual = int(rpc("eth_getBalance", [acct, hex(head)]), 16)
    if acct in inexact:
        # Internal (contract-mediated) flows are invisible to basic RPC:
        # exactness is only claimable for accounts no contract touched.
        # A tracing node (debug_traceTransaction) is the upgrade path.
        print(f"SKIP {acct} actual={actual} (contract-touched; internal flows not modeled)")
        continue
    status = "OK " if actual == expected else "FAIL"
    if actual != expected:
        ok = False
        print(f"{status} {acct} modeled={expected} actual={actual} delta={actual-expected}"
              " (if a contract paid this account, the basic-RPC model cannot see it)")
    else:
        print(f"{status} {acct} modeled={expected} actual={actual} delta={actual-expected}")

print(f"blocks={head} txs={txs} uncles={uncles_seen} burned={burned} wei")
# Supply as ISSUANCE MINUS BURN, not as a sum of the accounts this model
# happened to touch. Those differ the moment a contract pays an address
# that never appears in a transaction: that balance exists on chain but is
# invisible to basic-RPC accounting, so summing modeled balances would
# silently undercount. This figure stays exact on any chain.
print(f"supply={issued - burned} wei issued={issued} wei")
if not ok:
    sys.exit("FAIL: account model diverges from chain state")
if txs and burned <= 0:
    sys.exit("FAIL: transactions occurred but nothing burned")
_exact = len(bal) - len(inexact)
if inexact:
    # Do not claim more than the model checked: contract-touched accounts
    # were SKIPped above, so "every account exact" would be false.
    print(f"PASS: {_exact} directly-modeled accounts exact, {len(inexact)} contract-touched skipped;"
          " base fees provably destroyed")
else:
    print("PASS: every account exact; base fees provably destroyed" if txs
          else "PASS (no txs yet): reward accounting exact; send a tx to test the burn")
