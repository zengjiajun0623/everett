// kawpow_core.go: the KawPow (ProgPoW 0.9.4 + Ravencoin params) mixing core
// for the Everett family. Drops into core-geth's consensus/ethash package,
// reusing its DAG machinery (generateCache, makeHasher, fnv, hashBytes...).
//
// Derived from the ProgPoW implementation in go-quai (consensus/progpow,
// LGPL-3.0, go-ethereum lineage), adapted to KawPow per G6_P1_NOTES.md.
// KawPow deltas from generic ProgPoW: PERIOD 3 (not 10), epoch 7500, a
// 1 GiB-init DAG schedule, 512 dataset parents, and the "RAVENCOINKAWPOW"
// keccak-f800 padding. Kept BIT-EXACT with Ravencoin so stock GPU miners
// (T-Rex, kawpowminer) work against Everett unmodified.
//
// GATE: nothing here touches consensus until TestKawPow* reproduce the
// Ravencoin reference vectors bit-for-bit (see kawpow_core_test.go).

package ethash

import (
	"encoding/binary"
	"math/big"
	"math/bits"

	"golang.org/x/crypto/sha3"
)

const (
	kawpowEpochLength   = 7500
	kawpowCacheInit     = 1 << 24 // 16 MiB
	kawpowCacheGrowth   = 1 << 17 // 128 KiB / epoch
	kawpowDatasetInit   = 1 << 30 // 1 GiB
	kawpowDatasetGrowth = 1 << 23 // 8 MiB / epoch
	kawpowDatasetParents = 512

	kawpowCacheBytes = 16 * 1024
	kawpowCacheWords = kawpowCacheBytes / 4
	kawpowLanes      = 16
	kawpowRegs       = 32
	kawpowDagLoads   = 4
	kawpowCntCache   = 11
	kawpowCntMath    = 18
	kawpowPeriod     = 3
	kawpowCntDag     = 64
	kawpowMixBytes   = 256 // ProgPoW hash2048 granularity for the loop
	kawpowItemBytes  = 128 // prime-search granularity (ethash mixBytes)
)

// ravencoinKawpow: "RAVENCOINKAWPOW", one ASCII char per uint32, injected
// into keccak-f800 state positions 10..24 (initial) and 16..24 (final).
var ravencoinKawpow = [15]uint32{
	0x72, 0x41, 0x56, 0x45, 0x4E, 0x43, 0x4F, 0x49, 0x4E, 0x4B, 0x41, 0x57, 0x50, 0x4F, 0x57,
}

// --- DAG size schedule (KawPow) ---------------------------------------------

func kawpowCacheSize(epoch uint64) uint64 {
	size := uint64(kawpowCacheInit) + uint64(kawpowCacheGrowth)*epoch - hashBytes
	for !new(big.Int).SetUint64(size / hashBytes).ProbablyPrime(1) {
		size -= 2 * hashBytes
	}
	return size
}

func kawpowDatasetSize(epoch uint64) uint64 {
	size := uint64(kawpowDatasetInit) + uint64(kawpowDatasetGrowth)*epoch - kawpowItemBytes
	for !new(big.Int).SetUint64(size / kawpowItemBytes).ProbablyPrime(1) {
		size -= 2 * kawpowItemBytes
	}
	return size
}


// kawpowSeedHash: keccak256 iterated `epoch` times over 32 zero bytes.
// core-geth's seedHash() re-derives the epoch from a block using the
// hardcoded 30000-block ethash epoch, so KawPow needs its own.
func kawpowSeedHash(epoch uint64) []byte {
	seed := make([]byte, 32)
	keccak256 := makeHasher(sha3.NewLegacyKeccak256())
	for i := uint64(0); i < epoch; i++ {
		keccak256(seed, seed)
	}
	return seed
}

