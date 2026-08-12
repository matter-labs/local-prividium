# Deploy the Prividium Sepolia sandbox

This is the manual path from a prepared VPS to a verified Prividium evaluation.
The `deploy-prividium` skill drives the same CLI workflow and is the preferred
path for agents.

The sandbox is a single-host, fake-proof Sepolia deployment. It is not a
production network, custody model, or supported public testnet.

## 1. Supply a deployment-ready host

Host provisioning is deliberately outside this repository. The customer
engineer remains responsible for operating-system installation, accounts,
SSH, sudo policy, patching, firewall policy, Docker configuration, storage,
backups, and provider resources.

Before cloning, provide:

- a dedicated Linux `amd64` VPS; Ubuntu Server 24.04 LTS is the qualified
  target;
- expected capacity of 8 vCPU, 16 GB RAM, and a nominal 200 GB
  nonrotational SSD;
- a user that can run Docker Engine and Docker Compose v2;
- Git, Rust 1.90.0 with Cargo, `age`, `age-keygen`, SOPS, and Foundry `cast`;
- a real directory at `/etc/prividium/runtime`, owned by the deployment user
  with mode `0700`;
- outbound DNS and HTTPS access to GitHub, the Rust crate registry, Docker Hub,
  Quay, Chainlist, and both configured Sepolia RPC endpoints;
- a public IPv4 address and inbound routing for the chosen SSH port, TCP 80,
  TCP 443, and UDP 443; and
- control of the sandbox DNS zone.

The 8-vCPU, 16-GB, and 200-GB SSD figures are planning requirements, not CLI
gates. The CLI does not inspect CPU count, memory size, disk capacity, disk
media, SSH policy, sudo configuration, host firewall rules, package state, or
OS update policy.

Use the customer's approved host and security procedures to satisfy these
requirements. See [the host prerequisites](HOST_CONTRACT.md) for the exact
boundary.

## 2. Clone and start the agent

Clone the public repository over HTTPS:

```bash
git clone https://github.com/matter-labs/local-prividium.git
cd local-prividium
```

The CLI is built from this checkout and is not published. Confirm the
source-build toolchain, install the locked binary locally, and verify it:

```bash
rustc --version
cargo --version
cargo install --path crates/prividium-cli --locked --bin prividiumcli
prividiumcli --version
```

Installation needs access to the Rust crate registry and may take several
minutes. It places `prividiumcli` in Cargo's configured binary directory for
the current user. The repository does not install Rust or publish a binary.

Install and authenticate Codex CLI or Claude Code, start it from the repository,
and invoke:

```text
Codex:       $deploy-prividium
Claude Code: /deploy-prividium
```

Agents should use `prividiumcli --output json status` at the start of every
session. It reports the next Prividium action from durable artifacts without
auditing or changing the host.

## 3. Create the human input file

Create a protected copy of the input template:

```bash
install -m 0600 deployment/input.env.example deployment/input.env
```

Edit it directly on the VPS:

```dotenv
SANDBOX_DOMAIN=sandbox.example.com
ACME_EMAIL=platform@example.com
SEPOLIA_RPC_URL="https://private-archive-sepolia-rpc.example.com"
SEPOLIA_BROWSER_RPC_URL="https://public-browser-sepolia-rpc.example.com"
# Optional: L2_CHAIN_ID=1900000001
```

`SEPOLIA_RPC_URL` must be an archive-capable private Sepolia endpoint that
supports historical calls and logs, receipts, and blob-fee behavior. Keep its
credential out of chat and terminal logs. `SEPOLIA_BROWSER_RPC_URL` must be a
different public HTTPS endpoint that permits browser CORS.

When `L2_CHAIN_ID` is omitted, initialization generates an ID in
`1073741824..2147483647`. Supply one only for an approved allocation.

The parser accepts blank lines, comments, and quoted or unquoted values. It
rejects missing, duplicate, unknown, malformed, shell-expansion, or escaped
content, symlinks, and modes other than `0600`. Values are never printed.

`deployment/sandbox.env.example` is not an input file. It documents the
generated runtime shape and supports static Compose validation.

## 4. Initialize encrypted configuration

Run:

```bash
prividiumcli init
```

Initialization generates the L2 chain ID when needed, protocol and service
identities, the funding wallet, database secrets, and random evaluation
passwords. Verify these outputs:

| Path | Purpose |
| --- | --- |
| `deployment/secrets/sandbox.enc.env` | SOPS-encrypted configuration and secrets |
| `deployment/secrets/age.key` | Mode-`0600` local decryption identity |
| `deployment/public/roles.md` | Public, commit-safe identities and roles |

After encrypting and verifying the result, `init` removes the default
`deployment/input.env`. If initialization fails, the input remains available
for correction. Back up the encrypted environment and age identity together
using approved secret storage.

## 5. Configure DNS, network access, and Quay

Create these public IPv4 `A` records pointing to the VPS:

```text
app.<domain>
admin.<domain>
api.<domain>
explorer.<domain>
explorer-api.<domain>
idp.<domain>
```

All six must resolve before deployment. Do not add `AAAA` records unless IPv6
routing and security policy are configured end to end.

