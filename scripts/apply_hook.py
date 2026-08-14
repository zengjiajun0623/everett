#!/usr/bin/env python3
"""Idempotently insert the Everett-family router hook into params/mutations/rewards.go.

--verify checks, without writing, that the hook is present AND current.
Idempotency keyed on a MARKER rather than the inserted TEXT means an edited
hook never reaches an existing tree: the applier says "already present" and
the binary keeps the old consensus wiring. deploy_node.sh uses --verify to
prove a built tree really carries this patch set.
"""
import sys

HOOK = """	if id := config.GetChainID(); id != nil && isEverettFamily(id.Uint64()) {
		return everettRewards(header, uncles)
	}
"""
ANCHOR = "func GetRewards(config ctypes.ChainConfigurator, header *types.Header, uncles []*types.Header) (*uint256.Int, []*uint256.Int) {\n"

VERIFY = "--verify" in sys.argv
if VERIFY:
    sys.argv.remove("--verify")
path = sys.argv[1]
src = open(path).read()
if HOOK in src:
    print("reward hook: current")
    sys.exit(0)
if "isEverettFamily" in src or "everettChainID" in src:
    sys.exit("FAIL: outdated reward hook in %s; delete the core-geth tree and re-run for a clean patch" % path)
if VERIFY:
    sys.exit("FAIL: reward hook MISSING from %s; tree is not patched" % path)
if ANCHOR not in src:
    sys.exit("FAIL: GetRewards anchor not found; upstream changed, hook manually")
open(path, "w").write(src.replace(ANCHOR, ANCHOR + HOOK, 1))
print("hook inserted")