// kawpowGenerateDatasetItem is generateDatasetItem with 512 parents (the
// ProgPoW 0.9.4 DAG tweak) instead of ethash's 256.
func kawpowGenerateDatasetItem(cache []uint32, index uint32, keccak512 hasher) []byte {
	rows := uint32(len(cache) / hashWords)
	mix := make([]byte, hashBytes)
	binary.LittleEndian.PutUint32(mix, cache[(index%rows)*hashWords]^index)
	for i := 1; i < hashWords; i++ {
		binary.LittleEndian.PutUint32(mix[i*4:], cache[(index%rows)*hashWords+uint32(i)])
	}
	keccak512(mix, mix)
	intMix := make([]uint32, hashWords)
	for i := 0; i < len(intMix); i++ {
		intMix[i] = binary.LittleEndian.Uint32(mix[i*4:])
	}
	for i := uint32(0); i < kawpowDatasetParents; i++ {
		parent := fnv(index^i, intMix[i%16]) % rows
		fnvHash(intMix, cache[parent*hashWords:])
	}
	for i, val := range intMix {
		binary.LittleEndian.PutUint32(mix[i*4:], val)
	}
	keccak512(mix, mix)
	return mix
}

// kawpowGenerateCDag builds the 16 KiB L1 cache = first 4096 words of the
// dataset (256 items).
func kawpowGenerateCDag(cache []uint32) []uint32 {
	keccak512 := makeHasher(sha3.NewLegacyKeccak512())
	cDag := make([]uint32, kawpowCacheWords)
	for i := 0; i < kawpowCacheWords/16; i++ {
		item := kawpowGenerateDatasetItem(cache, uint32(i), keccak512)
		for j := 0; j < 16; j++ {
			cDag[i*16+j] = binary.LittleEndian.Uint32(item[j*4:])
		}
	}
	return cDag
}

// --- keccak-f800 -------------------------------------------------------------

func kpRotl32(x, n uint32) uint32 { return (x << (n % 32)) | (x >> (32 - (n % 32))) }
func kpRotr32(x, n uint32) uint32 { return (x >> (n % 32)) | (x << (32 - (n % 32))) }
func kpLo(in uint64) uint32       { return uint32(in) }
func kpHi(in uint64) uint32       { return uint32(in >> 32) }

var kawpowRNDC = [24]uint32{
	0x00000001, 0x00008082, 0x0000808a, 0x80008000, 0x0000808b, 0x80000001,
	0x80008081, 0x00008009, 0x0000008a, 0x00000088, 0x80008009, 0x8000000a,
	0x8000808b, 0x0000008b, 0x00008089, 0x00008003, 0x00008002, 0x00000080,
	0x0000800a, 0x8000000a, 0x80008081, 0x00008080, 0x80000001, 0x80008008}

func kawpowF800Round(st *[25]uint32, r int) {
	rotc := [24]uint32{1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44}
	piln := [24]uint32{10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1}
	var bc [5]uint32
	for i := 0; i < 5; i++ {
		bc[i] = st[i] ^ st[i+5] ^ st[i+10] ^ st[i+15] ^ st[i+20]
	}
	for i := 0; i < 5; i++ {
		t := bc[(i+4)%5] ^ kpRotl32(bc[(i+1)%5], 1)
		for j := 0; j < 25; j += 5 {
			st[j+i] ^= t
		}
	}
	t := st[1]
	for i, j := range piln {
		bc[0] = st[j]
		st[j] = kpRotl32(t, rotc[i])
		t = bc[0]
	}
	for j := 0; j < 25; j += 5 {
		bc[0], bc[1], bc[2], bc[3], bc[4] = st[j], st[j+1], st[j+2], st[j+3], st[j+4]
		st[j+0] ^= ^bc[1] & bc[2]
		st[j+1] ^= ^bc[2] & bc[3]
		st[j+2] ^= ^bc[3] & bc[4]
		st[j+3] ^= ^bc[4] & bc[0]
		st[j+4] ^= ^bc[0] & bc[1]
	}
	st[0] ^= kawpowRNDC[r]
}

func kawpowF800(st *[25]uint32) {
	for r := 0; r < 22; r++ {
		kawpowF800Round(st, r)
	}
}

// --- RNG and mix -------------------------------------------------------------

func kpFnv1a(h *uint32, d uint32) uint32 { *h = (*h ^ d) * 0x1000193; return *h }

type kpKiss struct{ z, w, jsr, jcong uint32 }

