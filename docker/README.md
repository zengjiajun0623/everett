# Everett Docker / Portainer deployment

Run an Everett node plus the `kawpow-stratum` sidecar with Docker: the node
does no hashing itself (`MINER_THREADS=0`) and serves work through the
sidecar on port 3333, where any stock KawPow miner (kawpowminer, T-Rex)
connects. That is the default stack. The bundled ethminer container
(ethash-only, `eth_getWork`/`eth_submitWork` over RPC) is legacy and starts
only under the `ethash-legacy` compose profile. Deploy with either the CLI
or Portainer's GUI; the same `docker-compose.yml` serves both.

The node image is built from source inside Docker and runs **the
verification gates as part of the build**: the build aborts if
`TestEverett` (Article III schedule), `TestASERT` (DAA, incl. the
exhaustive fixed-point enumeration), or `TestKawPow` fails. No
precompiled binaries anywhere. No consensus code, genesis file, or hook
script is modified by this packaging.

```
docker/
├── node.Dockerfile      # core-geth + Everett patches, gates, build
├── stratum.Dockerfile   # kawpow-stratum sidecar (KawPow miners connect here)
├── miner.Dockerfile     # ethminer v0.19.0 + CUDA 11.8, sm_86; ETHASH ONLY
├── run-node.sh          # container entrypoint (geth init + run)
└── docker-compose.yml   # node + stratum; ethminer only under ethash-legacy
```

KawPow networks (Wheeler v2, mainnet): mine via the **stratum** service.
Point kawpowminer/T-Rex at `stratum+tcp://worker@<host>:3333`. Payouts go
to the node's `ETHERBASE`; the stratum username is logging only. The
ethminer image is ethash-only legacy plumbing behind the `ethash-legacy`
compose profile.

## Pinned versions

| Component | Version | Notes |
|---|---|---|
| Build base (node) | `golang:1.23-bookworm` | replicates `ci_prepare.sh` (the canonical prep, KawPow included) |
| Runtime base (node) | `ubuntu:24.04` | + ca-certificates, curl, python3 |
| core-geth | commit `10f1ea74…` (pinned via `COREGETH_COMMIT` build arg) | the tree every Everett gate was verified against; blst v0.3.17 + memsize excision applied in-build |
| Build base (miner) | `nvidia/cuda:11.8.0-devel-ubuntu22.04` | CUDA 11.8 is battle-tested for Ampere; CUDA 12 breaks the old ethminer build |
| Runtime base (miner) | `nvidia/cuda:11.8.0-runtime-ubuntu22.04` | matched to the 11.8 toolkit |
| ethminer | `v0.19.0` (`ethereum-mining/ethminer`) | the upstream repo is archived; its last release tag is v0.19.0. **There is no v0.20.0 tag upstream**, so v0.19.0 is the pinned "old ethminer" build |
| CUDA arch | `sm_86` via `-DCOMPUTE=86` | ethminer's legacy FindCUDA build ignores `CMAKE_CUDA_ARCHITECTURES`; `COMPUTE` is its native flag. RTX 3090 = sm_86 |
| Host driver | >= 520 | 3090 on Ubuntu 24.04: 545+ recommended (580 verified in testing) |

## Prerequisites (host)

```bash
# Ubuntu's own packages (docker-compose-v2 provides `docker compose`);
# docker-compose-plugin only exists in Docker Inc's apt repo, not Ubuntu's.
sudo apt update && sudo apt install -y docker.io docker-compose-v2
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
# (Ubuntu 24.04 repo line; see https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
```

Check GPU and driver:

```bash
nvidia-smi                 # driver >= 520; your GPU must be sm_86 (3090) or edit COMPUTE in miner.Dockerfile
docker run --rm --gpus all nvidia/cuda:11.8.0-runtime-ubuntu22.04 nvidia-smi
```

Data volumes (create once; containers run as root, so this is optional:
Docker creates them on first start):

```bash
sudo mkdir -p /opt/docker/everett-node /opt/docker/everett-miner
```

## Build the images

### CLI

```bash
git clone https://github.com/zengjiajun0623/everett && cd everett
docker build -f docker/node.Dockerfile    -t everett-node:local .
docker build -f docker/stratum.Dockerfile -t everett-stratum:local .
# legacy, ethash-legacy profile only:
docker build -f docker/miner.Dockerfile   -t everett-miner:local .
```

The node build runs `TestEverett` + `TestASERT` + `TestKawPow` and **fails
the build** if any suite fails. Expect 5-20 min (node) and under a minute
(stratum: a small Go build with its own vet + test gate). The miner image
is 15-30 min (CUDA toolchain pull + ethminer compile + Boost via Hunter)
and the default stack never runs it; build it only if you want the
`ethash-legacy` profile.

### Portainer GUI

1. **Images → Build a new image**.
2. *Repository URL:* `https://github.com/zengjiajun0623/everett` (or your
   fork), *Reference:* `main` (or `docker-support` while in review).
