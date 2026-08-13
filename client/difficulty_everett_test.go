package ethash

import (
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/core/types"
)

func hdr(diff int64, t uint64) *types.Header {
	return &types.Header{Number: big.NewInt(100), Time: t, Difficulty: big.NewInt(diff)}
}

func TestASERTEquilibrium(t *testing.T) {
	// st == target: difficulty exactly unchanged (factor 65536 >> 16).
	d := everettCalcDifficulty(1013, hdr(1_000_000_000, 1000))
	if d.Cmp(big.NewInt(1_000_000_000)) != 0 {
		t.Fatalf("equilibrium moved: %s", d)
	}
}

func TestASERTExactHalving(t *testing.T) {
	// st = 13 + 1800: exponent exactly -1, difficulty exactly halves.
	d := everettCalcDifficulty(1000+13+1800, hdr(1_000_000_000, 1000))
	if d.Cmp(big.NewInt(500_000_000)) != 0 {
		t.Fatalf("expected exact halving, got %s", d)
	}
}

func TestASERTFastBlockRaises(t *testing.T) {
	// st = 1: e = +436 in Q16, factor 65840, D*65840>>16 = 1004638671.
	d := everettCalcDifficulty(1001, hdr(1_000_000_000, 1000))
	if d.Cmp(big.NewInt(1_004_638_671)) != 0 {
		t.Fatalf("fast-block vector mismatch: %s", d)
	}
}

func TestASERTDoublingCap(t *testing.T) {
	// Even an instant block (st clamps to 1... exponent caps at +1): at most 2x.
	// Force cap: st=1 with tiny tau distance won't cap, so check the cap arm
	// via the clamped-late side and symmetry: st at solvetime cap (10813)
	// gives exactly one halving despite being 6 half-lives late.
	d := everettCalcDifficulty(1000+10813, hdr(1_000_000_000, 1000))
	if d.Cmp(big.NewInt(500_000_000)) != 0 {
		t.Fatalf("late cap should limit to one halving, got %s", d)
	}
}

func TestASERTMinimumFloor(t *testing.T) {
	d := everettCalcDifficulty(1000+1813, hdr(131_072, 1000))
	if d.Cmp(big.NewInt(131_072)) != 0 {
		t.Fatalf("fell below ethash minimum: %s", d)
	}
}

func TestASERTNegativeSolvetime(t *testing.T) {
	// time <= parent.Time clamps st to 1: behaves as fastest block, no panic.
	d := everettCalcDifficulty(999, hdr(1_000_000_000, 1000))
	if d.Cmp(big.NewInt(1_004_638_671)) != 0 {
		t.Fatalf("negative solvetime not clamped to st=1: %s", d)
	}
}

func TestASERTDeterminismRegression(t *testing.T) {
	// The LWMA bug: miner and batch-sync verifier disagreed because the DAA
	// read ancestors from the DB. ASERT is parent-only BY SIGNATURE: this
	// test pins the property by computing the same vector twice from bare
	// headers with no chain context at all.
	a := everettCalcDifficulty(2000+9, hdr(777_777_777, 2000))
	b := everettCalcDifficulty(2000+9, hdr(777_777_777, 2000))
	if a.Cmp(b) != 0 {
		t.Fatalf("nondeterministic: %s vs %s", a, b)
	}
	if a.Cmp(big.NewInt(777_777_777)) <= 0 {
		t.Fatalf("st=9 (fast) should raise difficulty, got %s", a)
	}
}
