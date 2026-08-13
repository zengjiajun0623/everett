package main

import (
	"math/big"
	"testing"
)

// toCompact must produce Bitcoin-style compact bits that round-trip back to
// (or just above) the target, since kawpowminer parses the notify "bits"
// field with SetCompact. We check the round trip rather than hardcoding,
// because the compact form is lossy in the low bits by design.
func TestToCompactRoundTrip(t *testing.T) {
	cases := []string{
		"0000800000000000000000000000000000000000000000000000000000000000",
		"00000000ffff0000000000000000000000000000000000000000000000000000",
		"0000000000000000000000000000000000000000000000000000000000ffffff",
		"00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
	}
	for _, hexTarget := range cases {
		target, _ := new(big.Int).SetString(hexTarget, 16)
		compact := toCompact(target)
		got := decodeCompact(compact)
		// The compact encoding keeps the top 3 significant bytes; the decoded
		// value must match the target in those top bytes (i.e. differ only in
		// the bits the encoding legitimately drops).
		if got.BitLen() != target.BitLen() {
			t.Errorf("target %s: compact %s decodes to bitlen %d, want %d",
				hexTarget[:12], compact, got.BitLen(), target.BitLen())
			continue
		}
		// Top 24 significant bits must be identical.
		shift := uint(target.BitLen())
		if shift > 24 {
			shift -= 24
		} else {
			shift = 0
		}
		a := new(big.Int).Rsh(target, shift)
		b := new(big.Int).Rsh(got, shift)
		if a.Cmp(b) != 0 {
			t.Errorf("target %s: top bits differ: %x vs %x", hexTarget[:12], a, b)
		}
	}
}

// decodeCompact is SetCompact: the inverse of toCompact, for the test only.
func decodeCompact(compact string) *big.Int {
	var c uint64
	for _, ch := range compact {
		c <<= 4
		switch {
		case ch >= '0' && ch <= '9':
			c |= uint64(ch - '0')
		case ch >= 'a' && ch <= 'f':
			c |= uint64(ch-'a') + 10
		}
	}
	size := c >> 24
	mantissa := c & 0x007fffff
	result := new(big.Int).SetUint64(mantissa)
	if size > 3 {
		result.Lsh(result, uint(8*(size-3)))
	} else {
		result.Rsh(result, uint(8*(3-size)))
	}
	return result
}

func TestStrip0x(t *testing.T) {
	for in, want := range map[string]string{
		"0xdeadbeef": "deadbeef",
		"deadbeef":   "deadbeef",
		"0x":         "",
	} {
		if got := strip0x(in); got != want {
			t.Errorf("strip0x(%q)=%q want %q", in, got, want)
		}
	}
}
