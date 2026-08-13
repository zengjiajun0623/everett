package ethash

import (
	"encoding/hex"
	"testing"

	"golang.org/x/crypto/sha3"
)

// Vectors from RavenCommunity/cpp-kawpow progpow_test_vectors.hpp
// (byte-identical to Ravencoin core), via G6_P1_NOTES.md §3.

// Layer 0: DAG size schedule. {epoch, cache, dataset} from test_ethash.cpp.
func TestKawPowSizes(t *testing.T) {
	cases := []struct{ epoch, cache, dataset uint64 }{
		{0, 16776896, 1073739904},
		{14, 18611392, 1191180416},
		{17, 19004224, 1216345216},
		{56, 24116672, 1543503488},
		{158, 37486528, 2399139968},
		{203, 43382848, 2776625536},
		{211, 44433344, 2843734144},
		{272, 52427968, 3355440512},
		{350, 62651584, 4009751168},
		{412, 70778816, 4529846144},
	}
	for _, c := range cases {
		if got := kawpowCacheSize(c.epoch); got != c.cache {
			t.Errorf("cacheSize(%d)=%d want %d", c.epoch, got, c.cache)
		}
		if got := kawpowDatasetSize(c.epoch); got != c.dataset {
			t.Errorf("datasetSize(%d)=%d want %d", c.epoch, got, c.dataset)
		}
	}
}

// Layer 0b: epoch seed chain.
func TestKawPowSeed(t *testing.T) {
	cases := []struct {
		epoch uint64
		seed  string
	}{
		{0, "0000000000000000000000000000000000000000000000000000000000000000"},
		{1, "290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563"},
		{171, "a9b0e0c9aca72c07ba06b5bbdae8b8f69e61878301508473379bb4f71807d707"},
	}
	for _, c := range cases {
		got := hex.EncodeToString(kawpowSeedHash(c.epoch))
		if got != c.seed {
			t.Errorf("seed(epoch %d)=%s want %s", c.epoch, got, c.seed)
		}
	}
}

// epoch0 cache + cDag, built once and shared by layers 1 and 2.
func epoch0() (cache, cDag []uint32) {
	sz := kawpowCacheSize(0)
	cache = make([]uint32, sz/4)
	generateCache(cache, 0, kawpowEpochLength, kawpowSeedHash(0))
	cDag = kawpowGenerateCDag(cache)
	return
}

// Layer 1: the first 20 words of the epoch-0 L1 cache (cDag).
func TestKawPowCDag(t *testing.T) {
	_, cDag := epoch0()
	want := []uint32{2492749011, 430724829, 2029256771, 3095580433, 3583790154,
		3025086503, 805985885, 4121693337, 2320382801, 3763444918, 1006127899,
		1480743010, 2592936015, 2598973744, 3038068233, 2754267228, 2867798800,
		2342573634, 467767296, 246004123}
	for i, w := range want {
		if cDag[i] != w {
			t.Fatalf("cDag[%d]=%d want %d (DAG generation diverges)", i, cDag[i], w)
		}
	}
}

