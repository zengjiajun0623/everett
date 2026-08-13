// kawpow_core.go: the ProgPoW/KawPow mixing core for the Everett family.
// Drops into core-geth's consensus/ethash package (reuses its DAG machinery:
// generateDatasetItem, makeHasher, hashBytes/hashWords).
//
// Derived from the ProgPoW implementation in go-quai (consensus/progpow,
// LGPL-3.0, go-ethereum lineage), adapted for KawPow parameters. KawPow is
// ProgPoW 0.9.4 with Ravencoin's parameter set: period 3 and domain-tagged
// keccak-f800 padding: kept BIT-EXACT with Ravencoin so stock GPU miners
// (T-Rex, kawpowminer, lolMiner) work against Everett unmodified.
//
// GATE: nothing here touches consensus until TestKawPowVectors reproduces
// the Ravencoin reference vectors bit-for-bit. The vector values and the
// kawpowKeccakPad constants are filled from the G6 research memo; until
// then kawpowReady() is false and the engine refuses to use this path.

package ethash

import (
	"encoding/binary"
	"math/bits"

	"golang.org/x/crypto/sha3"
)

const (
	kawpowCacheBytes   = 16 * 1024
	kawpowCacheWords   = kawpowCacheBytes / 4
	kawpowLanes        = 16
	kawpowRegs         = 32
	kawpowDagLoads     = 4
	kawpowCntCache     = 11
	kawpowCntMath      = 18
	kawpowPeriodLength = 3 // KawPow: 3 (generic ProgPoW uses 10)
	kawpowCntDag       = 64
	kawpowMixBytes     = 256
)

// kawpowKeccakPad holds the 15 domain-separation words Ravencoin injects
// into keccak-f800 state positions 10..24. Filled from the verified
// research memo; zero means "not yet confirmed" and kawpowReady() gates on
// it. (These are the constants that make a KawPow share a KawPow share.)
var kawpowKeccakPad = [15]uint32{}

func kawpowReady() bool {
	for _, w := range kawpowKeccakPad {
		if w != 0 {
			return true
		}
	}
	return false
}

func kpRotl32(x uint32, n uint32) uint32 {
	return ((x) << (n % 32)) | ((x) >> (32 - (n % 32)))
}

func kpRotr32(x uint32, n uint32) uint32 {
	return ((x) >> (n % 32)) | ((x) << (32 - (n % 32)))
}

func kpLower32(in uint64) uint32  { return uint32(in) }
func kpHigher32(in uint64) uint32 { return uint32(in >> 32) }

var kawpowKeccakRNDC = [24]uint32{
	0x00000001, 0x00008082, 0x0000808a, 0x80008000, 0x0000808b, 0x80000001,
	0x80008081, 0x00008009, 0x0000008a, 0x00000088, 0x80008009, 0x8000000a,
	0x8000808b, 0x0000008b, 0x00008089, 0x00008003, 0x00008002, 0x00000080,
	0x0000800a, 0x8000000a, 0x80008081, 0x00008080, 0x80000001, 0x80008008}

func kawpowKeccakF800Round(st *[25]uint32, r int) {
	var rotc = [24]uint32{1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2,
		14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44}
	var piln = [24]uint32{10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24,
		4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1}
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
		bc[0], bc[1], bc[2], bc[3], bc[4] = st[j+0], st[j+1], st[j+2], st[j+3], st[j+4]
		st[j+0] ^= ^bc[1] & bc[2]
		st[j+1] ^= ^bc[2] & bc[3]
		st[j+2] ^= ^bc[3] & bc[4]
		st[j+3] ^= ^bc[4] & bc[0]
		st[j+4] ^= ^bc[0] & bc[1]
	}
	st[0] ^= kawpowKeccakRNDC[r]
}

// kawpowKeccakF800 runs the 22-round f800 permutation over a state seeded
// with the header hash (8 words), nonce (2 words), and 15 mix/pad words:
// KawPow's domain tag occupies the pad positions per the Ravencoin spec.
func kawpowKeccakF800(headerHash []byte, nonce uint64, mixOrPad [15]uint32) [25]uint32 {
	var st [25]uint32
	for i := 0; i < 8; i++ {
		st[i] = binary.LittleEndian.Uint32(headerHash[4*i:])
	}
	st[8] = kpLower32(nonce)
	st[9] = kpHigher32(nonce)
	for i := 0; i < 15; i++ {
		st[10+i] = mixOrPad[i]
	}
	for r := 0; r < 22; r++ {
		kawpowKeccakF800Round(&st, r)
	}
	return st
}

