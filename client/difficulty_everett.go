// difficulty_everett.go implements the Everett DAA: relative ASERT with a
// 30-minute half-life (see DAA_MEMO.md, decision v2).
//
//   D_next = D_parent * 2^(-(st - 13)/1800), st = clamp(time - parent.Time, 1, 10800)
//   exponent capped to one halving/doubling per block; floor 131072.
//
// CONSENSUS-CRITICAL PROPERTY: this function is PARENT-ONLY. It must never
// read ancestors, the database, or any state beyond (time, parent). The
// first LWMA implementation walked a 45-header window through chain.GetHeader
// and split consensus during batch sync (verifier saw a shorter window than
// the miner; block 3 rejected, "have 131072, want 135607"). The signature
// below deliberately takes no chain reader so the compiler enforces the
// property. Do not add one back.
//
// The 2^frac fixed-point cubic and its constants are the aserti3-2d
// approximation used in production by Bitcoin Cash since 2020.

package ethash

import (
	"math/big"

	"github.com/ethereum/go-ethereum/core/types"
)

const (
	everettChainID    uint64 = 15537393
	asertTargetSeconds int64  = 13
	asertHalfLife      int64  = 1800
	asertSolveTimeCap  int64  = 6 * asertHalfLife
)

var everettMinDiff = big.NewInt(131072)

// everettCalcDifficulty returns the ASERT difficulty for a block at `time`
// whose parent is `parent`. Parent-only by construction.
func everettCalcDifficulty(time uint64, parent *types.Header) *big.Int {
	st := int64(time) - int64(parent.Time)
	if st < 1 {
		st = 1
	}
	if st > asertSolveTimeCap {
		st = asertSolveTimeCap
	}

	// exponent e = -(st - T)/tau in Q16, capped to [-1, +1] (one halving or
	// doubling per block).
	eQ16 := -((st - asertTargetSeconds) << 16) / asertHalfLife
	if eQ16 > 65536 {
		eQ16 = 65536
	}
	if eQ16 < -65536 {
		eQ16 = -65536
	}

	// Split e = I + f/65536 with f in [0, 65536).
	shifts := eQ16 >> 16 // arithmetic shift: floor division by 65536
	frac := uint64(eQ16 - (shifts << 16))

	// aserti3-2d cubic approximation of 2^(frac/65536), Q16 result.
	factor := uint64(65536) + ((195766423245049*frac +
		971821376*frac*frac +
		5127*frac*frac*frac +
		(uint64(1) << 47)) >> 48)

	next := new(big.Int).Set(parent.Difficulty)
	next.Mul(next, new(big.Int).SetUint64(factor))
	sh := 16 - shifts // net right-shift; shifts is in {-1, 0} for capped e... and +1 when doubling capped
	if sh >= 0 {
		next.Rsh(next, uint(sh))
	} else {
		next.Lsh(next, uint(-sh))
	}

	if next.Cmp(everettMinDiff) < 0 {
		return new(big.Int).Set(everettMinDiff)
	}
	return next
}
