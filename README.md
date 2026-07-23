# Prividium Sepolia Sandbox

This repository deploys a durable, single-VPS Prividium sandbox backed by a dedicated ZKsync ecosystem on Ethereum Sepolia.

> [!CAUTION]
> This is not a production deployment or an officially supported public testnet. It uses fake proofs, a testnet verifier, one VPS, and operator-funded Sepolia transactions. Do not use it to secure assets of value.

## What runs

- ZKsync OS `0.20.8` using Protocol `v0.31.0`, rollup DA, blobs, and 10-minute batches.
- Prividium API, user panel, admin panel, and Block Explorer.
- Keycloak backed by PostgreSQL with one initial sandbox administrator.
- Caddy with automatic HTTPS for all browser-facing services.
- Prometheus, Grafana, Watchdog, and an operator-balance exporter.
- Optional SSO/EntryPoint/bundler, webhook, and institutional-demo profiles.

Anvil, deterministic development wallets, fixed passwords, the local faucet, and raw public RPC ports are not included.

## Prerequisites

- An x86-64 VPS with Docker Engine and Docker Compose v2.
- Recommended capacity: 8 vCPU, 16 GB RAM, and 200 GB SSD.
- An IPv4 address reachable on ports 80 and 443.
- `A` records pointing to the VPS for the core stack:

  `app`, `admin`, `api`, `explorer`, `explorer-api`, and `idp` under the selected sandbox domain.

- Optional `auth` and `auth-api` records for the `sso` profile, and `demo` for the institutional profile.

- A private Sepolia RPC with historical calls, logs, receipts, and blob transaction support.
- A separate public, CORS-enabled Sepolia RPC for browser bridging.
- `age`, `sops`, `cast`, `jq`, `openssl`, and `curl` on the operator workstation.
- Access to the Matter Labs private images on Quay.

## Deployment

The repository exposes one operator command: `tools/sandbox`. A first
deployment normally takes **2–4 hours elapsed time**, excluding delays obtaining
Sepolia ETH, private-image access, a capable RPC, and DNS/ACME propagation.
Start with the [guided setup](docs/SETUP.md); it describes the purpose,
expected result, time, and recovery path for every stage.

The complete command sequence is:

```bash
tools/sandbox doctor
tools/sandbox init

sudo install -d -m 0700 -o "$USER" /etc/prividium/runtime
tools/sandbox decrypt
tools/sandbox funding
tools/sandbox funding apply
tools/sandbox prepare
tools/sandbox readiness
tools/sandbox broadcast
tools/sandbox deploy
```

Initialization writes a commit-safe role inventory grouped by purpose. The
customer sends exactly **1 Sepolia ETH to one address**: the sandbox funding
wallet shown in `deployment/public/roles.md`. `funding` writes a protected,
reviewable allocation plan; `funding apply` confirms that exact plan and
distributes only current shortfalls.

`broadcast` reruns the mandatory readiness gate and is the only step that
submits the ecosystem deployment to Sepolia. `deploy` waits for core service
health plus HTTPS, protected API, Explorer, and OIDC checks before writing the
commit-safe final summary.

The broadcast writes `deployment/public/manifest.json`. Review and commit this
non-secret record after checking its addresses and transaction hashes.

## Repository layout

`docker-compose.yaml` is the only Compose entrypoint. It includes smaller files
that can be reviewed independently:

| File | Responsibility |
| --- | --- |
| `docker-compose.yaml` | Core Prividium API, user/admin applications, and Caddy |
| `docker-compose-platform.yaml` | PostgreSQL, Keycloak, chain bootstrap, and ZKsync OS |
| `docker-compose-explorer.yaml` | Block Explorer UI, API, worker, and data fetcher |
| `docker-compose-permissioning.yaml` | Idempotent Watchdog, SSO, and webhook permissions |
| `docker-compose-monitoring.yaml` | Watchdog, Prometheus, Grafana, and balance monitoring |
| `docker-compose-optional.yaml` | SSO/bundler and webhook runtime |
| `docker-compose-demos.yaml` | Institutional demo identity, funding, deployment, seed, and app |

See [deployment components](docs/COMPONENTS.md) for profiles, networks,
persistence, and startup dependencies.

## Public endpoints

For `SANDBOX_DOMAIN=sandbox.example.com`:

| Component | URL |
| --- | --- |
| User panel | `https://app.sandbox.example.com` |
| Admin panel | `https://admin.sandbox.example.com` |
| Protected API/RPC | `https://api.sandbox.example.com` |
| Block Explorer | `https://explorer.sandbox.example.com` |
| Explorer API | `https://explorer-api.sandbox.example.com` |
| SSO (optional) | `https://auth.sandbox.example.com` |
| SSO API (optional) | `https://auth-api.sandbox.example.com` |
| OIDC issuer | `https://idp.sandbox.example.com/realms/prividium` |
| Institutional demo (optional) | `https://demo.sandbox.example.com` |

Keycloak administration, PostgreSQL, Prometheus, bundler, webhook internals, and raw ZKsync OS RPC are not public. Grafana is bound to `127.0.0.1:3100` and is intended for an SSH tunnel.

## Configuration and versions

- `deployment/sandbox.env.example` documents every public and secret setting.
- `deployment/versions.lock.yaml` records component versions, source commits, and immutable registry digests.
- `deployment/funding-policy.json` records the one-ETH allocation boundary and release benchmark.
- `deployment/public/manifest.example.json` documents the on-chain manifest written by the bootstrap.
- `deployment/public/roles.example.md` and `deployment/public/deployment-summary.example.md` document the public reports.
- `tools/validate-stack` rejects local-only endpoints, legacy chain IDs, known development keys, floating remote images, and unexpected host ports.

Airbender `v0.8.1` remains selected but deferred; no prover service is started.

## Optional SSO, bundler, and webhooks

The default deployment does not start SSO, EntryPoint deployment, the bundler, or webhooks. Their credentials are still generated independently and kept encrypted so either profile can be enabled later.

For SSO, first add `auth` and `auth-api` DNS records, then:

```bash
tools/sandbox edit-secrets
# Set BUNDLER_ENABLED=true, save, and exit the editor.
tools/sandbox decrypt
tools/sandbox enable sso
```

The command states that SSO/bundler funding is outside the core 1 ETH
guarantee and checks the sandbox funding wallet for the incremental allowance
before it starts anything.

For webhooks:

```bash
tools/sandbox edit-secrets
# Set WEBHOOK_ENABLED=true, save, and exit the editor.
tools/sandbox decrypt
tools/sandbox enable webhook
```

The SSO and webhook permission jobs are independent and idempotent. Disabling either profile does not remove its durable data.

## Optional institutional demo

The demo uses SSO. Add the `demo` DNS record and enable it after the core stack
and SSO configuration are healthy:

```bash
tools/sandbox enable demo
```

The profile creates its own Keycloak realm, two SOPS-managed users, a dedicated funded deployer, and persistent contract output. It does not add demo users to the core realm.
Its incremental funding is also outside the core 1 ETH guarantee and is checked
before the profile starts.

## Release benchmark gate

The one-ETH claim is a release contract, not an estimate. Funding, readiness,
and deployment refuse to proceed while
`deployment/funding-policy.json` has `benchmark.status: pending`. Before
customer release, complete one clean Sepolia rehearsal using
[the benchmark procedure](docs/FUNDING_BENCHMARK.md), record the evidence, and
independently review the resulting targets. Provisional values are never
presented as measured values.

For restarts, upgrades, backups, certificate troubleshooting, and secret
recovery, use the [operations runbook](docs/RUNBOOK.md).
