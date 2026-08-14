# Integrating the Everett consensus delta into core-geth

The canonical, tested recipe is `scripts/ci_prepare.sh`. Run it and you
get a patched core-geth tree at `build/core-geth`, ready for `make geth`
(override the location with `COREGETH_DIR=...`; gates on an operator
host use `build/ci/core-geth` so they never touch the tree a live node
execs from). It does four things:

1. Fetches core-geth pinned to `COREGETH_COMMIT` (`10f1ea74…`, the tree
   every Everett gate was verified against). An existing checkout must
   match the pin or the script fails loudly.
2. Applies the modern-Go compat fixes (blst v0.3.17 bump, memsize
   excision).
3. Copies the `client/` source files into place: `rewards_everett.go`
   (+ test) into `params/mutations/`; `difficulty_everett.go` (+ tests,
   incl. `asert_enum_test.go`) and `kawpow_core.go` (+ test) into
   `consensus/ethash/`.
4. Runs the three hook appliers, then copies `kawpow_engine.go` into
   `consensus/ethash/` (the engine lands after the hooks, deliberately):
   `scripts/apply_hook.py` inserts the chain-ID-keyed reward router at
   the top of `GetRewards` in `params/mutations/rewards.go`
   (`isEverettFamily` → `everettRewards`, the hook `rewards_everett.go`
   refers to); `scripts/apply_daa_hook.py` wires ASERT into
   `consensus/ethash/consensus.go`; and `scripts/apply_kawpow_hooks.py`
   patches four files (`consensus/ethash/consensus.go`,
   `consensus/ethash/sealer.go`, `eth/backend.go`, `cmd/utils/flags.go`)
   for KawPow verification, sealing, and chain-keyed activation. All
   appliers are idempotent and anchored on upstream function signatures;
   a missing anchor fails loudly.

Verify the prepared tree with the standard gates. These are the exact
commands CI runs (.github/workflows/ci.yml); `docker/node.Dockerfile`,
`scripts/boot_devnet.sh`, and `scripts/join_wheeler_wsl.sh` run the same
three with the same minimums:

```bash
cd build/core-geth
bash ../../scripts/gate_test.sh ./params/mutations/ TestEverett 5
bash ../../scripts/gate_test.sh ./consensus/ethash/ TestASERT 11
bash ../../scripts/gate_test.sh ./consensus/ethash/ TestKawPow 7 -timeout 40m
```

Run them through `gate_test.sh`, not as bare `go test -run` commands. Every
gate here selects tests BY NAME from files the prep recipe copies into the
tree, and `go test -run TestFoo` prints "ok ... [no tests to run]" and exits
0 when the pattern matches nothing: a missed copy, a rename, or a typo turns
a consensus gate into a green no-op. That is not hypothetical, it is how the
ASERT enumeration tests once ran nowhere while the gates stayed green. The
wrapper fails unless at least the stated number of tests actually PASSED (5,
11, 7 here), so raise those numbers deliberately when you add tests.

`scripts/boot_devnet.sh` wraps prep, gates, build, and a mining devnet in
one command. `docker/node.Dockerfile` replicates the same recipe (same
pin, same copies, same hooks, same gates) for image builds. Do not fork
the prep; if a variant is needed, extend `ci_prepare.sh`.
