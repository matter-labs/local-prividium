# Local Prividium™ Development Environment

A Docker Compose setup for running a complete Prividium™ cluster locally.

## Getting Started

> [!WARNING]
> Request access to our private docker registry before continuing with these instructions.

### 1. Authenticate with Docker Registry

Authenticate with the information provided by the MatterLabs team:

```bash
DOCKER_USERNAME=matterlabs_enterprise+your_username
DOCKER_PASSWORD=super_secret_provided_by_matterlabs

docker login -u=$DOCKER_USERNAME -p=$DOCKER_PASSWORD quay.io
```

### 2. Start the Cluster

Start dependencies and core services:

```bash
docker compose -f docker-compose.yaml up -d
```

### 3. Seed Wallet-Based Users w/ Funds

To add a few wallet-based authenticated users with pre-configured test wallets, run the seed script against the database:

```bash
docker exec -i zksync-prividium-postgres-1 psql -U postgres -d permissions_api < dev/wallet-auth/seed-wallet-auth.sql
```

### 4. Access the Application

Open the User Panel at **http://localhost:3001**

Click **"Sign in with Keycloak"** and use one of the pre-configured test users:

| Email | Password |
|-------|----------|
| admin@local.dev | password |
| user@local.dev | password |
| test@local.dev | password |

Alternatively, you can login via a MetaMask wallet by clicking **"Sign in with Wallet"**:

| Wallet Address | Private Key |
|-------|----------|
| f39Fd6e51aad88F6F4ce6aB8827279cffFb92266 | 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 |
| 70997970C51812dc3A010C7d01b50e0d17dc79C8 | 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d |
| 3C44CdDdB6a900fa2b585dd299e03d12FA4293BC | 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a |

These wallet-based test users all have wallet addresses derived from the standard test mnemonic:
```
test test test test test test test test test test test junk
```

### 5. Access Other Applications

Login to the Admin Panel at **http://localhost:3000**

Login to the Block Explorer at **http://localhost:3010** (Be sure a wallet is associated with the user's account)

---

## Architecture

### Core Services (`docker-compose.yaml`)

The main Prividium™ application services:

- **Admin Panel** - Administrative interface for managing Prividium™
- **User Panel** - User login for Prividium™
- **Permissions API** - Backend API for access control and permissions
- **Proxy** - RPC proxy with permissions enforcement

### Dependencies (`docker-compose-deps.yaml`)

Supporting infrastructure services:

- **PostgreSQL** - Database for permissions and block explorer
- **Keycloak** - Identity provider for OIDC authentication
- **zkSync OS** - Layer 2 sequencer
- **L1 (Anvil)** - Local Ethereum testnet and settlement layer
- **Block Explorer** - Transaction explorer
- **Prometheus** - Metrics collection
- **Grafana** - Metrics visualization

---

## Available URLs

### Application

| Service | URL |
|---------|-----|
| User Panel | http://localhost:3001 |
| Admin Panel | http://localhost:3000 |
| Block Explorer | http://localhost:3010 |

### APIs

| Service | URL |
|---------|-----|
| Permissions API | http://localhost:8000 |
| Proxy (RPC) | http://localhost:8001 |
| Block Explorer API | http://localhost:3002 |

### Blockchain

| Service | URL |
|---------|-----|
| zkSync OS RPC | http://localhost:5050 |
| L1 (Anvil) RPC | http://localhost:5010 |

### Infrastructure

| Service | URL | Credentials |
|---------|-----|-------------|
| Keycloak Admin | http://localhost:5080 | admin / admin |
| Grafana | http://localhost:3100 | admin / admin |
| Prometheus | http://localhost:9090 | - |
| PostgreSQL | localhost:5432 | postgres / postgres |

### Metrics

| Service | URL |
|---------|-----|
| Permissions API Metrics | http://localhost:9091 |
| Proxy Metrics | http://localhost:9092 |

---

## Requesting Additional Funds

As everything is running locally, there are rich accounts on the L2.

You can use the following to "add assets" directly to any other account for testing:

```bash
cast send -r http://localhost:5050 f39Fd6e51aad88F6F4ce6aB8827279cffFb92266  --value 1 --private-key 0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110
```

---

## Viewing Available Versions

To see which image versions are available (useful for updating `docker-compose.yaml`):

```bash
# Install skopeo if needed, then login
skopeo login --username $DOCKER_USERNAME --password $DOCKER_PASSWORD quay.io

# List available tags for a service
skopeo list-tags docker://quay.io/matterlabs_enterprise/prividium-user-panel
```

---

## Stopping the Cluster

```bash
# Stop services
docker compose -f docker-compose.yaml down

# To remove all data volumes as well
docker compose -f docker-compose.yaml down -v
```