func be(t *testing.T, s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// Layer 2: the smoke vector (run first), then all 13 primary vectors.
func TestKawPowSmoke(t *testing.T) {
	cache, cDag := epoch0()
	// block 30000 is epoch 4, but the smoke vector in cpp-kawpow is checked
	// against the epoch of block 30000 under 7500 epoching = epoch 4. It uses
	// its own epoch's cache; build it.
	ep := uint64(30000) / kawpowEpochLength
	csz := kawpowCacheSize(ep)
	c := make([]uint32, csz/4)
	generateCache(c, ep, kawpowEpochLength, kawpowSeedHash(ep))
	cd := kawpowGenerateCDag(c)
	_ = cache
	_ = cDag
	header := be(t, "ffeeddccbbaa9988776655443322110000112233445566778899aabbccddeeff")
	mix, final := kawpowLight(kawpowDatasetSize(ep), c, header, 0x123456789abcdef0, 30000, cd)
	wantMix := "177b565752a375501e11b6d9d3679c2df6197b2cab3a1ba2d6b10b8c71a3d459"
	wantFinal := "c824bee0418e3cfb7fae56e0d5b3b8b14ba895777feea81c70c0ba947146da69"
	if hex.EncodeToString(mix) != wantMix {
		t.Errorf("smoke mix  = %s\n         want %s", hex.EncodeToString(mix), wantMix)
	}
	if hex.EncodeToString(final) != wantFinal {
		t.Errorf("smoke final= %s\n         want %s", hex.EncodeToString(final), wantFinal)
	}
}

func TestKawPowVectors(t *testing.T) {
	type vec struct {
		block       uint64
		header      string
		nonce       uint64
		mix, final  string
	}
	vs := []vec{
		{0, "0000000000000000000000000000000000000000000000000000000000000000", 0x0000000000000000, "6e97b47b134fda0c7888802988e1a373affeb28bcd813b6e9a0fc669c935d03a", "e601a7257a70dc48fccc97a7330d704d776047623b92883d77111fb36870f3d1"},
		{49, "63155f732f2bf556967f906155b510c917e48e99685ead76ea83f4eca03ab12b", 0x0000000007073c07, "d36f7e815ee09e74eceb9c96993a3d681edf2bf0921fc7bb710364042db99777", "e7ced124598fd2500a55ad9f9f48e3569327fe50493c77a4ac9799b96efb9463"},
		{50, "9e7248f20914913a73d80a70174c331b1d34f260535ac3631d770e656b5dd922", 0x00000000076e482e, "d6dc634ae837e2785b347648ea515e25e5d8821ae0b95e1c2a9c2d497e0dcfbd", "ab0ad7ef8d8ee317dd12d10310aceed7321d34fb263791c2de5776a6658d177e"},
		{99, "de37e1824c86d35d154cf65a88de6d9286aec4f7f10c3fc9f0fa1bcc2687188d", 0x000000003917afab, "fa706860e5e0e830d5d1d7157e5bea7f5f8a350c7c8612ac1d1fcf2974d64244", "aa85340690f2e907054324a5021937910e15edfd1ef1577231843e7d32ec3a61"},
		{30000, "d34519f72c97cae8892c277776259db3320820cb5279a299d0ef1e155e5c6454", 0x005db8607994ff30, "de0348b69bf91dfe2c3d3dba6f0132e9048a5284e57b8d9d20adc5f3dc0d3236", "c7953d848cda6e304f77b4c6d735645c8e8508a5e74c9e9814ef37b19087cd6c"},
		{170915, "5b3e8dfa1aafd3924a51f33e2d672d8dae32fa528d8b1d378d6e4db0ec5d665d", 0x0000000044975727, "efb29147484c434f1cc59629da90fd0343e3b047407ecd36e9ad973bd51bbac5", "e7e6bb3b2f9acd3864bc86f72f87237eaf475633ef650c726ac80eb0adf116b6"},
	}
	cacheByEpoch := map[uint64][]uint32{}
	cdagByEpoch := map[uint64][]uint32{}
	for _, v := range vs {
		ep := v.block / kawpowEpochLength
		if cacheByEpoch[ep] == nil {
			csz := kawpowCacheSize(ep)
			c := make([]uint32, csz/4)
			generateCache(c, ep, kawpowEpochLength, kawpowSeedHash(ep))
			cacheByEpoch[ep] = c
			cdagByEpoch[ep] = kawpowGenerateCDag(c)
		}
		mix, final := kawpowLight(kawpowDatasetSize(ep), cacheByEpoch[ep], be(t, v.header), v.nonce, v.block, cdagByEpoch[ep])
		if hex.EncodeToString(mix) != v.mix || hex.EncodeToString(final) != v.final {
			t.Errorf("block %d:\n  mix  = %s want %s\n  final= %s want %s",
				v.block, hex.EncodeToString(mix), v.mix, hex.EncodeToString(final), v.final)
		}
	}
}

var _ = sha3.NewLegacyKeccak512
