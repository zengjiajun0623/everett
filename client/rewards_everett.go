// rewards_everett.go implements CONSTITUTION.md Article III.
// Drop into core-geth's params/mutations/ package alongside rewards.go,
// then apply the router hook described in GETH_INTEGRATION.md.
//
// R(block) = R_tail + D(era)
//   era  = block / 100_000
//   D(0) = 1.8 ETT, D(n) = floor(D(n-1) * 993 / 1000)
//   Slow start: blocks 1..93_000 scale linearly.
// All arithmetic integer-exact; no floating point anywhere near money.

package mutations

import (
	"math/big"

	"github.com/ethereum/go-ethereum/core/types"
	"github.com/holiman/uint256"
)

const (
	everettChainID   uint64 = 15537393 // mainnet: reserved for the Art. VIII launch
	wheelerChainID   uint64 = 15537392 // Wheeler testnet: the penultimate PoW block
	everettEraLength uint64 = 100_000
	everettSlowStart uint64 = 93_000
)

// isEverettFamily reports whether a chain ID runs the Everett consensus
// rules. Wheeler (the testnet, named for Everett's advisor) runs identical
// rules so it rehearses exactly what mainnet will do.
func isEverettFamily(id uint64) bool {
	return id == everettChainID || id == wheelerChainID
}

var (
	everettTail   = uint256.NewInt(200_000_000_000_000_000)   // 0.2 ETT
	everettDecay0 = uint256.NewInt(1_800_000_000_000_000_000) // 1.8 ETT
	everettNum    = uint256.NewInt(993)
	everettDen    = uint256.NewInt(1000)
)

// everettDecay returns D(era) by exact iterated floor division. Eras advance
// one per ~15 days, so the loop stays trivially cheap for centuries; the
// compounding floor rounding is part of the consensus definition, not error.
func everettDecay(era uint64) *uint256.Int {
	d := new(uint256.Int).Set(everettDecay0)
	for i := uint64(0); i < era; i++ {
		d.Mul(d, everettNum)
		d.Div(d, everettDen)
	}
	return d
}

// EverettBlockReward returns R(block) per Article III, slow start included.
func EverettBlockReward(num *big.Int) *uint256.Int {
	if !num.IsUint64() {
		// Unreachable for ~7 trillion years; defined anyway: tail only.
		return new(uint256.Int).Set(everettTail)
	}
	n := num.Uint64()
	if n == 0 {
		return uint256.NewInt(0)
	}
	r := everettDecay(n / everettEraLength)
	r.Add(r, everettTail)
	if n < everettSlowStart {
		r.Mul(r, uint256.NewInt(n))
		r.Div(r, uint256.NewInt(everettSlowStart))
	}
	return r
}

// everettRewards mirrors the ETC Era-2+ uncle scheme on the Everett
// schedule: each uncle miner earns R/32, the winner earns R plus R/32 per
// included uncle. Uncle count is bounded by VerifyUncles upstream.
func everettRewards(header *types.Header, uncles []*types.Header) (*uint256.Int, []*uint256.Int) {
	blockReward := EverettBlockReward(header.Number)
	uncleRewards := make([]*uint256.Int, len(uncles))
	reward := new(uint256.Int).Set(blockReward)
	per32 := new(uint256.Int).Div(blockReward, big32)
	for i := range uncles {
		uncleRewards[i] = new(uint256.Int).Set(per32)
		reward.Add(reward, per32)
	}
	return reward, uncleRewards
}
