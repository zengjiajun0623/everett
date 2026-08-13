// kawpow_engine.go wires the KawPow core into core-geth's consensus paths.
//
// Design note: an Everett node NEVER builds the multi-gigabyte DAG. GPU
// miners generate it themselves (that is how Ravencoin works), so the node
// keeps only the ~16 MiB light cache plus the 16 KiB cDag per epoch and
// verifies with kawpowLight. Node-side CPU mining uses the same light path:
// slow, but it exists only as a devnet/bootstrap fallback. Real hashrate
// arrives over the work API from T-Rex/kawpowminer.
//
// ACTIVATION (v1, deliberately explicit): the EVERETT_KAWPOW=1 environment
// variable. Consensus rules must never depend on local environment on a
// public network, so before Wheeler or mainnet runs KawPow this must move
// into the chain config (tracked in GENESIS_SPEC 5a.5). The env gate exists
// so the algorithm can be proven end-to-end on an isolated devnet first.

package ethash

import (
	"encoding/binary"
	"math/big"
	"os"
	"runtime"
	"sync"

	"github.com/ethereum/go-ethereum/log"
	"golang.org/x/crypto/sha3"
)

var kawpowEnabled = os.Getenv("EVERETT_KAWPOW") == "1"

// KawPowEnabled reports whether this node runs the KawPow proof of work.
func KawPowEnabled() bool { return kawpowEnabled }

type kawpowEpoch struct {
	epoch       uint64
	cache       []uint32
	cDag        []uint32
	datasetSize uint64
}

var (
	kpMu     sync.Mutex
	kpEpochs = map[uint64]*kawpowEpoch{}
)

// kawpowEpochFor returns (building if needed) the light cache and cDag for
// the epoch containing `number`. Two epochs are retained: the current one
// and its predecessor, so verification across an epoch boundary never
// rebuilds. Cache construction for epoch 0 is ~16 MiB and takes a second.
func kawpowEpochFor(number uint64) *kawpowEpoch {
	epoch := number / kawpowEpochLength
	kpMu.Lock()
	defer kpMu.Unlock()
	if e, ok := kpEpochs[epoch]; ok {
		return e
	}
	size := kawpowCacheSize(epoch)
	cache := make([]uint32, size/4)
	generateCache(cache, epoch, kawpowEpochLength, kawpowSeedHash(epoch))
	e := &kawpowEpoch{
		epoch:       epoch,
		cache:       cache,
		cDag:        kawpowGenerateCDag(cache),
		datasetSize: kawpowDatasetSize(epoch),
	}
	kpEpochs[epoch] = e
	for k := range kpEpochs {
		if k+1 < epoch {
			delete(kpEpochs, k)
		}
	}
	return e
}

// kawpowCompute returns (mixDigest, result) for a sealing attempt.
func kawpowCompute(hash []byte, nonce uint64, number uint64) ([]byte, []byte) {
	e := kawpowEpochFor(number)
	return kawpowLight(e.datasetSize, e.cache, hash, nonce, number, e.cDag)
}

// kawpowVerify checks a sealed header: the mix digest must match and the
// final hash must meet the difficulty target. Mirrors the ethash checks so
// the two paths stay behaviorally identical apart from the hash function.
func kawpowVerify(sealHash []byte, nonce uint64, number uint64, mixDigest []byte, difficulty *big.Int) (bool, bool) {
	digest, result := kawpowCompute(sealHash, nonce, number)
	mixOK := true
	for i := range digest {
		if digest[i] != mixDigest[i] {
			mixOK = false
			break
		}
	}
	target := new(big.Int).Div(two256, difficulty)
	powOK := new(big.Int).SetBytes(result).Cmp(target) <= 0
	return mixOK, powOK
}

// --- full dataset (node-side mining only) -----------------------------------
//
// Verification never needs this. It exists so a node can CPU-mine its own
// chain (bootstrap/devnet); GPU miners build their own DAG from the seed
// hash and never ask the node for one.

func kawpowGenerateDataset(dest []uint32, cache []uint32) {
	threads := runtime.NumCPU()
	size := uint64(len(dest)) * 4
	var pend sync.WaitGroup
	pend.Add(threads)
	batch := uint32((size + hashBytes*uint64(threads) - 1) / (hashBytes * uint64(threads)))
	for i := 0; i < threads; i++ {
		go func(id uint32) {
			defer pend.Done()
			keccak512 := makeHasher(sha3.NewLegacyKeccak512())
			first, limit := id*batch, (id+1)*batch
			if limit > uint32(size/hashBytes) {
				limit = uint32(size / hashBytes)
			}
			for index := first; index < limit; index++ {
				item := kawpowGenerateDatasetItem(cache, index, keccak512)
				copy(dest[index*hashWords:], asUint32Slice(item))
			}
		}(uint32(i))
	}
	pend.Wait()
}

func asUint32Slice(b []byte) []uint32 {
	out := make([]uint32, len(b)/4)
	for i := range out {
		out[i] = binary.LittleEndian.Uint32(b[i*4:])
	}
	return out
}

// kawpowFullFor returns the mining dataset for `number`, building it once.
//
// It guards the multi-gigabyte build with its OWN mutex (kpDatasetMu), not
// kpMu, so building the mining DAG (minutes) never blocks block
// verification (which only takes kpMu, via kawpowEpochFor). The two locks
// are never held at the same time: kawpowEpochFor acquires and releases
// kpMu before kpDatasetMu is taken, and kawpowEpoch fields are immutable
// after creation, so reading e.cache/e.datasetSize outside kpMu is safe.
func kawpowFullFor(number uint64) []uint32 {
	e := kawpowEpochFor(number)
	kpDatasetMu.Lock()
	defer kpDatasetMu.Unlock()
	if kpDataset != nil && kpDatasetEpoch == e.epoch {
		return kpDataset
	}
	log.Info("Generating KawPow mining DAG", "epoch", e.epoch, "size", e.datasetSize)
	ds := make([]uint32, e.datasetSize/4)
	kawpowGenerateDataset(ds, e.cache)
	kpDataset, kpDatasetEpoch = ds, e.epoch
	log.Info("KawPow mining DAG ready", "epoch", e.epoch)
	return ds
}

var (
	kpDatasetMu    sync.Mutex // guards the mining DAG build, separate from
	                          // kpMu so it never blocks verification
	kpDataset      []uint32
	kpDatasetEpoch uint64 = ^uint64(0)
)

// kawpowComputeFull is the mining-speed hash (DAG lookups instead of
// per-item regeneration). Same result as kawpowCompute by construction.
func kawpowComputeFull(hash []byte, nonce uint64, number uint64) ([]byte, []byte) {
	e := kawpowEpochFor(number)
	ds := kawpowFullFor(number)
	lookup := func(index uint32) []byte {
		mix := make([]byte, hashBytes)
		for i := uint32(0); i < hashWords; i++ {
			binary.LittleEndian.PutUint32(mix[i*4:], ds[index+i])
		}
		return mix
	}
	return kawpowHash(hash, nonce, e.datasetSize, number, e.cDag, lookup)
}
