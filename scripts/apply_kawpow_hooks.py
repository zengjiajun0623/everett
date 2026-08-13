#!/usr/bin/env python3
"""Idempotently hook KawPow into core-geth's consensus, sealer, and work API.

Four hooks, each branching on kawpowEnabled and falling through to stock
ethash otherwise:
  1. verifySeal - light KawPow verification (miners own the DAG)
  2. mine       - lazy DAG (skip the ethash one when KawPow is active)
  3. mine loop  - full-DAG KawPow hashing for node-side CPU mining
  4. makeWork   - the KawPow seed hash for remote (GPU) miners; with the
                  ethash seed they build the wrong DAG and every share is
                  rejected.
"""
import sys

CONSENSUS, SEALER = 0, 1

HOOKS = [
    (CONSENSUS, "kawpowVerify",
     """	// Recompute the digest and PoW values
	number := header.Number.Uint64()
""",
     """	// Recompute the digest and PoW values
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
"""),
    (SEALER, "dataset *dataset",
     """		number  = header.Number.Uint64()
		dataset = ethash.dataset(number, false)
	)""",
     """		number  = header.Number.Uint64()
		dataset *dataset
	)
	// Everett: KawPow builds its own DAG lazily; skip the ethash one.
	if !kawpowEnabled {
		dataset = ethash.dataset(number, false)
	}"""),
    (SEALER, "kawpowComputeFull",
     """			digest, result := hashimotoFull(dataset.dataset, hash, nonce)""",
     """			var digest, result []byte
			if kawpowEnabled {
				digest, result = kawpowComputeFull(hash, nonce, number)
			} else {
				digest, result = hashimotoFull(dataset.dataset, hash, nonce)
			}"""),
    (SEALER, "kawpowSeedHash(block.NumberU64()",
     """	s.currentWork[1] = common.BytesToHash(SeedHash(epoch, epochLength)).Hex()""",
     """	if kawpowEnabled {
		s.currentWork[1] = common.BytesToHash(kawpowSeedHash(block.NumberU64() / kawpowEpochLength)).Hex()
	} else {
		s.currentWork[1] = common.BytesToHash(SeedHash(epoch, epochLength)).Hex()
	}"""),
]

paths = [sys.argv[1], sys.argv[2]]
for idx, marker, anchor, repl in HOOKS:
    src = open(paths[idx]).read()
    if marker in src:
        print(f"hook {marker[:26]!r}: already present")
        continue
    if anchor not in src:
        sys.exit(f"FAIL: anchor for {marker!r} not found in {paths[idx]}; upstream changed")
    open(paths[idx], "w").write(src.replace(anchor, repl, 1))
    print(f"hook {marker[:26]!r}: inserted")
