# Prividium Sepolia Sandbox

This repository deploys a persistent, single-VPS Prividium evaluation backed
by a dedicated ZKsync ecosystem on Ethereum Sepolia.

For the governed customer journey, begin with the
[enterprise deployment guide](runbooks/ENTERPRISE_DEPLOYMENT.md). The
[documentation index](runbooks/README.md) routes platform, security,
deployment, and evaluation teams to their supporting references.

> [!CAUTION]
> This is not a production deployment or an official public testnet. It uses
> fake proofs, a testnet verifier, SOPS-managed hot keys, and one host. Never
> use it to secure assets of value.

## Quick start with an agent

Have the customer engineer prepare a VPS that satisfies
[the documented prerequisites](runbooks/HOST_CONTRACT.md), then clone over
HTTPS:

```bash
git clone https://github.com/matter-labs/local-prividium.git
cd local-prividium
cargo install --path crates/prividium-cli --locked --bin prividiumcli
prividiumcli --version
```

Start the chosen agent from the repository and invoke the deployment skill:

```text
codex   → $deploy-prividium
claude  → /deploy-prividium
```

During this source-validation phase the CLI is not published. Rust 1.90.0 and
Cargo must already be available to the Unix user. The command above installs
`prividiumcli` locally from the locked source in the checkout.

The skill resumes safely from existing verified artifacts and drives the
repository CLI. It pauses when a human must control external infrastructure,
handle a credential, fund Sepolia identities, or approve protocol transactions.
Host provisioning and policy remain with the customer engineer.

## Human checkpoints

The agent identifies and verifies these checkpoints in order:

1. Edit the protected input file directly on the VPS; optionally choose the L2 chain ID.
2. Configure network access and the six required public DNS records.
3. Authenticate Docker to Quay with the issued pull-only credential.
4. Fund the generated Sepolia wallet and approve distribution.
5. Review and explicitly authorize the prepared Sepolia protocol broadcast.
6. Review and explicitly authorize the minimal acceptance canary.
7. Reveal generated evaluation logins only when requested.

Host preparation, firewall rules, DNS, Quay credential issuance, agent
installation, RPC procurement, and Sepolia funding remain human-controlled.

## Host prerequisites

- Dedicated Linux `amd64` VPS; Ubuntu Server 24.04 LTS is the qualified target.
- Expected capacity of 8 vCPU, 16 GB RAM, and a nominal 200 GB
  nonrotational SSD.
- Docker Engine and Compose v2 available to the deployment user.
- Rust 1.90.0 with Cargo, Git, age, SOPS, and Foundry `cast`.
- Protected `/etc/prividium/runtime`, required network access, and six DNS
  records as described in the setup guide.

These capacity figures are planning requirements, not CLI gates. The CLI does
not provision or audit the OS, accounts, SSH, sudo, firewall, package policy,
Docker daemon policy, or hardware capacity. See
[the host prerequisites](runbooks/HOST_CONTRACT.md) for the ownership boundary.

## CLI workflow

The skill uses these deterministic commands. They remain available as the
manual fallback documented in [the setup guide](runbooks/SETUP.md):

```bash
prividiumcli status
prividiumcli init
prividiumcli fund
prividiumcli preflight
prividiumcli prepare
prividiumcli broadcast
prividiumcli deploy
prividiumcli verify
```

- `init` reads `deployment/input.env`, generates strong evaluation passwords,
  creates the SOPS-encrypted configuration and public role inventory, verifies
  decryption, and removes the default plaintext input.
- `fund` reconciles the deployment and settlement identities on Sepolia.
- `preflight` validates application prerequisites, configuration, RPC,
  registry, DNS, Compose, identities, and funding without changing state. It
  does not assess hardware capacity or host policy.
- `prepare` builds and simulates the protocol deployment without transactions.
- `prepare` pulls the existing digest-pinned product images and builds only the
  local chain-bootstrap and operator-balance-exporter helpers. Nothing is
  published to a registry.
