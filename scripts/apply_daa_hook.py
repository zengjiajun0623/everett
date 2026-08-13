#!/usr/bin/env python3
"""Idempotently hook the Everett-family ASERT DAA into Ethash.CalcDifficulty (consensus.go)."""
import sys

ANCHOR = """func (ethash *Ethash) CalcDifficulty(chain consensus.ChainHeaderReader, time uint64, parent *types.Header) *big.Int {
	return CalcDifficulty(chain.Config(), time, parent)
}"""
REPLACEMENT = """func (ethash *Ethash) CalcDifficulty(chain consensus.ChainHeaderReader, time uint64, parent *types.Header) *big.Int {
	if cfg := chain.Config(); cfg != nil {
		if id := cfg.GetChainID(); id != nil && isEverettFamilyDiff(id.Uint64()) {
			return everettCalcDifficulty(time, parent)
		}
	}
	return CalcDifficulty(chain.Config(), time, parent)
}"""

path = sys.argv[1]
src = open(path).read()
if "isEverettFamilyDiff" in src:
    print("DAA hook already present, nothing to do")
    sys.exit(0)
if "everettCalcDifficulty" in src:
    sys.exit("FAIL: outdated DAA hook present; delete build/core-geth and re-run for a clean clone")
if ANCHOR not in src:
    sys.exit("FAIL: CalcDifficulty anchor not found; upstream changed, hook manually")
open(path, "w").write(src.replace(ANCHOR, REPLACEMENT, 1))
print("DAA hook inserted")
