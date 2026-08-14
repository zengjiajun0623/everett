#!/usr/bin/env python3
"""Idempotently hook the Everett-family ASERT DAA into Ethash.CalcDifficulty (consensus.go).

--verify checks, without writing, that the hook is present AND current. See
apply_hook.py for why marker-based idempotency is not enough.
"""
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

VERIFY = "--verify" in sys.argv
if VERIFY:
    sys.argv.remove("--verify")
path = sys.argv[1]
src = open(path).read()
if REPLACEMENT in src:
    print("DAA hook: current")
    sys.exit(0)
if "isEverettFamilyDiff" in src or "everettCalcDifficulty" in src:
    sys.exit("FAIL: outdated DAA hook in %s; delete the core-geth tree and re-run for a clean patch" % path)
if VERIFY:
    sys.exit("FAIL: DAA hook MISSING from %s; tree is not patched" % path)
if ANCHOR not in src:
    sys.exit("FAIL: CalcDifficulty anchor not found; upstream changed, hook manually")
open(path, "w").write(src.replace(ANCHOR, REPLACEMENT, 1))
print("DAA hook inserted")
