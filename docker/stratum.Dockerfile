# syntax=docker/dockerfile:1
# Everett kawpow-stratum sidecar: bridges stock KawPow miners
# (kawpowminer, T-Rex — connect with stratum+tcp://) to a node's
# eth_getWork/eth_submitWork API. Consensus-free by design; built from
# source like everything else in this repo.
#
# Pinned versions: golang:1.23-alpine (build), alpine:3.20 (runtime).

FROM golang:1.23-alpine AS build
WORKDIR /src
COPY stratum/ .
RUN go vet . && go test . && go build -o /kawpow-stratum .

FROM alpine:3.20
COPY --from=build /kawpow-stratum /usr/local/bin/kawpow-stratum
# -node/-listen/-sharediff come from the compose service command.
ENTRYPOINT ["/usr/local/bin/kawpow-stratum"]