3. *Dockerfile path:* `docker/node.Dockerfile`; name `everett-node:local`.
4. Repeat for `docker/stratum.Dockerfile` → `everett-stratum:local`.
5. Only for the `ethash-legacy` profile: repeat for
   `docker/miner.Dockerfile` → `everett-miner:local`.

## Deploy the stack

The stack defaults to **devnet** (`genesis-dev.json`, chain ID 15537391,
`--nodiscover`, throwaway etherbase) running **KawPow** (`EVERETT_KAWPOW=1`),
with the node mining zero CPU threads and serving work through the stratum
sidecar to any KawPow miner. The ethash-only ethminer service starts only
with `--profile ethash-legacy` (plus `EVERETT_KAWPOW` unset).

### Portainer GUI (recommended)

**Git-repo mode** (builds from the repo; one click):

1. **Stacks → Add stack → Git repository**.
2. *Repository URL:* `https://github.com/zengjiajun0623/everett`
   (*Reference:* `main`, or the `docker-support` branch while in review).
3. *Compose path:* `docker/docker-compose.yml`.
4. Name it `everett`, click **Build and deploy**. Portainer clones the repo,
   builds the node and stratum images (the profile-gated miner service is
   not built), and starts the stack. Done.

**Custom-paste mode** (images already built):

1. Build the node and stratum images via *Images → Build a new image* as
   above (or CLI); add the miner image only for the `ethash-legacy`
   profile.
2. **Stacks → Add stack → Web editor**, paste the contents of
   `docker/docker-compose.yml`, name it `everett`.
3. Click **Deploy the stack** (not "Build and deploy": the images are
   already local; pasted stacks have no repo context for `build.context`).

### CLI equivalent

```bash
docker compose -f docker/docker-compose.yml up -d --build
```

## Environment variables

Defaults below are the **image** (entrypoint) defaults; where the compose
stack sets its own value, that is listed too.

