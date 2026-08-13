#!/usr/bin/env python3
"""Idempotently hook the Everett ASERT DAA into Ethash.CalcDifficulty."""
import sys

ANCHOR = """func (ethash *Ethash) CalcDifficulty(chain consensus.ChainHeaderReader, time uint64, parent *types.Header) *big.Int {
	return CalcDifficulty(chain.Config(), time, parent)
}"""
REPLACEMENT = """func (ethash *Ethash) CalcDifficulty(chain consensus.ChainHeaderReader, time uint64, parent *types.Header) *big.Int {
	if cfg := chain.Config(); cfg != nil {
		if id := cfg.GetChainID(); id != nil && id.Uint64() == everettChainID {
			return everettCalcDifficulty(time, parent)
		}
	}
	return CalcDifficulty(chain.Config(), time, parent)
}"""

path = sys.argv[1]
src = open(path).read()
if "everettCalcDifficulty" in src:
    print("DAA hook already present, nothing to do")
    sys.exit(0)
if ANCHOR not in src:
    sys.exit("FAIL: CalcDifficulty anchor not found; upstream changed, hook manually")
open(path, "w").write(src.replace(ANCHOR, REPLACEMENT, 1))
print("DAA hook inserted")
