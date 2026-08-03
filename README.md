# Prividium Sepolia Sandbox

This repository provides a focused, single-VPS Prividium evaluation backed by a
dedicated ZKsync ecosystem on Ethereum Sepolia.

> [!CAUTION]
> This is not a production deployment or an official public testnet. It uses
> fake proofs, a testnet verifier, SOPS-managed hot keys, and one host. Never
> use it to secure assets of value.

## Evaluation workflow

The CLI is the only customer-facing deployment interface. From a clean
repository checkout on the dedicated VPS, bootstrap the pinned local Ansible
controller and assess the host:

```bash
./cli/prividium host bootstrap
./cli/prividium host preflight
./cli/prividium host install --check
./cli/prividium host install
# Reconnect so Docker group membership applies.
./cli/prividium host verify
```

Run that workflow as a normal passwordless-sudo operator. If a provider image
initially exposes only `root`, the setup guide uses the constrained
`./cli/prividium host operator create` command to create the operator while
preserving root access until a second SSH login has been verified.

Then run the application workflow on the VPS:

```bash
./cli/prividium init
./cli/prividium fund
./cli/prividium preflight
./cli/prividium prepare
./cli/prividium broadcast
./cli/prividium deploy
```

The stages are deliberately explicit:

- `host bootstrap` creates the pinned local Ansible controller and one-host
  local inventory.
- `host operator create` is a root-only preparatory command for provider images
  that do not already have a suitable non-root account.
- `host preflight` performs a read-only compatibility and dedicated-host
  assessment.
- `host install` safely upgrades Ubuntu packages and installs the baseline
  tools, Docker, services, and protected directories after revalidating the
  host.
- `host verify` checks the complete Ansible-managed installation surface.
- `init` creates the encrypted configuration, age identity, evaluation users,
  generated identities, and public role inventory.
- `fund` reconciles the three deployment and three settlement-operator
  identities on Sepolia.
- `preflight` performs read-only host, configuration, RPC, registry, DNS,
  Compose, identity, and funding checks.
- `prepare` creates the protected runtime, simulates protocol deployment, and
  pulls/builds the default stack without submitting transactions.
- `broadcast` requires chain-specific confirmation and creates the ecosystem
  and chain contracts on Sepolia.
- `deploy` requires public DNS, starts the prebuilt services, and validates the
  public interfaces.

See [the setup guide](runbooks/SETUP.md) for the complete walkthrough and
[the evaluation guide](runbooks/EVALUATION.md) for the engineering and BD handoff
checklist. The [evaluation VPS host contract](runbooks/HOST_CONTRACT.md)
defines the supported boundary enforced by the read-only Ansible preflight.

## What runs

- ZKsync OS `0.20.8` with Protocol `v0.31.0`, rollup DA, and fake proofs.
- Prividium API, user panel, administration panel, and protected RPC.
- PostgreSQL and a Keycloak realm with one administrator and two users.
- Block Explorer application, API, worker, and data fetcher.
- Caddy with automatic HTTPS.
- Prometheus, Grafana, and settlement-operator balance monitoring.

The default model has 14 long-running services and one successful one-shot
`chain-preflight` job. It contains no service-wallet bridge. Starting the chain
can still produce normal Sepolia transactions from the already-funded commit,
prove, and execute operators.

SSO, EntryPoint/bundler, webhook, and institutional-demo implementations remain
in deferred Compose profiles. They are not started by the initial CLI and do
not yet have public activation commands.

## Prerequisites

- A dedicated, initially blank Ubuntu Server 24.04 LTS / amd64 VPS.
- Git, Python 3.12 or newer, `python3-apt`, and `venv` support for the initial
  clone and bootstrapped host controller.
- Minimum CPU capacity: 4 vCPU.
- Minimum memory capacity: 8 GB RAM.
- Minimum root-disk capacity: 200 GB SSD.
- Recommended compute capacity: 8 vCPU and 16 GB RAM.
- Customer-approved SSH access, inbound TCP 80 and 443, and inbound UDP 443.
- `A` records for `app`, `admin`, `api`, `explorer`, `explorer-api`, and `idp`
  under the selected sandbox domain.
- A private Sepolia RPC with historical calls/logs, receipts, and blob-fee
  support.
- A separate public, CORS-enabled Sepolia RPC for browser use.
- Access to the pinned private Prividium images on Quay.
- Sepolia ETH for the six protocol identities.

The host installer supplies Docker Engine, Compose, `age`, SOPS, Foundry,
`jq`, OpenSSL, and the remaining managed host packages. Provider firewall
rules, DNS, Quay authentication, RPC access, and Sepolia funding remain
customer-controlled. Host firewall automation is deferred.

## Public interfaces

For `SANDBOX_DOMAIN=sandbox.example.com`:

| Interface | URL |
| --- | --- |
| User application | `https://app.sandbox.example.com` |
| Administration | `https://admin.sandbox.example.com` |
| Protected API and RPC | `https://api.sandbox.example.com` |
| Block Explorer | `https://explorer.sandbox.example.com` |
| Explorer API | `https://explorer-api.sandbox.example.com` |
| OIDC issuer | `https://idp.sandbox.example.com/realms/prividium` |

PostgreSQL, Keycloak administration, Prometheus, and raw ZKsync OS RPC are not
published. Grafana binds to `127.0.0.1:3100` for access through an SSH tunnel.

## Generated evidence

The focused track produces three commit-safe public records:

| File | Purpose |
| --- | --- |
| `deployment/public/roles.md` | Generated identities and their roles |
| `deployment/public/manifest.json` | Protocol addresses, genesis, locks, and transaction hashes |
| `deployment/public/deployment-summary.md` | Healthy services and public endpoints |

Private keys, passwords, and provider credentials remain in the encrypted
configuration or protected `/etc/prividium/runtime` files.

## Repository structure

The repository is organized by deployment interface and operational concern:

```text
.
├── README.md
├── schemas/                         # Reserved for deployment schemas
├── cli/                             # Customer-facing deployment CLI
├── ansible/                         # Host preflight, installation, and verification
├── compose/                         # Compose entrypoint and service modules
├── releases/                        # Reserved for release manifests
├── runbooks/                        # Setup, component, and evaluation guides
├── skills/deploy-prividium/         # Reserved deployment skill
├── mcp/prividium-deployment-server/ # Reserved deployment MCP server
├── deployment/                      # Sandbox configuration and public output
├── dev/                             # Container build and runtime assets
├── tools/                           # Internal deployment helpers
└── tests/                           # Deployment UX validation
```

`compose/compose.yaml` is the only Compose entrypoint. It includes separate
platform, Explorer, permissioning, monitoring, deferred-profile, and demo
modules. See [components](runbooks/COMPONENTS.md).

Reserved implementation directories retain `.gitkeep` placeholders until
their functionality is introduced. See [the Ansible guide](ansible/README.md)
for the implemented host automation and its explicit security boundary.

Configuration references:

- `deployment/sandbox.env.example` documents settings.
- `deployment/funding-targets.json` contains only the six evaluation funding
  targets.
- `deployment/versions.lock.yaml` records component versions, source commits,
  and immutable image digests.
- `deployment/public/*.example.*` documents public generated artifacts.
- `tools/validate-stack` validates the complete Compose model rooted at
  `compose/compose.yaml`.

Airbender remains version-selected but deferred; no prover service is started.
