# syntax=docker/dockerfile:1
# Everett node image: core-geth + the Everett consensus patches, built from
# source with the verification gates intact. The build stage replicates
# scripts/ci_prepare.sh EXACTLY (clone, modern-Go compat, patch copies,
# hooks — including KawPow — then the gates and the build); any failing
# gate fails the image build. KawPow activation is CHAIN-KEYED at runtime
# (Wheeler/mainnet: always on; dev chain 15537391: EVERETT_KAWPOW env
# selects; other chains: forced off — see client/kawpow_engine.go).
#
# Pinned versions: golang:1.23-bookworm (build), ubuntu:24.04 (runtime),
# core-geth pinned by COREGETH_COMMIT, the same pin ci_prepare.sh and
# join_wheeler_wsl.sh carry; scripts/check_consistency.py asserts the
# three never diverge.

FROM golang:1.23-bookworm AS build

WORKDIR /src

# core-geth needs git; apply_hook.py needs python3. make/gcc come with the
# golang image's buildpack-deps base.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git python3 \
 && rm -rf /var/lib/apt/lists/*

# Step 1: fetch upstream core-geth PINNED to the commit every Everett gate
# has been verified against, the same pin ci_prepare.sh uses. Override with
# --build-arg COREGETH_COMMIT=... to track a newer upstream deliberately
# (the consistency gate will then demand the scripts move too).
ARG COREGETH_COMMIT=10f1ea745cd89d72c398484a234cdc7fb29ecc32
RUN git init /src/core-geth \
 && git -C /src/core-geth remote add origin https://github.com/etclabscore/core-geth \
 && git -C /src/core-geth fetch --depth 1 origin "$COREGETH_COMMIT" \
 && git -C /src/core-geth checkout FETCH_HEAD

WORKDIR /src/core-geth

# Step 2: modern-Go compat fixes, verbatim from ci_prepare.sh (idempotent):
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
# and consensus/ethash/, exactly as ci_prepare.sh does).
COPY client/rewards_everett.go client/rewards_everett_test.go params/mutations/
COPY client/difficulty_everett.go client/difficulty_everett_test.go client/asert_enum_test.go consensus/ethash/
COPY client/kawpow_core.go client/kawpow_core_test.go consensus/ethash/
COPY scripts/apply_hook.py scripts/apply_daa_hook.py scripts/apply_kawpow_hooks.py /src/scripts/

# Step 4: apply the consensus hooks idempotently. kawpow_engine.go lands
# AFTER the KawPow hooks, mirroring ci_prepare.sh's order.
RUN python3 /src/scripts/apply_hook.py params/mutations/rewards.go \
 && python3 /src/scripts/apply_daa_hook.py consensus/ethash/consensus.go \
 && python3 /src/scripts/apply_kawpow_hooks.py consensus/ethash/consensus.go consensus/ethash/sealer.go eth/backend.go cmd/utils/flags.go
COPY client/kawpow_engine.go consensus/ethash/

# Step 5: verification gate 1 (schedule + DAA + KawPow). All suites MUST
# pass; a failure here aborts the image build.
RUN go test ./params/mutations/ -run TestEverett -v \
 && go test ./consensus/ethash/ -run TestASERT -v \
 && go test ./consensus/ethash/ -run TestKawPow -v -timeout 40m

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
# genesis-dev.json (chain ID 15537391) is the canonical devnet; the legacy
# genesis-devnet.json (15537393 — the RESERVED mainnet ID) ships only for
# compatibility with stacks already running it.
COPY genesis-dev.json genesis-devnet.json genesis-wheeler.json genesis.json /etc/everett/

# Gate-2 verification scripts, runnable inside the container (also from the
# host against 127.0.0.1:8545, per docker/README.md).
COPY scripts/verify_devnet.sh scripts/burn_audit.py /usr/local/bin/

COPY docker/run-node.sh /usr/local/bin/run-node.sh
RUN chmod +x /usr/local/bin/run-node.sh /usr/local/bin/verify_devnet.sh

ENTRYPOINT ["/usr/local/bin/run-node.sh"]
