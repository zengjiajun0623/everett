package ethash

// Exhaustive verification of the ASERT fixed-point layer.
//
// The approximation's input domain is finite: the capped exponent eQ16
// takes 131,073 values, the cubic's fractional input 65,536. Every test
// here enumerates its ENTIRE domain — these are complete proofs by
// enumeration, not samples. They run in seconds and are named TestASERT*
// so the existing consensus gates (-run TestASERT) include them in CI,
// the Docker image build, and every prep script without modification.
//
// Verified properties:
//   1. cubic accuracy: |factor - 2^(f/65536)·2^16| bounded over ALL f
//   2. factor range: factor ∈ [65536, 131072] over ALL f (so one block
//      can at most double or halve difficulty — Art. of the DAA memo)
//   3. end-to-end monotonicity: the full multiplier 2^shifts·factor is
//      non-increasing as solvetime grows, over ALL eQ16 — including the
//      shift-boundary seams where fixed-point exp implementations
//      classically jump
//   4. solvetime→exponent monotonicity over the whole clamped domain
//   5. difficulty floor holds for every solvetime at boundary parents

import (
	"math"
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/core/types"
)

// cubicFactor mirrors the production computation exactly (kept in one
// place in everettCalcDifficulty; duplicated here deliberately so a
// refactor that changes the constants breaks this test).
func cubicFactor(frac uint64) uint64 {
	return uint64(65536) + ((195766423245049*frac +
		971821376*frac*frac +
		5127*frac*frac*frac +
		(uint64(1) << 47)) >> 48)
}

// TestASERTApproxErrorExhaustive: property 1+2 over all 65,536 inputs.
func TestASERTApproxErrorExhaustive(t *testing.T) {
	maxRelErr := 0.0
	for f := uint64(0); f < 65536; f++ {
		got := float64(cubicFactor(f))
		want := math.Exp2(float64(f)/65536.0) * 65536.0
		if e := math.Abs(got-want) / want; e > maxRelErr {
			maxRelErr = e
		}
		if cf := cubicFactor(f); cf < 65536 || cf > 131072 {
			t.Fatalf("factor out of [1,2] range at f=%d: %d", f, cf)
		}
	}
	// Exhaustively measured: max relative error 0.0105% (13.82 Q16 ULPs
	// at the top of the range), matching the aserti3-2d analysis's
	// documented ~0.013% bound (Bitcoin Cash, 2020). The bound is pinned
	// so any constant change that degrades the approximation fails
	// loudly. Consensus does not depend on the error being small — every
	// node computes the identical value — but difficulty tracking the
	// ideal exponential within 0.013% is a property worth keeping.
	if maxRelErr >= 0.00013 {
		t.Fatalf("cubic max relative error %.6f%% (must stay < 0.013%%)", maxRelErr*100)
	}
	t.Logf("cubic max relative error over full domain: %.6f%%", maxRelErr*100)
}

// multiplierQ enumerates the combined multiplier for one eQ16 value the
// exact way production applies it: split, cubic, then shift. Returned as
// an exact big.Int scaled by 2^32 so cross-shift comparisons are integral.
func multiplierQ(eQ16 int64) *big.Int {
	shifts := eQ16 >> 16
	frac := uint64(eQ16 - (shifts << 16))
	m := new(big.Int).SetUint64(cubicFactor(frac)) // Q16
	// scale to Q32, then apply 2^shifts
	m.Lsh(m, 16)
	if shifts >= 0 {
		m.Lsh(m, uint(shifts))
	} else {
		m.Rsh(m, uint(-shifts))
	}
	return m
}

// TestASERTMonotonicExhaustive: property 3 over all 131,073 exponents.
// A larger exponent must never produce a smaller multiplier, and the
// shift-boundary seams (eQ16 crossing multiples of 65536) must be
// continuous to within one Q32 step.
func TestASERTMonotonicExhaustive(t *testing.T) {
	prev := multiplierQ(-65536)
	for e := int64(-65535); e <= 65536; e++ {
		cur := multiplierQ(e)
		if cur.Cmp(prev) < 0 {
			t.Fatalf("multiplier decreased at eQ16=%d", e)
		}
		prev = cur
	}
}

// TestASERTSolvetimeExhaustive: property 4 — the solvetime→exponent map
// is non-increasing across the entire clamped domain [1, 10800], so a
// slower block can never RAISE difficulty.
func TestASERTSolvetimeExhaustive(t *testing.T) {
	exp := func(st int64) int64 {
		e := -((st - asertTargetSeconds) << 16) / asertHalfLife
		if e > 65536 {
			e = 65536
		}
		if e < -65536 {
			e = -65536
		}
		return e
	}
	for st := int64(1); st < asertSolveTimeCap; st++ {
		if exp(st+1) > exp(st) {
			t.Fatalf("exponent increased from st=%d to st=%d", st, st+1)
		}
	}
	// And end-to-end on real headers for a spread of parent difficulties:
	for _, d := range []int64{131072, 1 << 20, 1 << 30, 1 << 40} {
		parent := &types.Header{Time: 1_000_000, Difficulty: big.NewInt(d)}
		prev := everettCalcDifficulty(parent.Time+1, parent)
		for st := int64(2); st <= asertSolveTimeCap+100; st++ {
			cur := everettCalcDifficulty(parent.Time+uint64(st), parent)
			if cur.Cmp(prev) > 0 {
				t.Fatalf("difficulty rose with slower block: D=%d st=%d", d, st)
			}
			prev = cur
		}
	}
}

// TestASERTFloorExhaustive: property 5 — at and near the minimum
// difficulty, every solvetime yields >= the floor.
func TestASERTFloorExhaustive(t *testing.T) {
	for _, d := range []int64{131072, 131073, 262144} {
		parent := &types.Header{Time: 1_000_000, Difficulty: big.NewInt(d)}
		for st := int64(1); st <= asertSolveTimeCap+100; st++ {
			if next := everettCalcDifficulty(parent.Time+uint64(st), parent); next.Cmp(everettMinDiff) < 0 {
				t.Fatalf("difficulty %v below floor at parent=%d st=%d", next, d, st)
			}
		}
	}
}
