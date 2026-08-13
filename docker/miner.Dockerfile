# syntax=docker/dockerfile:1
# Everett GPU miner image: ethminer built from source with CUDA 11.8
# (battle-tested for Ampere; CUDA 12 breaks the old ethminer build).
# RTX 3090 = sm_86; ethminer's legacy FindCUDA build targets it via its
# native COMPUTE flag (it ignores modern CMAKE_CUDA_ARCHITECTURES).
# Runtime stage is matched to the same CUDA 11.8 toolkit so the binary's
# dynamic CUDA runtime deps resolve; the GPU driver itself is supplied by
# nvidia-container-toolkit on the host (driver >= 520).
#
# Pinned versions: nvidia/cuda:11.8.0-devel-ubuntu22.04 (build),
# nvidia/cuda:11.8.0-runtime-ubuntu22.04 (runtime),
# ethminer v0.19.0 (ethereum-mining/ethminer; the upstream repo is archived
# and its last release tag is v0.19.0 - there is no v0.20.0 tag upstream,
# so v0.19.0 is the pinned "old ethminer" build).

FROM nvidia/cuda:11.8.0-devel-ubuntu22.04 AS build

# ethminer's CMake needs: git, cmake, a C++ compiler, the jsoncpp / leveldb /
# openssl development packages, and 7zip (Hunter extracts Boost from .7z).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ca-certificates curl cmake build-essential \
      libjsoncpp-dev libleveldb-dev libssl-dev p7zip-full \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch v0.19.0 \
      https://github.com/ethereum-mining/ethminer ethminer \
 && git -C ethminer submodule update --init --recursive

# ethminer's Hunter package manager fetches Boost 1.66.0 from the defunct
# dl.bintray.com. The first configure unpacks Hunter itself; we then repoint
# its Boost recipe at the official mirror archives.boost.io (byte-identical
# file, same SHA1 as Hunter's recipe) and reconfigure, so the download works.
# A failed first configure is expected here; the build aborts if the recipe
# does not end up pointing at the mirror.
WORKDIR /src/ethminer/build
RUN cmake .. -DCMAKE_BUILD_TYPE=Release \
      -DETHASHCUDA=ON \
      -DETHASHCL=OFF \
      -DETHSTRATUM=ON \
      -DETHDBUS=OFF \
      -DCOMPUTE=86 || true; \
    sed -i 's|https://dl.bintray.com/boostorg/release|https://archives.boost.io/release|' \
      /root/.hunter/_Base/Download/Hunter/0.23.112/*/Unpacked/cmake/projects/Boost/hunter.cmake; \
    grep -q 'archives.boost.io' /root/.hunter/_Base/Download/Hunter/0.23.112/*/Unpacked/cmake/projects/Boost/hunter.cmake
RUN cmake .. -DCMAKE_BUILD_TYPE=Release \
      -DETHASHCUDA=ON \
      -DETHASHCL=OFF \
      -DETHSTRATUM=ON \
      -DETHDBUS=OFF \
      -DCOMPUTE=86 \
 && cmake --build . --config Release -j "$(nproc)"

# ---- runtime stage ----
FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

# The CUDA backend is built STATIC into the binary (ldd: only libc/libm/
# libgcc_s); the GPU driver's libcuda comes from nvidia-container-toolkit.
COPY --from=build /src/ethminer/build/ethminer/ethminer /usr/local/bin/ethminer

# ethminer persists its ethash cache under $HOME/.ethash; the compose file
# bind-mounts /opt/docker/everett-miner there so the cache survives restarts.
ENV HOME=/root

ENTRYPOINT ["/usr/local/bin/ethminer"]
