#!/usr/bin/env python3
"""Idempotently insert the Everett router hook into params/mutations/rewards.go."""
import sys

HOOK = """	if id := config.GetChainID(); id != nil && id.Uint64() == everettChainID {
		return everettRewards(header, uncles)
	}
"""
ANCHOR = "func GetRewards(config ctypes.ChainConfigurator, header *types.Header, uncles []*types.Header) (*uint256.Int, []*uint256.Int) {\n"

path = sys.argv[1]
src = open(path).read()
if "everettChainID" in src:
    print("hook already present, nothing to do")
    sys.exit(0)
if ANCHOR not in src:
    sys.exit("FAIL: GetRewards anchor not found; upstream changed, hook manually")
open(path, "w").write(src.replace(ANCHOR, ANCHOR + HOOK, 1))
print("hook inserted")
