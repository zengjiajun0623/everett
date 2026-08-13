# KawPow port reference material (G6)

`go-quai/` vendors the ProgPoW Go implementation from
github.com/dominant-strategies/go-quai (consensus/progpow, LGPL-3.0,
go-ethereum lineage), unmodified, as the port base for Everett's KawPow.

Port strategy (decided 2026-08-13):

1. **Embed in core-geth's ethash package**, not a separate engine: ProgPoW
   reuses the ethash DAG (same epochs, dataset, cache), so all existing DAG
   machinery, remote-sealer plumbing, and our reward/DAA hooks carry over.
   The port is the mixing core only: kiss99, fill_mix, the per-period
   program generator, progpowLoop, keccak-f800.
2. **Bit-exact KawPow, zero Everett customization.** T-Rex, kawpowminer,
   and lolMiner must validate against us unmodified: the gamer thesis
   depends on stock miner software. KawPow deltas from this reference
   (per G6_P1_NOTES.md when research lands): period 3 (not 10), and
   Ravencoin's keccak-f800 domain constants in the state initialization.
3. **Differential gate before consensus wiring**: the Go core must
   reproduce Ravencoin/kawpowminer test vectors bit-exactly, in unit tests
   that run in boot_devnet.sh's gate, before any devnet flips to KawPow.
4. Wheeler flips first (testnet rehearsal, ASERT absorbing the 3080);
   mainnet spec follows only after soak.
