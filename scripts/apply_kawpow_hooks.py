#!/usr/bin/env python3
"""Idempotently hook KawPow into core-geth's consensus, sealer, and work API.

Five hooks. 1-4 branch on kawpowEnabled and fall through to stock ethash;
hook 5 SETS kawpowEnabled from the loaded chain config (chain-keyed
activation — consensus must never depend on local environment):
  1. verifySeal - light KawPow verification (miners own the DAG)
  2. mine       - lazy DAG (skip the ethash one when KawPow is active)
  3. mine loop  - full-DAG KawPow hashing for node-side CPU mining
  4. makeWork   - the KawPow seed hash for remote (GPU) miners; with the
                  ethash seed they build the wrong DAG and every share is
                  rejected.
  5. backend    - SetKawPowChainID(chainConfig.GetChainID()) once the eth
                  backend resolves the chain: Wheeler/mainnet = KawPow
                  from genesis, dev chain = env-selectable, anything
                  else = forced off. Plus the ethash import it needs.

Usage: apply_kawpow_hooks.py <consensus.go> <sealer.go> [<eth/backend.go>]
(backend.go optional for compatibility with pre-v2 build recipes; the
CI/Docker/boot preps all pass it).
"""
import sys

CONSENSUS, SEALER, BACKEND = 0, 1, 2

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
    (BACKEND, "consensus/ethash\"",
     """	"github.com/ethereum/go-ethereum/eth/ethconfig"
""",
     """	"github.com/ethereum/go-ethereum/consensus/ethash"
	"github.com/ethereum/go-ethereum/eth/ethconfig"
"""),
    (BACKEND, "SetKawPowChainID",
     """	chainConfig, err := core.LoadChainConfig(chainDb, config.Genesis)
	if err != nil {
		return nil, err
	}
""",
     """	chainConfig, err := core.LoadChainConfig(chainDb, config.Genesis)
	if err != nil {
		return nil, err
	}
	// Everett: KawPow activation is keyed to the chain being run, never
	// to local environment. Wheeler (v2) and mainnet: KawPow from genesis.
	ethash.SetKawPowChainID(chainConfig.GetChainID())
"""),
]

paths = [sys.argv[1], sys.argv[2]]
if len(sys.argv) > 3:
    paths.append(sys.argv[3])
for idx, marker, anchor, repl in HOOKS:
    if idx >= len(paths):
        print(f"hook {marker[:26]!r}: SKIPPED (no backend.go argument — env-var activation only)")
        continue
    src = open(paths[idx]).read()
    if marker in src:
        print(f"hook {marker[:26]!r}: already present")
        continue
    if anchor not in src:
        sys.exit(f"FAIL: anchor for {marker!r} not found in {paths[idx]}; upstream changed")
    open(paths[idx], "w").write(src.replace(anchor, repl, 1))
    print(f"hook {marker[:26]!r}: inserted")
