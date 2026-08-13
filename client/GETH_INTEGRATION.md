# Integrating the Lifeboat reward schedule into core-geth

1. Copy `rewards_lifeboat.go` and `rewards_lifeboat_test.go` into
   `params/mutations/` of a core-geth checkout.
2. Hook the router: in `params/mutations/rewards.go`, at the top of
   `GetRewards`, before the ECIP-1017 check, insert:

```go
	if id := config.GetChainID(); id != nil && id.Uint64() == lifeboatChainID {
		return lifeboatRewards(header, uncles)
	}
```

   (`scripts/apply_hook.py` does this idempotently.)
3. `go test ./params/mutations/ -run TestLifeboat -v` — all five must pass.
4. `make geth`, then `scripts/boot_devnet.sh` and `scripts/verify_devnet.sh`.

Design notes: chain-ID gating is the v0.1 shortcut; the proper core-geth way
is a ctypes ChainConfigurator feature flag, deferred until a real fork of the
repo exists. The uncle scheme reuses `big32` from rewards.go (same package).
