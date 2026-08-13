# syntax=docker/dockerfile:1
# Everett node image: core-geth + the Everett consensus patches, built from
# source with the verification gates intact. The build stage replicates
# scripts/boot_devnet.sh's PREP EXACTLY (clone, modern-Go compat, patch
# copies, hooks, gates, build); any failing gate fails the image build.
#
# Pinned versions: golang:1.23-bookworm (build), ubuntu:24.04 (runtime),
# core-geth @ upstream default branch (depth-1 clone, same as boot_devnet.sh).

FROM golang:1.23-bookworm AS build

WORKDIR /src

# core-geth needs git; apply_hook.py needs python3. make/gcc come with the
# golang image's buildpack-deps base.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git python3 \
 && rm -rf /var/lib/apt/lists/*

# Step 1 of boot_devnet.sh: depth-1 clone of upstream core-geth.
RUN git clone --depth 1 https://github.com/etclabscore/core-geth /src/core-geth

WORKDIR /src/core-geth

# Step 2: modern-Go compat fixes, verbatim from boot_devnet.sh (idempotent):
# blst v0.3.11-* fails under Go 1.23+; bump to v0.3.17. fjl/memsize uses a
# runtime linkname removed in modern Go; excise it (same removal upstream
# geth made).
RUN set -eux; \
    if grep -q "blst v0.3.1[1-6]" go.mod; then \
        go get github.com/supranational/blst@v0.3.17; \
    fi; \
    sed -i.bak -e '/fjl\/memsize\/memsizeui/d' -e '/var Memsize memsizeui.Handler/d' \
      -e '/http.Handle("\/memsize\/"/d' internal/debug/flags.go && rm -f internal/debug/flags.go.bak; \
    sed -i.bak '/debug.Memsize.Add("node", stack)/d' cmd/geth/main.go && rm -f cmd/geth/main.go.bak

# Step 3: drop the Everett family files into the clone (params/mutations/
# and consensus/ethash/, exactly as boot_devnet.sh does).
COPY client/rewards_everett.go client/rewards_everett_test.go params/mutations/
COPY client/difficulty_everett.go client/difficulty_everett_test.go consensus/ethash/
COPY scripts/apply_hook.py scripts/apply_daa_hook.py /src/scripts/

# Step 4: apply the two consensus hooks idempotently.
RUN python3 /src/scripts/apply_hook.py params/mutations/rewards.go \
 && python3 /src/scripts/apply_daa_hook.py consensus/ethash/consensus.go

# Step 5: verification gate 1 (schedule + DAA). Both suites MUST pass;
# a failure here aborts the image build.
RUN go test ./params/mutations/ -run TestEverett -v \
 && go test ./consensus/ethash/ -run TestASERT -v

# Step 6: build geth.
RUN make geth

# ---- runtime stage ----
FROM ubuntu:24.04

# python3 is only for the in-container verification audit (gate 2);
# the node itself needs just ca-certificates and curl.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl python3 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/core-geth/build/bin/geth /usr/local/bin/geth

# Genesis files at /etc/everett/; GENESIS env selects one (see run-node.sh).
COPY genesis-devnet.json genesis-wheeler.json genesis.json /etc/everett/

# Gate-2 verification scripts, runnable inside the container (also from the
# host against 127.0.0.1:8545, per docker/README.md).
COPY scripts/verify_devnet.sh scripts/burn_audit.py /usr/local/bin/

COPY docker/run-node.sh /usr/local/bin/run-node.sh
RUN chmod +x /usr/local/bin/run-node.sh /usr/local/bin/verify_devnet.sh

ENTRYPOINT ["/usr/local/bin/run-node.sh"]
