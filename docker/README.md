# Everett Docker / Portainer deployment

Run an Everett node plus an external GPU miner (ethminer over RPC,
`eth_getWork`/`eth_submitWork`) with Docker. Deploy with either the CLI or
Portainer's GUI — the same `docker-compose.yml` serves both.

The node image is built from source inside Docker and runs **both
verification gates as part of the build**: the build aborts if
`TestEverett` (Article III schedule) or `TestASERT` (DAA) fails. No
precompiled binaries anywhere. No consensus code, genesis file, or hook
script is modified by this packaging.

```
docker/
├── node.Dockerfile      # core-geth + Everett patches, gates, build
├── miner.Dockerfile     # ethminer v0.19.0 + CUDA 11.8, sm_86
├── run-node.sh          # container entrypoint (geth init + run)
└── docker-compose.yml   # node + miner stack (CLI and Portainer)
```

## Pinned versions

| Component | Version | Notes |
|---|---|---|
| Build base (node) | `golang:1.23-bookworm` | replicates `ci_prepare.sh` (the canonical prep, KawPow included) |
| Runtime base (node) | `ubuntu:24.04` | + ca-certificates, curl, python3 |
| core-geth | commit `10f1ea74…` (pinned via `COREGETH_COMMIT` build arg) | the tree every Everett gate was verified against; blst v0.3.17 + memsize excision applied in-build |
| Build base (miner) | `nvidia/cuda:11.8.0-devel-ubuntu22.04` | CUDA 11.8 is battle-tested for Ampere; CUDA 12 breaks the old ethminer build |
| Runtime base (miner) | `nvidia/cuda:11.8.0-runtime-ubuntu22.04` | matched to the 11.8 toolkit |
| ethminer | `v0.19.0` (`ethereum-mining/ethminer`) | the upstream repo is archived; its last release tag is v0.19.0 — **there is no v0.20.0 tag upstream**, so v0.19.0 is the pinned "old ethminer" build |
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

Data volumes (create once; containers run as root, so this is optional —
Docker creates them on first start):

```bash
sudo mkdir -p /opt/docker/everett-node /opt/docker/everett-miner
```

## Build the images

### CLI

```bash
git clone https://github.com/zengjiajun0623/everett && cd everett
docker build -f docker/node.Dockerfile  -t everett-node:local .
docker build -f docker/miner.Dockerfile -t everett-miner:local .
```

The node build runs `TestEverett` + `TestASERT` + `TestKawPow` and **fails
the build** if any suite fails. Expect 5-20 min (node) and 15-30 min
(miner: CUDA toolchain pull + ethminer compile + Boost via Hunter).

### Portainer GUI

1. **Images → Build a new image**.
2. *Repository URL:* `https://github.com/zengjiajun0623/everett` (or your
   fork), *Reference:* `main` (or `docker-support` while in review).
3. *Dockerfile path:* `docker/node.Dockerfile`; name `everett-node:local`.
4. Repeat for `docker/miner.Dockerfile` → `everett-miner:local`.

## Deploy the stack

The stack defaults to **devnet** (`genesis-dev.json`, chain ID 15537391,
`--nodiscover`, throwaway etherbase, GPU miner only — the node mines zero
CPU threads and just serves work to ethminer).

### Portainer GUI (recommended)

**Git-repo mode** (builds from the repo; one click):

1. **Stacks → Add stack → Git repository**.
2. *Repository URL:* `https://github.com/zengjiajun0623/everett`
   (*Reference:* `main`, or the `docker-support` branch while in review).
3. *Compose path:* `docker/docker-compose.yml`.
4. Name it `everett`, click **Build and deploy**. Portainer clones the repo,
   builds both images, and starts the stack. Done.

**Custom-paste mode** (images already built):

1. Build both images via *Images → Build a new image* as above (or CLI).
2. **Stacks → Add stack → Web editor**, paste the contents of
   `docker/docker-compose.yml`, name it `everett`.