func kpFnv1a(h *uint32, d uint32) uint32 {
	*h = (*h ^ d) * uint32(0x1000193)
	return *h
}

type kpKiss99State struct {
	z, w, jsr, jcong uint32
}

func kpKiss99(st *kpKiss99State) uint32 {
	st.z = 36969*(st.z&65535) + (st.z >> 16)
	st.w = 18000*(st.w&65535) + (st.w >> 16)
	mwc := (st.z << 16) + st.w
	st.jsr ^= st.jsr << 17
	st.jsr ^= st.jsr >> 13
	st.jsr ^= st.jsr << 5
	st.jcong = 69069*st.jcong + 1234567
	return (mwc ^ st.jcong) + st.jsr
}

func kawpowFillMix(seed uint64, laneId uint32) [kawpowRegs]uint32 {
	var st kpKiss99State
	var mix [kawpowRegs]uint32
	fnvHash := uint32(0x811c9dc5)
	st.z = kpFnv1a(&fnvHash, kpLower32(seed))
	st.w = kpFnv1a(&fnvHash, kpHigher32(seed))
	st.jsr = kpFnv1a(&fnvHash, laneId)
	st.jcong = kpFnv1a(&fnvHash, laneId)
	for i := 0; i < kawpowRegs; i++ {
		mix[i] = kpKiss99(&st)
	}
	return mix
}