func kpKiss99(st *kpKiss) uint32 {
	st.z = 36969*(st.z&65535) + (st.z >> 16)
	st.w = 18000*(st.w&65535) + (st.w >> 16)
	mwc := (st.z << 16) + st.w
	st.jsr ^= st.jsr << 17
	st.jsr ^= st.jsr >> 13
	st.jsr ^= st.jsr << 5
	st.jcong = 69069*st.jcong + 1234567
	return (mwc ^ st.jcong) + st.jsr
}

func kawpowFillMix(seed uint64, lane uint32) [kawpowRegs]uint32 {
	var st kpKiss
	var mix [kawpowRegs]uint32
	h := uint32(0x811c9dc5)
	st.z = kpFnv1a(&h, kpLo(seed))
	st.w = kpFnv1a(&h, kpHi(seed))
	st.jsr = kpFnv1a(&h, lane)
	st.jcong = kpFnv1a(&h, lane)
	for i := 0; i < kawpowRegs; i++ {
		mix[i] = kpKiss99(&st)
	}
	return mix
}

func kawpowMerge(a *uint32, b, r uint32) {
	switch r % 4 {
	case 0:
		*a = (*a * 33) + b
	case 1:
		*a = (*a ^ b) * 33
	case 2:
		*a = kpRotl32(*a, ((r>>16)%31)+1) ^ b
	default:
		*a = kpRotr32(*a, ((r>>16)%31)+1) ^ b
	}
}

func kawpowInit(seed uint64) (kpKiss, [kawpowRegs]uint32, [kawpowRegs]uint32) {
	var rs kpKiss
	h := uint32(0x811c9dc5)
	rs.z = kpFnv1a(&h, kpLo(seed))
	rs.w = kpFnv1a(&h, kpHi(seed))
	rs.jsr = kpFnv1a(&h, kpLo(seed))
	rs.jcong = kpFnv1a(&h, kpHi(seed))
	var dst, src [kawpowRegs]uint32
	for i := uint32(0); i < kawpowRegs; i++ {
		dst[i], src[i] = i, i
	}
	for i := uint32(kawpowRegs - 1); i > 0; i-- {
		j := kpKiss99(&rs) % (i + 1)
		dst[i], dst[j] = dst[j], dst[i]
		j = kpKiss99(&rs) % (i + 1)
		src[i], src[j] = src[j], src[i]
	}
	return rs, dst, src
}

func kawpowMath(a, b, r uint32) uint32 {
	switch r % 11 {
	case 0:
		return a + b
	case 1:
		return a * b
	case 2:
		return kpHi(uint64(a) * uint64(b))
	case 3:
		if a < b {
			return a
		}
		return b
	case 4:
		return kpRotl32(a, b)
	case 5:
		return kpRotr32(a, b)
	case 6:
		return a & b
	case 7:
		return a | b
	case 8:
		return a ^ b
	case 9:
		return uint32(bits.LeadingZeros32(a) + bits.LeadingZeros32(b))
	case 10:
		return uint32(bits.OnesCount32(a) + bits.OnesCount32(b))
	default:
		return 0
	}
}

func kawpowLoop(seed uint64, loop uint32, mix *[kawpowLanes][kawpowRegs]uint32,
	lookup func(index uint32) []byte, cDag []uint32, datasetItems uint32) {
	gOffset := mix[loop%kawpowLanes][0] % (64 * datasetItems / (kawpowLanes * kawpowDagLoads))
	dagItem := make([]byte, 256)
	copy(dagItem, lookup((gOffset*kawpowLanes)*kawpowDagLoads))
	copy(dagItem[64:], lookup((gOffset*kawpowLanes)*kawpowDagLoads+16))
	copy(dagItem[128:], lookup((gOffset*kawpowLanes)*kawpowDagLoads+32))
	copy(dagItem[192:], lookup((gOffset*kawpowLanes)*kawpowDagLoads+48))

	for l := uint32(0); l < kawpowLanes; l++ {
		rs, dst, src := kawpowInit(seed)
		sc, dc := uint32(0), uint32(0)
		for i := uint32(0); i < kawpowCntMath; i++ {
			if i < kawpowCntCache {
				s := src[sc%kawpowRegs]
				sc++
				off := mix[l][s] % kawpowCacheWords
				d := dst[dc%kawpowRegs]
				dc++
				kawpowMerge(&mix[l][d], cDag[off], kpKiss99(&rs))
			}
			srcRnd := kpKiss99(&rs) % (kawpowRegs * (kawpowRegs - 1))
			s1 := srcRnd % kawpowRegs
			s2 := srcRnd / kawpowRegs
			if s2 >= s1 {
				s2++
			}
			data32 := kawpowMath(mix[l][s1], mix[l][s2], kpKiss99(&rs))
			d := dst[dc%kawpowRegs]
			dc++
			kawpowMerge(&mix[l][d], data32, kpKiss99(&rs))
		}
		index := ((l ^ loop) % kawpowLanes) * kawpowDagLoads
		var dg [kawpowDagLoads]uint32
		for i := 0; i < kawpowDagLoads; i++ {
			dg[i] = binary.LittleEndian.Uint32(dagItem[4*(index+uint32(i)):])
		}
		kawpowMerge(&mix[l][0], dg[0], kpKiss99(&rs))
		for i := 1; i < kawpowDagLoads; i++ {
			d := dst[dc%kawpowRegs]
			dc++
			kawpowMerge(&mix[l][d], dg[i], kpKiss99(&rs))
		}
	}
}