3. Click **Deploy the stack** (not "Build and deploy" — the images are
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
| `GENESIS` | `genesis-dev.json` | same | `genesis-dev.json` (devnet, 15537391), `genesis-wheeler.json` (Wheeler testnet), `genesis.json` (mainnet — reserved, do not use casually), `genesis-devnet.json` (legacy devnet — carries the reserved mainnet chain ID; only for stacks already running it), or an absolute path |
| `MINE` | `0` (sync-only) | `1` | `1` = enable mining (`--mine`); `0` = sync-only node |
| `ETHERBASE` | unset | throwaway `0x1000…0001` | Coinbase address. **Required when `MINE=1`** (the entrypoint hard-fails without it). Devnet/Wheeler coins are valueless; use your own EOA to keep anything |
| `MINER_THREADS` | `0` | `0` | Node CPU mining threads. `0` = serve `eth_getWork` only; the GPU miner does the hashing. `>0` also mines on CPU |
| `NETWORKID` | auto from `GENESIS` | auto | 15537391 (devnet, also the fallback for absolute-path genesis — set explicitly if yours differs), 15537392 (Wheeler), 15537393 (mainnet/legacy devnet) |
| `BOOTNODE` | unset | unset | Set an `enode://…@host:30303` to join a public network (Wheeler). Unset = `--nodiscover` (private devnet) |
| `HTTP_VHOSTS` | `node,localhost,127.0.0.1` | same | Allowed HTTP `Host` headers. The default covers the compose miner and host-localhost curls without reopening the DNS-rebinding hole a `*` wildcard would |
| `DATADIR` | `/data` | `/data` | Node datadir (bind-mounted volume) |

Wheeler mode (live testnet, chain ID 15537392 — bootnode from README):

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
| `/opt/docker/everett-miner` | `/root/.ethash` | ethash cache (survives restarts; no full DAG rebuild) |

## Verification

On the host (RPC is published to localhost only):

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  http://127.0.0.1:8545
# 0xed14ef (15537391 devnet) or 0xed14f0 (15537392 Wheeler)

git clone https://github.com/zengjiajun0623/everett   # once
cd everett && scripts/verify_devnet.sh                # gate 2, from the host
```

`verify_devnet.sh` recomputes the entire Article III schedule in Python
(independent of the Go code) and demands the miner's balance match wei for
wei, including uncles and the 1559 burn. On a healthy devnet stack it ends
with `PASS … delta=0`. Inside the container (`-f` is needed unless you run
from `docker/`): `docker compose -f docker/docker-compose.yml exec node
/usr/local/bin/verify_devnet.sh` (the image ships the audit scripts).

Miner health:

```bash
docker logs -f everett-miner        # **Accepted** shares, Epoch 0 Difficulty…
```

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_getWork","params":[]}' \
  http://127.0.0.1:8545   # [headerhash, seedhash, boundary, height] = serving work
```

Portainer: the stack page shows `everett-node` (healthy) and
`everett-miner`; open each container's *Logs* tab.

Transport note: `eth_getWork` polling is fine for devnet and early Wheeler,
but soak testing on this repo showed it churns (miner suspend/resume on
every new head) as difficulty and block cadence rise. The stratum sidecar
in [`stratum/`](../stratum/README.md) is the long-run transport; a
containerized variant is planned.

## Safety notes

- **RPC is localhost-only on the host** (`127.0.0.1:8545:8545`). Inside the
  container it binds `0.0.0.0:8545` so the miner can reach it over the
  private `everett-int` network — do not publish it beyond localhost.
- The default `ETHERBASE` is a throwaway address. On Wheeler, use your own
  EOA if you want to keep anything; devnet coins are valueless by design.
- `genesis.json` (mainnet, chain ID 15537393) is **reserved** for the
  Article VIII launch ceremony. The entrypoint refuses to start it unless
  `EVERETT_ART_VIII_CEREMONY=1` is set — that flag belongs to the ceremony,
  not to experiments. The stack defaults to `genesis-dev.json` (chain ID
  15537391). The legacy `genesis-devnet.json` also carries the reserved
  15537393 — it ships only so stacks already running it keep working; new
  devnets should not use it.
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
