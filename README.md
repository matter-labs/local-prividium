# Local Prividium™ Development Environment

A Docker Compose setup for running a complete Prividium™ cluster locally.

> [!CAUTION]
> This repository is for local development only.
> The stack uses localhost-only URLs, seeded test users, test wallets, fixed development keys, and local infrastructure such as Anvil and a local zkSync OS instance.
> Do not reuse these Docker Compose files, credentials, keys, or defaults against any shared or public network.

## Prerequisites

- Docker with Docker Compose 2.24 or later (Docker Desktop or Docker Engine).
- At least 4 GB of memory and 15 GB of free disk for Docker. The images take about 10 GB.
- These host ports free: `3000`, `3001`, `3002`, `3010`, `3100`, `5010`, `5050`, `5080`, `5432`, `8000`, `8080`, `8081`, `9090`, `9091`.
- Registry credentials for `quay.io`, provided by the Matter Labs team.

The Prividium images are built for `linux/amd64`. On Apple Silicon, Docker Desktop runs them under emulation. Turn on
**Use Rosetta for x86_64/amd64 emulation** in Docker Desktop settings for the best speed.

## Getting Started

Run every command from the root of this repository.

### 1. Log in to the registry

Use the username and password provided by the Matter Labs team:

```bash
DOCKER_USERNAME=matterlabs_enterprise+your_username
echo 'password_provided_by_matterlabs' | docker login quay.io -u "$DOCKER_USERNAME" --password-stdin
```

### 2. Start the cluster

```bash
docker compose up -d
```

The first start pulls all images and takes a few minutes.

### 3. Wait for the API

```bash
until curl -sf http://localhost:8000/health > /dev/null; do echo "Waiting for the Prividium API..."; sleep 5; done
```

The API runs its database migrations on startup. The next step needs them.

### 4. Seed test users and services

```bash
cat dev/wallet-auth/seed-wallet-auth.sql dev/service-auth/seed-webhook-service.sql \
  | docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres -d prividium_api
```

This adds the wallet-based test users and the account the webhook service uses to read the chain. It is safe to run
again.

### 5. Open the User Panel

Open **http://localhost:3001** and click **Sign in with Keycloak**. Use one of these test users:

| Email           | Password |
|-----------------|----------|
| admin@local.dev | password |
| user1@local.dev | password |
| user2@local.dev | password |

You can also click **Sign in with Wallet** and use MetaMask with one of these test wallets:

| Wallet Address                           | Private Key                                                        |
|------------------------------------------|--------------------------------------------------------------------|
| f39Fd6e51aad88F6F4ce6aB8827279cffFb92266 | 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 |
| 70997970C51812dc3A010C7d01b50e0d17dc79C8 | 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d |
| 3C44CdDdB6a900fa2b585dd299e03d12FA4293BC | 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a |

These wallets come from the standard test mnemonic:

```
test test test test test test test test test test test junk
```

The first wallet (`f39F…2266`) is an admin.

### 6. Open the other applications

- Admin Panel: **http://localhost:3000**
- Block Explorer: **http://localhost:3010**. Your user needs a linked wallet to sign in.

---

## Available URLs

### Application

| Service        | URL                   |
|----------------|-----------------------|
| User Panel     | http://localhost:3001 |
| Admin Panel    | http://localhost:3000 |
| Block Explorer | http://localhost:3010 |

### APIs

| Service            | URL                   |
|--------------------|-----------------------|
| Prividium API      | http://localhost:8000 |
| Block Explorer API | http://localhost:3002 |

### Blockchain

| Service        | URL                   |
|----------------|-----------------------|
| zkSync OS RPC  | http://localhost:5050 |
| L1 (Anvil) RPC | http://localhost:5010 |

### Infrastructure

| Service        | URL                   | Credentials         |
|----------------|-----------------------|---------------------|
| Keycloak Admin | http://localhost:5080 | admin / admin       |
| Grafana        | http://localhost:3100 | admin / admin       |
| Prometheus     | http://localhost:9090 | -                   |
| PostgreSQL     | localhost:5432        | postgres / postgres |

### Metrics

| Service               | URL                   |
|-----------------------|-----------------------|
| Prividium API Metrics | http://localhost:9091 |

---

## Funding Test Accounts

The local L2 has pre-funded accounts. To send 1 ETH to any address, run `cast` inside the stack's L1 container:

```bash
docker compose exec l1 cast send --rpc-url http://zksyncos:3050 <address-to-fund> --value 1ether \
  --private-key 0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110
```

---

## Stopping and Resetting

```bash
# Stop the cluster and keep its data
docker compose down

# Stop the cluster and delete all data
docker compose down -v
```

After `down -v`, start again from [step 2](#2-start-the-cluster) and run the seed step again.

---

## Troubleshooting

### `zksyncos` keeps restarting with `BlockOutOfRangeError`

The log shows lines like these:

```
failed to init CommittedBatchProvider: failed to find live L1 commit block for batch 15
BlockOutOfRangeError: block height is 796 but requested was 99
```

On startup, the sequencer reads old blocks from the local L1. To save disk, the local L1 keeps history for only its 512 most
recent blocks, under two hours. Restarting the sequencer after the stack has run that long hits this. Run the reset
below.

### `l1` keeps restarting with `EOF while parsing`

The log shows a line like this:

```
error: invalid value '/home/foundry/l1state/state.json' for '--state <PATH>': failed to parse json file: ... EOF while parsing
```

The L1 state file was cut short. This happens when Docker stops before the L1 finishes saving, for example when the
machine sleeps or Docker Desktop quits. Run the reset below.

### Reset

The local chain is a disposable sandbox. A reset deletes all its data and starts a fresh chain:

```bash
docker compose down -v
docker compose up -d
```

Then wait for the API and seed again ([steps 3 and 4](#3-wait-for-the-api)).

### Webhook service logs `Unauthorized`

The seed step has not run. Run [step 4](#4-seed-test-users-and-services).

### `Bind for 0.0.0.0:<port> failed: port is already allocated`

Another program uses one of the ports listed in [Prerequisites](#prerequisites). Stop it and run `docker compose up -d`
again.

### `unauthorized` or `denied` when pulling images

Log in to the registry again ([step 1](#1-log-in-to-the-registry)). If it still fails, ask the Matter Labs team to
check your registry access.

---

## Viewing Available Versions

To see which image versions are available (useful for updating `docker-compose.yaml`):

```bash
# Install skopeo if needed, then log in
skopeo login --username "$DOCKER_USERNAME" quay.io

# List available tags for a service
skopeo list-tags docker://quay.io/matterlabs_enterprise/prividium-user-panel
```

---

## Architecture

### Core Services (`docker-compose.yaml`)

- **Admin Panel**: administrative interface for managing Prividium™
- **User Panel**: user login for Prividium™
- **Prividium API**: API services, including permissions and the protected RPC

### Dependencies (`docker-compose-deps.yaml`)

- **PostgreSQL**: database for the Prividium API and the block explorer
- **Keycloak**: identity provider for OIDC authentication
- **zkSync OS**: Layer 2 sequencer
- **L1 (Anvil)**: local Ethereum execution layer, used as the settlement layer for this sandbox
- **Block Explorer**: transaction explorer
- **Webhook Service**: delivers webhooks for on-chain activity
- **Prometheus**: metrics collection
- **Grafana**: metrics visualization
