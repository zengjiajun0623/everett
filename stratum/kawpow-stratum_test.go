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
		// The decoded value must equal the target truncated exactly the way
		// Bitcoin's compact encoding truncates: keep the top 3 significant
		// bytes — and when the leading byte has its high bit set (it would
		// collide with the sign bit), drop one more byte of precision. A
		// mantissa of ffffff therefore legitimately round-trips to ffff00;
		// demanding full top-24-bit fidelity is asserting a property the
		// encoding does not have.
		if want := bitcoinTruncate(target); got.Cmp(want) != 0 {
			t.Errorf("target %s: compact %s decodes to %x, want %x",
				hexTarget[:12], compact, got, want)
		}
		// And re-encoding the decoded value must be stable.
		if again := toCompact(got); again != compact {
			t.Errorf("target %s: re-encoding %s gives %s (not idempotent)",
				hexTarget[:12], compact, again)
		}
	}
}

// bitcoinTruncate reduces target to the precision Bitcoin compact bits can
// represent: top 3 significant bytes, minus one more byte when the leading
// byte's high bit is set (the sign-bit shift in the encoding).
func bitcoinTruncate(target *big.Int) *big.Int {
	byteLen := (target.BitLen() + 7) / 8
	keep := 3
	if byteLen > 0 {
		top := new(big.Int).Rsh(target, uint(8*(byteLen-1))).Uint64()
		if top&0x80 != 0 {
			keep = 2
		}
	}
	if byteLen <= keep {
		return new(big.Int).Set(target)
	}
	shift := uint(8 * (byteLen - keep))
	return new(big.Int).Lsh(new(big.Int).Rsh(target, shift), shift)
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
