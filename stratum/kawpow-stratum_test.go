package main

import (
	"fmt"
	"math"
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

// Every legal -sharediff value must produce a well-formed 64-hex-char
// target and compact bits that a Bitcoin-style SetCompact accepts.
// sharediff=1 is the boundary: two256/1 = 2^256 is one past the largest
// 256-bit value, and unclamped it rendered 65 hex chars and bits
// 0x21010000, which SetCompact flags as overflow (decoding to 0, so the
// miner's search boundary was 0 and it could never find a share).
func TestShareTargetBoundaries(t *testing.T) {
	blockT, _ := new(big.Int).SetString(
		"00000000ffff0000000000000000000000000000000000000000000000000000", 16)
	for _, diff := range []int64{1, 2, 3, 255, 256, 8_000_000, math.MaxInt64} {
		st := shareTarget(diff, blockT)
		if st.Sign() <= 0 {
			t.Errorf("sharediff %d: target is not positive", diff)
		}
		if st.Cmp(maxTarget) > 0 {
			t.Errorf("sharediff %d: target %x exceeds 2^256-1", diff, st)
		}
		hexTarget := fmt.Sprintf("%064x", st)
		if len(hexTarget) != 64 {
			t.Errorf("sharediff %d: target renders to %d hex chars, want 64", diff, len(hexTarget))
		}
		bits := toCompact(st)
		if len(bits) != 8 {
			t.Errorf("sharediff %d: bits %q is not 8 hex chars", diff, bits)
		}
		// Bitcoin's arith_uint256::SetCompact overflow rule: reject when the
		// mantissa shifted by the size would exceed 256 bits.
		c, _ := new(big.Int).SetString(bits, 16)
		size := new(big.Int).Rsh(c, 24).Uint64()
		word := new(big.Int).And(c, big.NewInt(0x007fffff)).Uint64()
		if word != 0 && (size > 34 ||
			(word > 0xff && size > 33) ||
			(word > 0xffff && size > 32)) {
			t.Errorf("sharediff %d: bits %s overflow SetCompact (size=%d word=%#x)", diff, bits, size, word)
		}
		decoded := decodeCompact(bits)
		if decoded.Sign() <= 0 {
			t.Errorf("sharediff %d: bits %s decode to %x, a zero/negative search boundary", diff, bits, decoded)
		}
		if decoded.BitLen() > 256 {
			t.Errorf("sharediff %d: bits %s decode to %d bits, exceeds 256", diff, bits, decoded.BitLen())
		}
	}
	// diff <= 0 must pass the block target through untouched.
	if got := shareTarget(0, blockT); got.Cmp(blockT) != 0 {
		t.Errorf("sharediff 0: got %x, want block target %x", got, blockT)
	}
	// The diff=1 clamp specifically must land on 2^256-1 exactly.
	if got := shareTarget(1, blockT); got.Cmp(maxTarget) != 0 {
		t.Errorf("sharediff 1: got %x, want maxTarget %x", got, maxTarget)
	}
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