The host engineer decides how to implement ingress policy. The application
expects public TCP 80/443 and UDP 443, administrative SSH access, and no public
exposure for database, Prometheus, Keycloak administration, Grafana, or raw
ZKsync OS RPC. Grafana intentionally binds to `127.0.0.1:3100` for an SSH
tunnel. The CLI does not inspect or modify firewall state.

Matter Labs DevOps supplies a pull-only Quay credential. Authenticate directly
in a private SSH terminal without placing the token in a file, argument, or
agent conversation:

```bash
read -r -p 'Quay username: ' QUAY_USERNAME
read -r -s -p 'Quay token: ' QUAY_TOKEN
printf '\n'
printf '%s' "$QUAY_TOKEN" |
  docker login quay.io --username "$QUAY_USERNAME" --password-stdin
unset QUAY_USERNAME QUAY_TOKEN
```

The workflow pulls the existing digest-pinned product images. It never pushes,
publishes, or signs images. Preparation builds only the repo-local
`chain-bootstrap` and `operator-balance-exporter` helpers.

## 6. Fund protocol identities

Inspect and reconcile the required Sepolia balances:

```bash
prividiumcli fund --list
prividiumcli fund
```

If the generated funding wallet is short, send only the additional Sepolia ETH
reported by the command. Run `fund` again and explicitly approve distribution
to the six generated protocol roles. The target includes a small reserve in
the funding wallet for the acceptance canary.

Funding is resumable. The CLI reconciles current balances and durable evidence
rather than repeating completed transfers.

## 7. Validate and prepare

Run:

```bash
prividiumcli preflight
prividiumcli prepare
```

Application preflight checks only deployment dependencies: Linux amd64,
required commands, protected runtime access, encrypted configuration, RPC
capabilities, chain-ID availability, Docker and Compose, digest-pinned image
pulls, generated identities, funding, and DNS resolution. DNS is a warning at
preparation time and required by `deploy`.

`prepare` pulls the locked product images, builds the two local helpers, builds
the pinned zk-deployer/protocol helper locally, and simulates the Stage-0
Validium (`da_mode: no_da`) deployment. It submits no transactions. Preserve
`/etc/prividium/runtime/chain/out/preparation.json`; broadcast uses exactly the
helper image that produced this preparation.

## 8. Review and broadcast to Sepolia

Run once without confirmation:

```bash
prividiumcli broadcast
```

Review the network, L2 chain ID, domain, deployer, preparation timestamp, and
prepared-manifest digest. Interactive use requires typing the L2 chain ID.
Agent use must obtain explicit human approval before supplying the displayed
confirmation value.

This creates irreversible Sepolia contracts. If broadcast may have begun and
then fails, do not rerun it, regenerate identities, or remove runtime state.
Preserve the output and inspect the recorded and on-chain transaction state.

Success writes `deployment/public/manifest.json` and includes the Stage-0
Validium ecosystem, Prividium transaction filterer, required administrative
sender whitelist, and normal deposits.

## 9. Deploy the core stack

After all six DNS names resolve, run:

```bash
prividiumcli deploy
```

Success requires 14 healthy long-running services and the successful
`chain-preflight` one-shot job. It writes
`deployment/public/deployment-summary.md` and validates the public HTTPS
interfaces, strict OIDC discovery, and rejection of unauthenticated protected
RPC access.

```text
https://app.<domain>
https://admin.<domain>
https://api.<domain>
https://explorer.<domain>
https://explorer-api.<domain>
https://idp.<domain>/realms/prividium
```

SSO, webhook, and institutional-demo profiles are retained in the repository
but unsupported for this happy path.

## 10. Confirm the product happy path

Run once without confirmation:

```bash
prividiumcli verify
```

The command proves a generated non-admin OIDC user can call authenticated
`eth_chainId`, then pauses before the Sepolia canary deposit. Review its
generated address, chain, value, and purpose, then authorize the exact displayed
confirmation:

```bash
CONFIRM_CANARY=CANARY_SEPOLIA_<L2_CHAIN_ID> prividiumcli verify
```

The command resumes an existing canary, waits for its authenticated L2 receipt,
and confirms Explorer indexing. It does not wait for or poll batch settlement.
Afterward, this reports `READY` without repeating funding, broadcast, or the
canary:

```bash
prividiumcli --output json status
```

## 11. Reveal evaluation credentials

Only when an authorized human requests them, run outside an agent transcript:

```bash
prividiumcli credentials show
```

The command requires an interactive terminal and typing `SHOW`. It refuses
redirected output and displays only evaluation URLs and three generated logins.

## Evidence and cleanup

Retain only these commit-safe records in the evaluation report:

```text
deployment/public/roles.md
deployment/public/manifest.json
deployment/public/deployment-summary.md
deployment/public/happy-path.json
```

Never share the age identity, SOPS file, decrypted runtime, private RPC URL,
passwords, registry token, or private keys.

There is no automated uninstall command. At the end of the evaluation, revoke
Quay and RPC credentials, remove DNS, and destroy the VPS and its volumes unless
retention is explicitly approved. Sepolia contracts and transactions cannot be
removed; never reuse their evaluation keys.