// kawpowHash computes (mixHash, finalHash) per the Ravencoin KawPow flow.
func kawpowHash(hash []byte, nonce uint64, size uint64, blockNumber uint64,
	cDag []uint32, lookup func(index uint32) []byte) ([]byte, []byte) {
	// Initial keccak-f800: header(8) + nonce(2) + RAVENCOINKAWPOW(15).
	var ist [25]uint32
	for i := 0; i < 8; i++ {
		ist[i] = binary.LittleEndian.Uint32(hash[4*i:])
	}
	ist[8] = kpLo(nonce)
	ist[9] = kpHi(nonce)
	for i := 0; i < 15; i++ {
		ist[10+i] = ravencoinKawpow[i]
	}
	kawpowF800(&ist)
	seed := uint64(ist[0]) | uint64(ist[1])<<32

	var mix [kawpowLanes][kawpowRegs]uint32
	for lane := uint32(0); lane < kawpowLanes; lane++ {
		mix[lane] = kawpowFillMix(seed, lane)
	}
	period := blockNumber / kawpowPeriod
	for l := uint32(0); l < kawpowCntDag; l++ {
		kawpowLoop(period, l, &mix, lookup, cDag, uint32(size/kawpowMixBytes))
	}

	var laneResults [kawpowLanes]uint32
	for lane := uint32(0); lane < kawpowLanes; lane++ {
		laneResults[lane] = 0x811c9dc5
		for i := 0; i < kawpowRegs; i++ {
			kpFnv1a(&laneResults[lane], mix[lane][i])
		}
	}
	var result [8]uint32
	for i := 0; i < 8; i++ {
		result[i] = 0x811c9dc5
	}
	for lane := uint32(0); lane < kawpowLanes; lane++ {
		kpFnv1a(&result[lane%8], laneResults[lane])
	}

	// Final keccak-f800: initial-output(8) + mix(8) + RAVENCOINKAWPOW[0..8](9).
	var fst [25]uint32
	for i := 0; i < 8; i++ {
		fst[i] = ist[i]
	}
	for i := 0; i < 8; i++ {
		fst[8+i] = result[i]
	}
	for i := 0; i < 9; i++ {
		fst[16+i] = ravencoinKawpow[i]
	}
	kawpowF800(&fst)

	finalHash := make([]byte, 32)
	for i := 0; i < 8; i++ {
		binary.LittleEndian.PutUint32(finalHash[i*4:], fst[i])
	}
	mixHash := make([]byte, 32)
	for i := 0; i < 8; i++ {
		binary.LittleEndian.PutUint32(mixHash[i*4:], result[i])
	}
	return mixHash, finalHash
}

// kawpowLight computes KawPow from a light cache + cDag (verification path).
func kawpowLight(size uint64, cache []uint32, hash []byte, nonce uint64, blockNumber uint64, cDag []uint32) ([]byte, []byte) {
	keccak512 := makeHasher(sha3.NewLegacyKeccak512())
	lookup := func(index uint32) []byte {
		return kawpowGenerateDatasetItem(cache, index/16, keccak512)
	}
	return kawpowHash(hash, nonce, size, blockNumber, cDag, lookup)
}
