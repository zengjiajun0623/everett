package mutations

import (
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/core/types"
	"github.com/holiman/uint256"
)

func TestEverettDecayFirstEras(t *testing.T) {
	want := []uint64{
		1_800_000_000_000_000_000, // D(0)
		1_787_400_000_000_000_000, // D(1) exact
		1_774_888_200_000_000_000, // D(2) exact
	}
	for era, w := range want {
		if got := everettDecay(uint64(era)); got.Uint64() != w {
			t.Fatalf("era %d: got %s want %d", era, got, w)
		}
	}
}

func TestEverettHalfLife(t *testing.T) {
	// ~4.07y half-life: D should sit near 0.9e18 at era 98 and decay monotonically.
	d98, d99 := everettDecay(98), everettDecay(99)
	if d98.Uint64() < 880_000_000_000_000_000 || d98.Uint64() > 920_000_000_000_000_000 {
		t.Fatalf("D(98) out of half-life neighborhood: %s", d98)
	}
	if d99.Cmp(d98) >= 0 {
		t.Fatalf("decay not monotonic: D(99)=%s D(98)=%s", d99, d98)
	}
}

func TestEverettBlockReward(t *testing.T) {
	cases := []struct {
		block uint64
		want  uint64
	}{
		{0, 0},
		{1, 21_505_376_344_086},              // 2e18 * 1 / 93000, floored
		{46_500, 1_000_000_000_000_000_000},  // exact midpoint of slow start
		{93_000, 2_000_000_000_000_000_000},  // full schedule
		{100_000, 1_987_400_000_000_000_000}, // tail + D(1)
	}
	for _, c := range cases {
		got := EverettBlockReward(new(big.Int).SetUint64(c.block))
		if got.Uint64() != c.want {
			t.Fatalf("block %d: got %s want %d", c.block, got, c.want)
		}
	}
}

func TestEverettTailFloor(t *testing.T) {
	// Era 5000 (~208 years): decay is dust; reward must sit at/just above the
	// tail and never below it.
	r := EverettBlockReward(new(big.Int).SetUint64(500_000_000))
	if r.Cmp(everettTail) < 0 {
		t.Fatalf("reward fell below tail: %s", r)
	}
	ceiling := new(uint256.Int).Add(everettTail, uint256.NewInt(1_000_000))
	if r.Cmp(ceiling) > 0 {
		t.Fatalf("decay failed to vanish by era 5000: %s", r)
	}
}

func TestEverettUncles(t *testing.T) {
	// Block 200_000: R = tail + D(2) = 1_974_888_200_000_000_000, cleanly /32.
	header := &types.Header{Number: big.NewInt(200_000)}
	uncle := &types.Header{Number: big.NewInt(199_999)}
	reward, uncleRewards := everettRewards(header, []*types.Header{uncle})

	wantPer32 := uint64(61_715_256_250_000_000)
	if len(uncleRewards) != 1 || uncleRewards[0].Uint64() != wantPer32 {
		t.Fatalf("uncle reward: got %v want %d", uncleRewards, wantPer32)
	}
	wantWinner := uint64(1_974_888_200_000_000_000 + 61_715_256_250_000_000)
	if reward.Uint64() != wantWinner {
		t.Fatalf("winner reward: got %s want %d", reward, wantWinner)
	}
}
