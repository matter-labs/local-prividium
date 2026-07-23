FROM node:22-slim@sha256:6c74791e557ce11fc957704f6d4fe134a7bc8d6f5ca4403205b2966bd488f6b3 AS bridge-funds
ENV PNPM_HOME=/pnpm
ENV PATH=/pnpm:$PATH
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY scripts ./scripts
ENTRYPOINT ["node", "--import", "tsx", "scripts/bridge-funds.ts"]

FROM ghcr.io/foundry-rs/foundry:v1.5.1@sha256:3a70bfa9bd2c732a767bb60d12c8770b40e8f9b6cca28efc4b12b1be81c7f28e AS entrypoint
USER root
WORKDIR /app
COPY entrypoint /app
RUN forge soldeer install --config-location foundry
ENTRYPOINT ["/bin/bash", "/app/script/deploy.sh"]