| Variable | Image default | Compose stack | Purpose |
|---|---|---|---|
| `GENESIS` | `genesis-dev.json` | same | `genesis-dev.json` (devnet, 15537391), `genesis-wheeler.json` (Wheeler testnet), `genesis.json` (mainnet: reserved, do not use casually), `genesis-devnet.json` (legacy devnet: carries the reserved mainnet chain ID, and its old ethash datadirs do NOT work under current images; see Safety notes), or an absolute path |
| `MINE` | `0` (sync-only) | `1` | `1` = enable mining (`--mine`); `0` = sync-only node |
| `ETHERBASE` | unset | throwaway `0x1000…0001` | Coinbase address. **Required when `MINE=1`** (the entrypoint hard-fails without it). Devnet/Wheeler coins are valueless; use your own EOA to keep anything |
| `MINER_THREADS` | `0` | `0` | Node CPU mining threads. `0` = serve `eth_getWork` only; the GPU miner does the hashing. `>0` also mines on CPU. (The entrypoint translates `0` into geth's `--miner.threads -1`: core-geth reads a plain `0` as "use every core", so passing it through would silently CPU-mine KawPow on the whole box and build a ~1 GiB DAG.) |
| `EVERETT_KAWPOW` | unset (ethash on the dev chain) | `1` | Algorithm selector, honored **only on the dev chain 15537391**: `1` = KawPow, unset = ethash. Activation is otherwise chain-keyed in the client: Wheeler (15537392) and mainnet (15537393) run KawPow from genesis whatever this says, and every other chain ID is forced off. Set it (as the compose stack does) for the stratum + KawPow-miner path on devnet; leave it unset for the `ethash-legacy` ethminer profile. Getting it wrong on devnet is quiet: the sidecar acks KawPow shares while the node rejects every one and no block ever lands |
| `NETWORKID` | auto from `GENESIS` | auto | 15537391 (devnet), 15537392 (Wheeler), 15537393 (mainnet/legacy devnet). For an absolute-path genesis the entrypoint reads `chainId` out of the file itself and fails if it cannot; set this explicitly only to override |
| `BOOTNODE` | unset | unset | Set an `enode://…@host:30303` to join a public network (Wheeler). Unset = `--nodiscover` (private devnet) |
| `HTTP_VHOSTS` | `node,localhost,127.0.0.1` | same | Allowed HTTP `Host` headers. The default covers the in-stack clients that dial `http://node:8545` (the stratum sidecar, and the legacy miner) plus host-localhost curls, without reopening the DNS-rebinding hole a `*` wildcard would |
| `DATADIR` | `/data` | `/data` | Node datadir (bind-mounted volume) |

Wheeler mode (live testnet, chain ID 15537392; bootnode from README).
**Wheeler runs KawPow since its v2 re-genesis (2026-08-13)**: the node
image (post-`ci_prepare` parity) validates and serves KawPow work
automatically. Activation is keyed to the chain ID, no env var needed.
Note the bundled **ethminer image is ethash-only and cannot mine
Wheeler v2**: run the node with `MINE=1` + `MINER_THREADS=0` to serve
work, and point a KawPow miner (kawpowminer, T-Rex) at a
`kawpow-stratum` sidecar (the compose stack's `stratum` service, port 3333) or at the node's getwork URL. Wheeler v1 datadirs are incompatible: wipe
the volume and re-init.

```yaml
    environment:
      GENESIS: genesis-wheeler.json
      ETHERBASE: 0xYourAddress
      BOOTNODE: "enode://ad614b8c…@71.183.54.11:30303"
    ports:
      - "127.0.0.1:8545:8545"
      - "30303:30303/tcp"     # public P2P: 0.0.0.0; private: 127.0.0.1
      - "30303:30303/udp"
```

## Volume layout

| Host path | Container path | Holds |
|---|---|---|
| `/opt/docker/everett-node` | `/data` | chaindata, keystore, geth.ipc |
| `/opt/docker/everett-miner` | `/root/.ethash` | ethash cache for the `ethash-legacy` miner only (survives restarts; no full DAG rebuild). Unused by the default stack: KawPow miners build their own DAG on the GPU host |

## Verification

On the host (RPC is published to localhost only):

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  http://127.0.0.1:8545
# 0xed14ef (15537391 devnet) or 0xed14f0 (15537392 Wheeler)

git clone https://github.com/zengjiajun0623/everett   # once
cd everett && scripts/verify_devnet.sh                # gate 2 (devnet; for Wheeler: EXPECT_CHAINID=15537392 scripts/verify_devnet.sh)
```

`verify_devnet.sh` recomputes the entire Article III schedule in Python
(independent of the Go code) and demands the miner's balance match wei for
wei, including uncles and the 1559 burn. On a healthy devnet stack it ends
with `PASS … delta=0`. Inside the container (`-f` is needed unless you run
from `docker/`): `docker compose -f docker/docker-compose.yml exec node
/usr/local/bin/verify_devnet.sh` (the image ships the audit scripts).

Mining health on the default stack (node + stratum):

```bash
docker logs -f everett-stratum
# "kawpow-stratum listening on 0.0.0.0:3333, node http://node:8545"
# "new job <id> height=… target=…"      the sidecar is pulling work
# "miner connected from <ip> (extranonce …)"
# "BLOCK: job <id> height=… nonce=… from <worker>"   the node accepted a block
```

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_getWork","params":[]}' \
  http://127.0.0.1:8545   # [headerhash, seedhash, boundary, height] = serving work
```

Portainer: the stack page shows `everett-node` (healthy) and
`everett-stratum`; open each container's *Logs* tab.

Under the `ethash-legacy` profile only, the ethminer container has its own
log (`docker logs -f everett-miner`: **Accepted** shares, Epoch/Difficulty
lines). On the default stack there is no `everett-miner` container, and
that command answers `No such container`.

Transport note: `eth_getWork` polling is fine for devnet and early Wheeler,
but soak testing on this repo showed it churns (miner suspend/resume on
every new head) as difficulty and block cadence rise. The stratum sidecar
in [`stratum/`](../stratum/README.md) is the long-run transport and ships as the
compose `stratum` service.

## Safety notes

- **RPC is localhost-only on the host** (`127.0.0.1:8545:8545`). Inside the
  container it binds `0.0.0.0:8545` so the miner can reach it over the
  private `everett-int` network; do not publish it beyond localhost.
- The default `ETHERBASE` is a throwaway address. On Wheeler, use your own
  EOA if you want to keep anything; devnet coins are valueless by design.
- `genesis.json` (mainnet, chain ID 15537393) is **reserved** for the
  Article VIII launch ceremony. The entrypoint refuses to start any
  genesis carrying that chain ID unless `EVERETT_ART_VIII_CEREMONY=1` is
  set (the guard keys on the genesis content, not the filename); that
  flag belongs to the ceremony, not to experiments. The stack defaults
  to `genesis-dev.json` (chain ID 15537391). The legacy
  `genesis-devnet.json` also carries the reserved
  15537393 and ships for identification/compat only. Chain-keyed
  activation forces KawPow ON for that chain ID, so legacy ethash devnet
  datadirs are NOT usable with current images: wipe the volume and
  re-init on `genesis-dev.json`, or stay on a pre-flip build. New
  devnets should never use it.
- No secrets: nothing in the repo or the images requires credentials.
- Everything builds from source; a failed gate fails the build. There are
  no prebuilt binaries to trust.

## Known build quirks (why the Dockerfiles look the way they do)

- **Hunter/Bintray**: ethminer 0.19.0's Hunter package manager downloads
  Boost 1.66.0 from `dl.bintray.com`, which is dead. The first `cmake`
  configure unpacks Hunter; the Dockerfile then repoints its Boost recipe
  at `archives.boost.io` (byte-identical file, same SHA1) and reconfigures.
  A failed first configure is expected; the build aborts if the recipe is
  not repointed.
- **Old gencode list**: the CUDA kernel flags hardcode `compute_30` (removed
  in CUDA 11). `-DCOMPUTE=86` emits only `sm_86`.
- **`v0.19.0`**: the archived upstream has no `v0.20.0` tag; v0.19.0 is the
  last release and the pinned "old ethminer" build.
