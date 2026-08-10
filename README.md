# Prividium Sepolia Sandbox

This repository deploys a persistent, single-VPS Prividium evaluation backed
by a dedicated ZKsync ecosystem on Ethereum Sepolia.

> [!CAUTION]
> This is not a production deployment or an official public testnet. It uses
> fake proofs, a testnet verifier, SOPS-managed hot keys, and one host. Never
> use it to secure assets of value.

## Quick start with an agent

Install and authenticate either Codex CLI or Claude Code before starting. On a
dedicated, initially blank Ubuntu Server 24.04 amd64 VPS, clone over HTTPS:

```bash
git clone https://github.com/matter-labs/local-prividium.git
cd local-prividium
```

Start the chosen agent from the repository and invoke the deployment skill:

```text
codex   → $deploy-prividium
claude  → /deploy-prividium
```

The skill resumes safely from existing verified artifacts and drives the
repository CLI. It pauses when a human must verify access, control an external
account, handle a credential, fund Sepolia identities, or approve protocol
transactions.

If the provider image initially exposes only `root`, the skill uses the
constrained `./cli/prividium host operator create` command and stops until a
second SSH login as the new operator is verified. Continue from a fresh
operator-owned HTTPS clone; never reuse a checkout under `/root`.

## Human checkpoints

The agent identifies and verifies these checkpoints in order:

1. Verify a non-root passwordless-sudo operator and reconnect when required.
2. Reconnect after Docker group membership, rebooting first only when required.
3. Edit the protected four-field `deployment/input.env` directly on the VPS.
4. Configure the provider firewall and six public DNS records.
5. Authenticate Docker to Quay with the issued pull-only credential.
6. Fund the generated Sepolia wallet and approve distribution.
7. Review and explicitly authorize the prepared Sepolia protocol broadcast.
8. Reveal generated evaluation logins only when requested.

Provider firewall rules, DNS, Quay credential issuance, agent installation,
RPC procurement, and Sepolia funding remain human-controlled. Host firewall
automation is deferred.

## Supported VPS

- Ubuntu Server 24.04 LTS, `amd64`, systemd, and a public IPv4 address.
- Dedicated blank host with a key-authenticated non-root passwordless-sudo
  operator.
- Minimum 4 vCPU and 8 GB RAM; 8 vCPU and 16 GB RAM are recommended.
- Nominal 200 GB SSD; preflight accepts at least 190 GB usable root capacity.
- Provider recovery console or equivalent out-of-band access.

The host installer supplies safe Ubuntu upgrades, baseline packages, Chrony,
unattended security updates without automatic reboot, checksum-pinned SOPS and
Foundry, Docker Engine, Buildx, Compose, bounded container logs, and protected
runtime directories.

See [the host contract](runbooks/HOST_CONTRACT.md) for the enforced boundary.

## CLI workflow

The skill uses these deterministic commands. They remain available as the
manual fallback documented in [the setup guide](runbooks/SETUP.md):

```bash
./cli/prividium host bootstrap
./cli/prividium host preflight
./cli/prividium host install --check
./cli/prividium host install
# Reconnect, then:
./cli/prividium host verify

./cli/prividium init
./cli/prividium fund
./cli/prividium preflight
./cli/prividium prepare
./cli/prividium broadcast
./cli/prividium deploy
```

- Host commands operate only on the current VPS. Remote inventories are not
  supported.
- `init` reads `deployment/input.env`, generates strong evaluation passwords,
  and creates the SOPS-encrypted configuration and public role inventory.
- `fund` reconciles the deployment and settlement identities on Sepolia.
- `preflight` validates configuration, RPC, registry, DNS, Compose, identities,
  and funding without changing state.
- `prepare` builds and simulates the protocol deployment without transactions.
- `broadcast` requires chain-specific human approval before Sepolia
  transactions.
- `deploy` starts and verifies the persistent evaluation services.
- `credentials show` is a confirmation-gated, TTY-only credential reveal.

## Human input and generated configuration

`deployment/input.env.example` is the template for the only four human values:

```text
SANDBOX_DOMAIN
ACME_EMAIL
SEPOLIA_RPC_URL
SEPOLIA_BROWSER_RPC_URL
```

The private RPC must support historical calls/logs, receipts, and blob-fee
behavior. The browser RPC must be a distinct public HTTPS endpoint with CORS.
The input file is mode `0600`, parsed as data rather than shell code, and
deleted by the skill only after encrypted outputs are verified.

`deployment/sandbox.env.example` is different: it documents the complete
generated runtime shape and provides non-secret example values for static
Compose validation. Customers do not fill it in.

## What runs

- ZKsync OS `0.20.8` with Protocol `v0.31.0`, rollup DA, and fake proofs.
- Prividium API, user panel, administration panel, and protected RPC.
- PostgreSQL and Keycloak with one administrator and two evaluation users.
- Block Explorer application, API, worker, and data fetcher.
- Caddy with automatic HTTPS.
- Prometheus, Grafana, and settlement-operator balance monitoring.

The default model has 14 long-running services and one successful one-shot
`chain-preflight` job. SSO, webhook, and institutional-demo implementations
remain deferred profiles and are not part of the initial customer path.

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
published. Grafana binds to `127.0.0.1:3100` for an SSH tunnel.

## Generated evidence

The deployment produces three commit-safe public records:

| File | Purpose |
| --- | --- |
| `deployment/public/roles.md` | Generated public identities and roles |
| `deployment/public/manifest.json` | Protocol addresses, genesis, locks, and transaction hashes |
| `deployment/public/deployment-summary.md` | Healthy services and public endpoints |

Private keys, passwords, RPC credentials, and the age identity must never be
included in an evaluation report. See [the evaluation guide](runbooks/EVALUATION.md)
for the engineering and BD handoff.

## Repository structure

```text
.
├── cli/                             # Customer-facing deployment CLI
├── compose/                         # Compose entrypoint and service modules
├── deployment/                      # Input template, runtime reference, and public output
├── dev/                             # Container build and runtime assets
├── runbooks/                        # Setup, host, component, and evaluation guides
├── skills/deploy-prividium/         # Canonical agent deployment contract
├── .agents/skills/                  # Codex discovery link
├── .claude/skills/                  # Claude Code discovery link
├── tools/host/                      # Auditable local VPS host backend
├── tools/                           # Protocol and deployment helpers
└── tests/                           # Focused happy-path smoke validation
```

`compose/compose.yaml` is the only Compose entrypoint. Component versions,
source commits, image digests, and deferred profiles are recorded in
`deployment/versions.lock.yaml`.