func kawpowMerge(a *uint32, b uint32, r uint32) {
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

func kawpowInit(seed uint64) (kpKiss99State, [kawpowRegs]uint32, [kawpowRegs]uint32) {
	var randState kpKiss99State
	fnvHash := uint32(0x811c9dc5)
	randState.z = kpFnv1a(&fnvHash, kpLower32(seed))
	randState.w = kpFnv1a(&fnvHash, kpHigher32(seed))
	randState.jsr = kpFnv1a(&fnvHash, kpLower32(seed))
	randState.jcong = kpFnv1a(&fnvHash, kpHigher32(seed))
	var dstSeq, srcSeq [kawpowRegs]uint32
	for i := uint32(0); i < kawpowRegs; i++ {
		dstSeq[i], srcSeq[i] = i, i
	}
	for i := uint32(kawpowRegs - 1); i > 0; i-- {
		j := kpKiss99(&randState) % (i + 1)
		dstSeq[i], dstSeq[j] = dstSeq[j], dstSeq[i]
		j = kpKiss99(&randState) % (i + 1)
		srcSeq[i], srcSeq[j] = srcSeq[j], srcSeq[i]
	}
	return randState, dstSeq, srcSeq
}

func kawpowMath(a, b, r uint32) uint32 {
	switch r % 11 {
	case 0:
		return a + b
	case 1:
		return a * b
	case 2:
		return kpHigher32(uint64(a) * uint64(b))
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
	lookup func(index uint32) []byte, cDag []uint32, datasetWords uint32) {
	gOffset := mix[loop%kawpowLanes][0] % (64 * datasetWords / (kawpowLanes * kawpowDagLoads))
	dagItem := make([]byte, 256)
	copy(dagItem, lookup((gOffset*kawpowLanes)*kawpowDagLoads))
	copy(dagItem[64:], lookup((gOffset*kawpowLanes)*kawpowDagLoads+16))
	copy(dagItem[128:], lookup((gOffset*kawpowLanes)*kawpowDagLoads+32))
	copy(dagItem[192:], lookup((gOffset*kawpowLanes)*kawpowDagLoads+48))

	for l := uint32(0); l < kawpowLanes; l++ {
		randState, dstSeq, srcSeq := kawpowInit(seed)
		srcCounter, dstCounter := uint32(0), uint32(0)
		for i := uint32(0); i < kawpowCntMath; i++ {
			if i < kawpowCntCache {
				src := srcSeq[srcCounter%kawpowRegs]
				srcCounter++
				offset := mix[l][src] % kawpowCacheWords
				data32 := cDag[offset]
				dst := dstSeq[dstCounter%kawpowRegs]
				dstCounter++
				r := kpKiss99(&randState)
				kawpowMerge(&mix[l][dst], data32, r)
			}
			srcRnd := kpKiss99(&randState) % (kawpowRegs * (kawpowRegs - 1))
			src1 := srcRnd % kawpowRegs
			src2 := srcRnd / kawpowRegs
			if src2 >= src1 {
				src2++
			}
			data32 := kawpowMath(mix[l][src1], mix[l][src2], kpKiss99(&randState))
			dst := dstSeq[dstCounter%kawpowRegs]
			dstCounter++
			kawpowMerge(&mix[l][dst], data32, kpKiss99(&randState))
		}
		index := ((l ^ loop) % kawpowLanes) * kawpowDagLoads
		var dataG [kawpowDagLoads]uint32
		for i := 0; i < kawpowDagLoads; i++ {
			dataG[i] = binary.LittleEndian.Uint32(dagItem[4*(index+uint32(i)):])
		}
		kawpowMerge(&mix[l][0], dataG[0], kpKiss99(&randState))
		for i := 1; i < kawpowDagLoads; i++ {
			dst := dstSeq[dstCounter%kawpowRegs]
			dstCounter++
			kawpowMerge(&mix[l][dst], dataG[i], kpKiss99(&randState))
		}
	}
}

// kawpowHash computes the KawPow (mixhash, finalhash) for a sealed header
// hash + nonce at the given block number. Flow per the Ravencoin spec:
// seed from domain-tagged f800, lanes mixed over the DAG, reduced, final
// f800 over (header, seed, mix). Exactness is judged solely by
// TestKawPowVectors against the Ravencoin reference vectors.
func kawpowHash(hash []byte, nonce uint64, size uint64, blockNumber uint64,
	cDag []uint32, lookup func(index uint32) []byte) ([]byte, []byte) {
	var mix [kawpowLanes][kawpowRegs]uint32
	var laneResults [kawpowLanes]uint32

	// Initial seed: keccak-f800 over header+nonce with the KawPow domain pad.
	st := kawpowKeccakF800(hash, nonce, kawpowKeccakPad)
	seed := (uint64(st[1]) << 32) | uint64(st[0])
	for lane := uint32(0); lane < kawpowLanes; lane++ {
		mix[lane] = kawpowFillMix(seed, lane)
	}
	period := blockNumber / kawpowPeriodLength
	for l := uint32(0); l < kawpowCntDag; l++ {
		kawpowLoop(period, l, &mix, lookup, cDag, uint32(size/kawpowMixBytes))
	}
	for lane := uint32(0); lane < kawpowLanes; lane++ {
		laneResults[lane] = 0x811c9dc5
		for i := 0; i < kawpowRegs; i++ {
			kpFnv1a(&laneResults[lane], mix[lane][i])
		}
	}
	var result [15]uint32
	for i := 0; i < 8; i++ {
		result[i] = 0x811c9dc5
	}
	for lane := uint32(0); lane < kawpowLanes; lane++ {
		kpFnv1a(&result[lane%8], laneResults[lane])
	}
	// Final: f800 over header hash with seed in the nonce slots and the mix
	// result (+pad tail) in positions 10..24 per KawPow.
	var finalPad [15]uint32
	copy(finalPad[:], result[:8])
	for i := 8; i < 15; i++ {
		finalPad[i] = kawpowKeccakPad[i]
	}
	fst := kawpowKeccakF800(hash, seed, finalPad)
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

// kawpowLight/kawpowFull mirror hashimotoLight/Full using the existing
// ethash cache/dataset machinery from this package.
func kawpowLight(size uint64, cache []uint32, hash []byte, nonce uint64, blockNumber uint64, cDag []uint32) ([]byte, []byte) {
	keccak512 := makeHasher(sha3.NewLegacyKeccak512())
	lookup := func(index uint32) []byte {
		return generateDatasetItem(cache, index/16, keccak512)
	}
	return kawpowHash(hash, nonce, size, blockNumber, cDag, lookup)
}

func kawpowFull(dataset []uint32, hash []byte, nonce uint64, blockNumber uint64) ([]byte, []byte) {
	lookup := func(index uint32) []byte {
		mix := make([]byte, hashBytes)
		for i := uint32(0); i < hashWords; i++ {
			binary.LittleEndian.PutUint32(mix[i*4:], dataset[index+i])
		}
		return mix
	}
	cDag := make([]uint32, kawpowCacheWords)
	for i := uint32(0); i < kawpowCacheWords; i += 2 {
		cDag[i+0] = dataset[i+0]
		cDag[i+1] = dataset[i+1]
	}
	return kawpowHash(hash, nonce, uint64(len(dataset))*4, blockNumber, cDag, lookup)
}