- `broadcast` requires chain-specific human approval before Sepolia
  transactions.
- `deploy` starts and verifies the persistent evaluation services.
- `verify` uses a non-admin OIDC login, authenticated RPC, a confirmation-gated
  deposit receipt, and Explorer indexing to establish `READY`.
- `status [--json]` reports the resumable stage without decrypting secrets or
  repeating funding and broadcast transactions. Interrupted approved writes
  become manual-review stages instead of retry instructions.
- `credentials show` is a confirmation-gated, TTY-only credential reveal.
- `--output json` returns one versioned result envelope on stdout; progress and
  prompts stay on stderr. Agents should prefer it for control flow and use the
  stable `outcome`, `stage`, `next_action`, and `error.code` fields.
  Exit `0` is complete, `2` is an expected action/review checkpoint, `1` is a
  failure, and `64` is invalid invocation.

## Human input and generated configuration

`deployment/input.env.example` requires four human values and accepts one
optional override:

```text
SANDBOX_DOMAIN
ACME_EMAIL
SEPOLIA_RPC_URL
SEPOLIA_BROWSER_RPC_URL
L2_CHAIN_ID (optional; generated in 1073741824..2147483647 when omitted)
```

The private RPC must support historical calls/logs, receipts, and blob-fee
behavior. The browser RPC must be a distinct public HTTPS endpoint with CORS.
The input file is mode `0600`, parsed as data rather than shell code, and
deleted by the skill only after encrypted outputs are verified.

`deployment/sandbox.env.example` is different: it documents the complete
generated runtime shape and provides non-secret example values for static
Compose validation. Customers do not fill it in.

## What runs

- ZKsync OS `0.20.8` with Protocol `v0.31.0`, Stage-0 Validium (`no_da`),
  the Prividium transaction filterer, and fake proofs.
- Prividium API, user panel, administration panel, and protected RPC.
- PostgreSQL and Keycloak with one administrator and two evaluation users.
- Block Explorer application, API, worker, and data fetcher.
- Caddy with automatic HTTPS.
- Prometheus, Grafana, and settlement-operator balance monitoring.

The default model has 14 long-running services and one successful one-shot
`chain-preflight` job. SSO, webhook, and institutional-demo implementations
remain in the repository as explicitly unsupported profiles and are not part
of the customer happy path.

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

The deployment produces four commit-safe public records:

| File | Purpose |
| --- | --- |
| `deployment/public/roles.md` | Generated public identities and roles |
| `deployment/public/manifest.json` | Protocol addresses, genesis, locks, and transaction hashes |
| `deployment/public/deployment-summary.md` | Healthy services and public endpoints |
| `deployment/public/happy-path.json` | Authenticated canary receipt and Explorer READY evidence |

Private keys, passwords, RPC credentials, and the age identity must never be
included in an evaluation report. See [the evaluation guide](runbooks/EVALUATION.md)
for the engineering and BD handoff.

## Repository structure

```text
.
├── crates/prividium-cli/            # Customer-facing Rust control plane
├── compose/                         # Compose entrypoint and service modules
├── deployment/                      # Input template, runtime reference, and public output
├── dev/                             # Container build and runtime assets
├── runbooks/                        # Setup, host, component, and evaluation guides
├── skills/deploy-prividium/         # Canonical agent deployment contract
├── .agents/skills/                  # Codex discovery link
├── .claude/skills/                  # Claude Code discovery link
├── tools/validate-stack             # Narrow Compose policy check used by CI
└── tests/                           # Focused agent-skill validation
```

`compose/compose.yaml` is the only Compose entrypoint. Component versions,
source commits, image digests, and retained unsupported profiles are recorded in
`deployment/versions.lock.yaml`.

The CLI is installed locally from the locked Rust source in the checkout. No
CLI executable or container image is published by this repository.
