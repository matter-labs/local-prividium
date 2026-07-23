FROM ghcr.io/foundry-rs/foundry:v1.5.1@sha256:3a70bfa9bd2c732a767bb60d12c8770b40e8f9b6cca28efc4b12b1be81c7f28e AS foundry
FROM node:22-slim@sha256:6c74791e557ce11fc957704f6d4fe134a7bc8d6f5ca4403205b2966bd488f6b3 AS node

FROM rust:bookworm@sha256:77fac8b98f9f46062bb680b6d25d5bcaabfc400143952ebc572e924bcbedc3fa AS builder
ARG ZK_DEPLOYER_COMMIT
ARG PROTOCOL_COMMIT

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates clang git libssl-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*
COPY --from=foundry /usr/local/bin/forge /usr/local/bin/forge
COPY --from=foundry /usr/local/bin/cast /usr/local/bin/cast
COPY --from=node /usr/local /usr/local
COPY --from=node /opt/yarn-v1.22.22 /opt/yarn-v1.22.22
RUN test "$(yarn --version)" = "1.22.22"

RUN git init /src/integration \
    && git -C /src/integration remote add origin https://github.com/matter-labs/zksync-os-integration-tests.git \
    && git -C /src/integration fetch --depth 1 origin "${ZK_DEPLOYER_COMMIT}" \
    && git -C /src/integration checkout --detach FETCH_HEAD \
    && test "$(git -C /src/integration rev-parse HEAD)" = "${ZK_DEPLOYER_COMMIT}"
COPY zk-deployer-sepolia.patch /tmp/zk-deployer-sepolia.patch
RUN git -C /src/integration apply --check /tmp/zk-deployer-sepolia.patch \
    && git -C /src/integration apply /tmp/zk-deployer-sepolia.patch
RUN git init /src/era-contracts \
    && git -C /src/era-contracts remote add origin https://github.com/matter-labs/era-contracts.git \
    && git -C /src/era-contracts fetch --depth 1 origin "${PROTOCOL_COMMIT}" \
    && git -C /src/era-contracts checkout --detach FETCH_HEAD \
    && test "$(git -C /src/era-contracts rev-parse HEAD)" = "${PROTOCOL_COMMIT}"

ENV PROTOCOL_CONTRACTS_ROOT=/src/era-contracts
WORKDIR /src/integration
RUN rustup toolchain install nightly-2026-01-22 --profile minimal \
    && cargo +nightly-2026-01-22 build --locked --release -p zk-deployer
RUN git -C /src/era-contracts submodule update --init --recursive --depth 1
RUN ./target/release/zk-deployer build-contracts

FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818
ARG ZK_DEPLOYER_COMMIT
ARG PROTOCOL_COMMIT

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates curl jq libssl3 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=foundry /usr/local/bin/forge /usr/local/bin/forge
COPY --from=foundry /usr/local/bin/cast /usr/local/bin/cast
COPY --from=node /usr/local /usr/local
COPY --from=node /opt/yarn-v1.22.22 /opt/yarn-v1.22.22
COPY --from=builder /src/integration/target/release/zk-deployer /usr/local/bin/zk-deployer
COPY --from=builder /src/era-contracts /opt/era-contracts
COPY rpc-capabilities.sh /usr/local/libexec/prividium/rpc-capabilities.sh
COPY bootstrap.sh /usr/local/bin/prividium-chain-bootstrap

ENV PROTOCOL_CONTRACTS_ROOT=/opt/era-contracts
ENV ZK_DEPLOYER_COMMIT=${ZK_DEPLOYER_COMMIT}
ENV PROTOCOL_COMMIT=${PROTOCOL_COMMIT}
WORKDIR /runtime/chain
ENTRYPOINT ["/usr/local/bin/prividium-chain-bootstrap"]
