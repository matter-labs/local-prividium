# Local Prividium™ Development Environment

A Docker Compose setup for running a complete Prividium™ cluster locally.

> [!CAUTION]
> This repository is for local development only.
> The stack uses localhost-only URLs, seeded test users, test wallets, fixed development keys, and local infrastructure such as a local Ethereum node and a local zkSync OS instance.
> Do not reuse these Docker Compose files, credentials, keys, or defaults against any shared or public network.

## Prerequisites

- Docker with Docker Compose 2.24.4 or later (Docker Desktop or Docker Engine).
- At least 4 GB of memory and 15 GB of free disk for Docker. The images take about 10 GB.
- These host ports free: `3000`, `3001`, `3002`, `3010`, `3100`, `5010`, `5050`, `5080`, `5432`, `8000`, `8080`, `8081`, `9090`, `9091`.
- Registry credentials for `quay.io`, provided by the Matter Labs team.
- Optional: [Foundry](https://getfoundry.sh) for `cast`, to fund test accounts.

## Getting Started

> [!WARNING]
> Request access to our private docker registry before continuing with these instructions.

Run every command from the root of this repository.

### 1. Authenticate with Docker Registry

Authenticate with the information provided by the MatterLabs team:

```bash
DOCKER_USERNAME=matterlabs_enterprise+your_username
echo 'password_provided_by_matterlabs' | docker login quay.io -u "$DOCKER_USERNAME" --password-stdin
```

### 2. Start the Cluster

Start dependencies and core services:

```bash
docker compose up -d
```

The first start pulls all images and deploys the contracts on the local L1. It takes a few minutes. Later starts reuse
both.

### 3. Wait for the API

```bash
until curl -sf http://localhost:8000/health > /dev/null; do echo "Waiting for the Prividium API..."; sleep 5; done
```

The API runs its database migrations on startup. The next step needs them.

### 4. Seed Users and Services

```bash
cat dev/wallet-auth/seed-wallet-auth.sql dev/service-auth/seed-webhook-service.sql \
  | docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres -d prividium_api
```

This adds the wallet-based test users and the account the webhook service uses to read the chain. It is safe to run
again.

### 5. Access the Application

Open the User Panel at **http://localhost:3001**

Click **"Sign in with Keycloak"** and use one of the pre-configured test users:

| Email           | Password |
|-----------------|----------|
| admin@local.dev | password |
| user1@local.dev | password |
| user2@local.dev | password |

Alternatively, you can login via a MetaMask wallet by clicking **"Sign in with Wallet"**:

| Wallet Address                           | Private Key                                                        |
|------------------------------------------|--------------------------------------------------------------------|
| f39Fd6e51aad88F6F4ce6aB8827279cffFb92266 | 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 |
| 70997970C51812dc3A010C7d01b50e0d17dc79C8 | 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d |
| 3C44CdDdB6a900fa2b585dd299e03d12FA4293BC | 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a |

These wallet-based test users all have wallet addresses derived from the standard test mnemonic:

```
test test test test test test test test test test test junk
```

The first wallet (`f39F…2266`) is an admin.

### 6. Access Other Applications

Login to the Admin Panel at **http://localhost:3000**

Login to the Block Explorer at **http://localhost:3010** (Be sure a wallet is associated with the user's account)

---

## Architecture

### Core Services (`docker-compose.yaml`)

The main Prividium™ application services:

- **Admin Panel** - Administrative interface for managing Prividium™
- **User Panel** - User login for Prividium™
- **Prividium API** - API services, including control and permissions and protected rpc.

### Dependencies (`docker-compose-deps.yaml`)

Supporting infrastructure services:

- **PostgreSQL** - Database for prividium api and block explorer
- **Keycloak** - Identity provider for OIDC authentication
- **zkSync OS** - Layer 2 sequencer
- **L1 (Geth)** - Local Ethereum node used as the settlement layer for this sandbox. It keeps the full chain history,
  so the stack can be stopped and restarted at any time.
- **Block Explorer** - Transaction explorer
- **Webhook Service** - Delivers webhooks for on-chain activity
- **Prometheus** - Metrics collection
- **Grafana** - Metrics visualization

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
| L1 (Geth) RPC  | http://localhost:5010 |

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

## Requesting Additional Funds

As everything is running locally, there are rich accounts on the L2.

You can use the following to "add assets" directly to any other account for testing. It needs
[Foundry](https://getfoundry.sh) installed:

```bash
cast send --rpc-url http://localhost:5050 <address-to-fund> --value 1ether \
  --private-key 0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110
```

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

## Stopping the Cluster

```bash
# Stop services
docker compose down

# To remove all data volumes as well
docker compose down -v
```

After `down -v`, start again from [step 2](#2-start-the-cluster) and run the seed step again.

---

## Troubleshooting

### `zksyncos` keeps restarting after an update

The local chain data comes from an earlier version of this repository. Run the reset below.

### Reset

The local chain is a disposable sandbox. A reset deletes all its data and starts a fresh chain:

```bash
docker compose down -v
docker compose up -d
```

Then wait for the API and seed again ([steps 3 and 4](#3-wait-for-the-api)).

### Slow startup on Apple Silicon

The Prividium images are built for `linux/amd64`, so Docker Desktop runs them under emulation. Turn on **Use Rosetta for
x86_64/amd64 emulation** in Docker Desktop settings for the best speed.

### Webhook service logs `Unauthorized`

The seed step has not run. Run [step 4](#4-seed-users-and-services).

### `Bind for 0.0.0.0:<port> failed: port is already allocated`

Another program uses one of the ports listed in [Prerequisites](#prerequisites). Stop it and run `docker compose up -d`
again.

### `unauthorized` or `denied` when pulling images

Log in to the registry again ([step 1](#1-authenticate-with-docker-registry)). If it still fails, ask the Matter Labs team to
check your registry access.
