#!/usr/bin/env python3
"""Idempotently hook KawPow into core-geth's verifySeal and mine paths.

Both hooks branch on kawpowEnabled and fall through to stock ethash
otherwise, so an unpatched-behaviour node is exactly stock geth.
"""
import sys

VERIFY_ANCHOR = """	// Recompute the digest and PoW values
	number := header.Number.Uint64()
"""
VERIFY_HOOK = """	// Recompute the digest and PoW values
	number := header.Number.Uint64()

	// Everett: KawPow verification is light-only (miners own the DAG).
	if kawpowEnabled {
		mixOK, powOK := kawpowVerify(ethash.SealHash(header).Bytes(),
			header.Nonce.Uint64(), number, header.MixDigest[:], header.Difficulty)
		if !mixOK {
			return errInvalidMixDigest
		}
		if !powOK {
			return errInvalidPoW
		}
		return nil
	}
"""

MINE_ANCHOR = """		number  = header.Number.Uint64()
		dataset = ethash.dataset(number, false)
	)"""
MINE_HOOK = """		number  = header.Number.Uint64()
		dataset *dataset
	)
	// Everett: KawPow mines from the light cache; no DAG is ever built here.
	if !kawpowEnabled {
		dataset = ethash.dataset(number, false)
	}"""

MINE_HASH_ANCHOR = """			digest, result := hashimotoFull(dataset.dataset, hash, nonce)"""
MINE_HASH_HOOK = """			var digest, result []byte
			if kawpowEnabled {
				digest, result = kawpowComputeFull(hash, nonce, number)
			} else {
				digest, result = hashimotoFull(dataset.dataset, hash, nonce)
			}"""

consensus_path, sealer_path = sys.argv[1], sys.argv[2]

src = open(consensus_path).read()
if "kawpowVerify" in src:
    print("verify hook already present")
else:
    if VERIFY_ANCHOR not in src:
        sys.exit("FAIL: verifySeal anchor not found")
    open(consensus_path, "w").write(src.replace(VERIFY_ANCHOR, VERIFY_HOOK, 1))
    print("verify hook inserted")

src = open(sealer_path).read()
if "kawpowCompute" in src:
    print("mine hook already present")
    sys.exit(0)
if MINE_ANCHOR not in src or MINE_HASH_ANCHOR not in src:
    sys.exit("FAIL: mine anchors not found")
src = src.replace(MINE_ANCHOR, MINE_HOOK, 1).replace(MINE_HASH_ANCHOR, MINE_HASH_HOOK, 1)
open(sealer_path, "w").write(src)
print("mine hook inserted")
