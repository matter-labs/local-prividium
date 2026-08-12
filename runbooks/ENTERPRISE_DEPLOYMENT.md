# Enterprise deployment guide

This guide directs a customer engineering team through deploying and qualifying
the Prividium evaluation sandbox in a customer-controlled environment. It
explains the purpose of each activity, the change being made, the responsible
party, and the evidence required before proceeding.

| Document attribute | Value |
| --- | --- |
| Audience | Platform engineers, security engineers, blockchain engineers, and deployment agents |
| Environment | One customer-managed Linux amd64 VPS |
| Settlement network | Ethereum Sepolia |
| Deployment model | Stage-0 Validium (`da_mode: no_da`) with fake proofs |
| Supported application scope | Fourteen-service Prividium core stack |
| Command-line interface | `prividiumcli`, installed from this repository |
| Completion state | `READY` |

> [!CAUTION]
> This deployment is an evaluation environment. It uses fake proofs, a testnet
> verifier, locally managed hot keys, and a single host. It is not a production
> architecture, custody design, or high-availability service. Do not use it to
> secure assets of value.

## 1. Intended outcome

At completion, the customer has a private Prividium-enabled ZKsync ecosystem
running on its own VPS. The deployment includes:

- a dedicated L2 settled on Ethereum Sepolia;
- Stage-0 Validium operation using `no_da`;
- the Prividium transaction filterer and required administrative sender
  authorization;
- normal deposits from Sepolia to the L2;
- Prividium user, administration, API, and protected RPC interfaces;
- Keycloak-backed identity with generated administrator and non-administrator
  evaluation users;
- Block Explorer indexing; and
- Prometheus, Grafana, and settlement-operator balance monitoring.

The deployment is considered `READY` only when a generated non-administrator
user successfully authenticates, calls protected RPC, receives a canary deposit
on the configured L2, and observes the transaction in Explorer. `READY` does
not require waiting for batch settlement on Sepolia.

The retained SSO, webhook, bundler, and institutional-demo profiles are not
supported by this procedure and must remain disabled.

## 2. Operating model and responsibilities

The repository owns the Prividium application lifecycle. It does not own the
customer's host or infrastructure lifecycle.

| Responsibility | Customer platform team | Matter Labs | CLI or deployment agent |
| --- | :---: | :---: | :---: |
| VPS, operating system, accounts, SSH, and sudo policy | Owner | — | No changes |
| Hardware sizing, storage, patching, backup, and recovery | Owner | — | No changes |
| Provider and host firewall policy | Owner | — | No changes |
| DNS records and public IP | Owner | — | Validates DNS when required |
| Sepolia RPC procurement and credentials | Owner | — | Validates capability without displaying secrets |
| Sepolia ETH | Owner | — | Calculates and reconciles required balances |
| Pull-only Quay credential | Consumer | Issuer | Validates access to locked images |
| Repository source and locked deployment definitions | Consumer | Provider | Enforces the checked-out definitions |
| Generated evaluation identities and secrets | Custodian | — | Generates and encrypts locally |
| Protocol simulation, deployment, and application startup | Approver | — | Executes through explicit lifecycle commands |
| Funding, broadcast, and canary authorization | Approver | — | Stops before each gated write |

This division is intentional. It allows the customer's existing security and
change-management controls to remain authoritative while keeping the product
deployment deterministic and agent-operable.

## 3. Lifecycle and approval gates

The workflow separates read-only validation, local preparation, and external
writes. A deployment request is not authorization for a later irreversible
action.

| Phase | Primary command | Persistent or external effect | Explicit approval |
| --- | --- | --- | :---: |
| Determine current state | `prividiumcli status` | None | No |
| Generate protected configuration | `prividiumcli init` | Local encrypted secrets and public roles | Input completion |
| Inspect funding | `prividiumcli fund --list` | None | No |
| Reconcile role funding | `prividiumcli fund` | Sepolia ETH transfers when shortfalls exist | Yes |
| Validate readiness | `prividiumcli preflight` | None | No |
| Simulate deployment | `prividiumcli prepare` | Protected local build and simulation artifacts | No |
| Deploy protocol | `prividiumcli broadcast` | Irreversible Sepolia transactions | Yes |
| Start services | `prividiumcli deploy` | Containers, volumes, and runtime state | No |
| Prove authenticated access | `prividiumcli verify` | Read-only until the canary checkpoint | No |
| Submit acceptance canary | `prividiumcli verify` with confirmation | Minimal Sepolia-to-L2 deposit | Yes |
| Reveal evaluation logins | `prividiumcli credentials show` | Displays sensitive credentials in the terminal | Yes |

## 4. Prerequisites and required decisions

### 4.1 Host handoff

**What is required:** A dedicated Linux amd64 VPS prepared according to
[Prividium VPS prerequisites](HOST_CONTRACT.md).

**Why it is required:** The core stack combines a blockchain node, databases,
identity, Explorer, application services, and monitoring on one machine.
Predictable capacity and network ownership reduce deployment ambiguity during
the evaluation.

The planned capacity is 8 vCPU, 16 GB RAM, and a nominal 200 GB nonrotational
SSD. These values are documented planning requirements; the CLI does not
measure or enforce them. The platform team must also provide Docker Engine,
Docker Compose v2, the required local tools, and an operator-owned mode-`0700`
directory at `/etc/prividium/runtime`.

The CLI does not install packages, modify accounts, configure SSH, change
firewalls, or remediate the host. Missing host prerequisites are returned to
the platform team.

### 4.2 Customer-provided values

The following values must be approved before initialization:

| Input | What it controls | Why it is needed | Handling requirement |
| --- | --- | --- | --- |
| `SANDBOX_DOMAIN` | Base domain for all public services | Establishes stable HTTPS and OIDC issuer URLs | Public after deployment |
| `ACME_EMAIL` | Caddy ACME registration contact | Enables automated certificate lifecycle notices | Treat as customer contact data |
| `SEPOLIA_RPC_URL` | Private deployment and settlement RPC | Provides archive-capable Sepolia access for protocol operations | Secret; never paste into chat or reports |
| `SEPOLIA_BROWSER_RPC_URL` | Browser-facing Sepolia RPC | Allows supported browser-origin RPC access with CORS | Public URL; must differ from the private RPC |
| `L2_CHAIN_ID` | Numeric identity of the new L2 | Prevents ambiguity across wallets and integrations | Optional; omit unless an allocation is approved |

When `L2_CHAIN_ID` is omitted, initialization generates a value in
`1073741824..2147483647` and checks it against Chainlist.

The team must also have:

- control of the domain's DNS zone;
- a pull-only Quay credential issued by Matter Labs DevOps; and
- sufficient Sepolia ETH for the generated deployment and settlement roles.

## 5. Deployment procedure

Run all commands from the root of the same repository checkout. The CLI uses
that checkout's Compose definitions, build context, and version lock.

### 5.1 Record the approved source and install the CLI

**What you are doing:** Selecting the exact repository revision and compiling
the customer-facing deployment command from its locked Rust source.

**Why:** The CLI is not published as a binary. Building from the approved
checkout binds execution to the reviewed source and `Cargo.lock` dependency
set.

```bash
git clone https://github.com/matter-labs/local-prividium.git
cd local-prividium
git rev-parse HEAD
rustc --version
cargo --version
cargo install --path crates/prividium-cli --locked --bin prividiumcli
prividiumcli --version
```

Record the Git commit in the evaluation change record. `cargo install` places
the binary in Cargo's configured binary directory for the current user. If the
command is not found, correct that user's `PATH` using the organization's
approved Rust toolchain procedure.

After moving to another approved repository revision, reinstall with `--force`
so the command matches the active checkout:

```bash
cargo install --path crates/prividium-cli --locked --bin prividiumcli --force
```

**Completion evidence:** `prividiumcli --version` succeeds and the approved Git
commit is recorded.

### 5.2 Start or resume the workflow

**What you are doing:** Reading durable deployment evidence to determine the
next incomplete stage.

**Why:** Funding transfers, protocol transactions, and canary submission must
not be repeated merely because an agent session or SSH connection ended.

Humans may use:

```bash
prividiumcli status
```

Agents must use:

```bash
prividiumcli --output json status
```

An agent should follow `next_action` only when `requires_confirmation` is
false. It must stop when confirmation is required or when no safe next action
is returned.

**Completion evidence:** The command returns a recognized lifecycle stage and
the team continues from that stage rather than starting over.

### 5.3 Create the protected input

**What you are doing:** Supplying the small set of customer-controlled values
that cannot be safely or correctly generated by the repository.

**Why:** Domain ownership, ACME contact, RPC providers, and any reserved chain
ID are external business and infrastructure decisions.

Create the protected file:

```bash
install -m 0600 deployment/input.env.example deployment/input.env
```

An authorized engineer edits `deployment/input.env` directly on the VPS:

```dotenv
SANDBOX_DOMAIN=sandbox.example.com
ACME_EMAIL=platform@example.com
SEPOLIA_RPC_URL="https://private-archive-sepolia-rpc.example.com"
SEPOLIA_BROWSER_RPC_URL="https://public-browser-sepolia-rpc.example.com"
# Optional: L2_CHAIN_ID=1900000001
```

Do not provide private RPC credentials through an agent conversation. Do not
source this file in a shell. The CLI parses it as strict data and rejects
unknown, duplicate, malformed, shell-shaped, symlinked, or incorrectly
permissioned input.

**Completion evidence:** The file is a regular file with mode `0600`, and the
authorized engineer confirms all required values are complete.

### 5.4 Initialize encrypted configuration

**What you are doing:** Generating unique protocol, settlement, service, and
evaluation identities; creating service credentials; and encrypting the full
runtime configuration with SOPS and age.

**Why:** Every deployment requires distinct identities and secrets. Generating
them on the customer host avoids transporting private keys through chat,
source control, or a shared provisioning service.

```bash
prividiumcli init
```

The command validates its input, generates the role set, encrypts the complete
environment, verifies decryption, writes a public role inventory, and removes
the default plaintext input only after verification succeeds.

| Output | Classification | Purpose |
| --- | --- | --- |
| `deployment/secrets/sandbox.enc.env` | Secret, encrypted | Complete runtime configuration |
| `deployment/secrets/age.key` | Secret, mode `0600` | Local decryption identity |
| `deployment/public/roles.md` | Public | Role addresses, purposes, chain ID, and funding wallet |

Back up the encrypted environment and age identity together using approved
secret storage. The encrypted environment cannot be recovered without the age
identity.

**Completion evidence:** Both secret files are nonempty regular files,
`roles.md` exists, and the default plaintext input no longer exists.

### 5.5 Establish external connectivity

**What you are doing:** Connecting the customer-controlled network and domain
to the application endpoints, and authenticating Docker for private image
pulls.

**Why:** Caddy requires public DNS and ingress for certificates and HTTPS.
Prividium product images are existing, digest-pinned artifacts hosted in Quay.

Create these public IPv4 `A` records pointing to the VPS:

```text
app.<domain>
admin.<domain>
api.<domain>
explorer.<domain>
explorer-api.<domain>
idp.<domain>
```

The application expects public TCP 80/443 and UDP 443, together with the
customer's chosen SSH access. PostgreSQL, Prometheus, Keycloak administration,
and raw ZKsync OS RPC must remain private. Grafana binds to
`127.0.0.1:3100` for access through an SSH tunnel. The customer decides how to
implement these controls; the CLI does not inspect or change firewall policy.

Authenticate to Quay in a private terminal using the pull-only credential and
`docker login quay.io --password-stdin`. Never put the token in a command-line
argument, input environment, Git, or agent conversation.

No step in this workflow pushes, publishes, or signs an image. The CLI pulls
the approved digest-pinned product images and builds only repository-local
helpers that have no registry artifact.

**Completion evidence:** All six names resolve to the VPS, required ingress is
available, internal services remain private, and Docker is authenticated for
the locked Quay images.

### 5.6 Fund the generated roles

**What you are doing:** Supplying Sepolia ETH to the distinct identities used
for ecosystem deployment, governance, and ongoing commit/prove/execute
operations.

**Why:** Role separation makes the evaluation topology representative and
allows each operational balance to be monitored independently. The customer
funds only the generated funding wallet; the CLI calculates and distributes
the exact role shortfalls.

Inspect the purpose and current requirement:

```bash
prividiumcli fund --list
prividiumcli fund
```

If the funding wallet is short, send only the additional amount reported by
the CLI to the public funding address in `roles.md`. Then run
`prividiumcli fund` again in a private interactive terminal.

The CLI displays the six target transfers and pauses for approval. Approving
this checkpoint authorizes only the displayed Sepolia funding transfers. It
does not authorize protocol deployment. The requested balance also retains a
small reserve for the later acceptance canary.

Funding reconciliation is resumable: already satisfied balances are not sent
again.

**Completion evidence:** `prividiumcli --output json status` reports `FUNDED`
or identifies `prividiumcli preflight` as the next action.

### 5.7 Validate application readiness

**What you are doing:** Running a no-transaction validation of all inputs and
external dependencies needed for deterministic preparation.

**Why:** Discovering an RPC, registry, role, funding, chain-ID, Docker, or
configuration problem before simulation avoids partial protocol deployment.

```bash
prividiumcli preflight
```

Preflight checks:

- Linux amd64 compatibility and required local commands;
- protected runtime-directory ownership and permissions;
- encrypted configuration and generated role integrity;
- private and browser RPC identity and capabilities;
- L2 chain-ID range and Chainlist availability;
- Docker Engine, Compose v2, and the rendered stack;
- pull access to the locked private images;
- role funding and canary reserve; and
- the six DNS names.

DNS is reported as a warning during preparation but is mandatory before
deployment. Hardware capacity and customer host policy are not inspected.

**Completion evidence:** The command completes successfully with no transaction
submitted and identifies `prividiumcli prepare` as the next action.

### 5.8 Build and simulate the protocol deployment

**What you are doing:** Producing the exact local deployment helper, simulating
the ecosystem and chain deployment, pulling locked service images, and
recording provenance.

**Why:** Simulation verifies the deployment inputs and creates a reviewable
boundary before irreversible Sepolia transactions. Recording the helper image
identity ensures broadcast uses the same image that produced the simulation.

```bash
prividiumcli prepare
```

Preparation:

- builds the locked zk-deployer/protocol helper locally;
- configures Stage-0 Validium with `da_mode: no_da`;
- simulates ecosystem, chain, and transaction-filterer deployment;
- pulls existing product and supporting images by locked digest;
- builds the local `chain-bootstrap` and
  `operator-balance-exporter` helpers; and
- writes protected preparation evidence beneath
  `/etc/prividium/runtime/chain`.

It does not submit an Ethereum transaction or publish an image.

**Completion evidence:**
`/etc/prividium/runtime/chain/out/preparation.json` exists and
`prividiumcli status` reports `READY_TO_BROADCAST`.

### 5.9 Review and authorize protocol broadcast

**What you are doing:** Deploying the prepared ecosystem, L2 chain, testnet
verifier configuration, and Prividium transaction filterer to Sepolia.

**Why:** These transactions are irreversible and consume Sepolia ETH. The
human approver must verify that the prepared chain and domain match the change
record before authorizing them.

First run without confirmation:

```bash
prividiumcli broadcast
```

Review the displayed:

- settlement network;
- L2 chain ID;
- sandbox domain;
- deployer address;
- preparation timestamp; and
- prepared-manifest digest.

Interactive human use requires entering the displayed chain ID. An agent must
stop, present the review data, obtain explicit authorization for that exact
deployment, and only then use the displayed confirmation value:

```bash
CONFIRM_BROADCAST=BROADCAST_SEPOLIA_<L2_CHAIN_ID> prividiumcli --output json broadcast
```

The original request to deploy the sandbox is not sufficient authorization
for this transaction boundary.

If broadcast starts and then fails or the session disconnects, do not rerun
the command, delete runtime state, or regenerate identities. Preserve
`/etc/prividium/runtime/chain`, the CLI result, and all transaction evidence.
`BROADCAST_REVIEW_REQUIRED` intentionally has no automatic retry instruction.

**Completion evidence:** `deployment/public/manifest.json` records the chain,
contract addresses, transaction hashes, genesis data, locked versions,
filterer registration, administrative whitelist, and deposit configuration.

### 5.10 Start and validate the core stack

**What you are doing:** Starting the persistent application, identity,
Explorer, chain, proxy, database, and monitoring services.

**Why:** Contract deployment alone does not establish a usable product. The
services must agree on chain identity, permissions, OIDC issuer, and protected
RPC behavior.

```bash
prividiumcli deploy
```

The command validates DNS and protected runtime state, starts the Compose
model, waits for real service health, runs `chain-preflight`, checks public
HTTPS and strict OIDC discovery, and confirms unauthenticated protected RPC is
rejected.

The supported model contains fourteen long-running services. Optional SSO,
webhook, bundler, and demo services must not be activated.

**Completion evidence:** All fourteen services are healthy,
`chain-preflight` succeeds, and
`deployment/public/deployment-summary.md` exists.

### 5.11 Prove the authenticated product path

**What you are doing:** Confirming that a normal generated user can authenticate
and use protected RPC, then sending one minimal deposit to a newly generated
canary address and confirming Explorer indexing.

**Why:** Container health does not prove the customer-facing identity,
permission, RPC, bridge, transaction, and indexing path works end to end.

First run without canary authorization:

```bash
prividiumcli verify
```

The command logs in as a generated non-administrator OIDC user and calls
authenticated `eth_chainId`. It then stops before the Sepolia write and
displays the canary address, L2 chain ID, value, purpose, and confirmation
token.

After a separate human approval for that exact canary:

```bash
CONFIRM_CANARY=CANARY_SEPOLIA_<L2_CHAIN_ID> prividiumcli --output json verify
```

The command resumes any durable canary submission, waits for its authenticated
L2 receipt, and confirms Explorer indexing. It does not wait for or poll batch
settlement on Sepolia.

**Completion evidence:** `deployment/public/happy-path.json` exists and:

```bash
prividiumcli --output json status
```

reports `stage: READY` and `ready: true` without repeating funding, broadcast,
or canary submission.

### 5.12 Retrieve evaluation credentials when authorized

**What you are doing:** Revealing the generated administrator and evaluation
user credentials to an authorized human.

**Why:** Credentials are needed for interactive product evaluation but must not
be exposed through agent output, redirected logs, or shared evidence.

Run only in a private interactive terminal outside the agent transcript:

```bash
prividiumcli credentials show
```

The command refuses redirected output and requires entering `SHOW`. Clear or
close the terminal after securely transferring the credentials through the
customer's approved channel.

## 6. Agent control contract

Agents must add `--output json` to every CLI command they execute and treat
stdout as one versioned result document. Progress and prompts are emitted on
stderr.

The stable control fields are:

| Field | Agent behavior |
| --- | --- |
| `outcome` | Branch on `complete`, `action_required`, `review_required`, or `failed` |
| `stage` | Identify the durable lifecycle state when present |
| `next_action.command` | Execute only when it is safe and applicable |
| `next_action.requires_confirmation` | Stop and obtain explicit approval when `true` |
| `error.code` | Use for deterministic error handling; do not parse prose |
| `data` | Read non-secret command-specific evidence |

Exit codes have fixed meaning:

| Exit code | Meaning | Required response |
| ---: | --- | --- |
| `0` | Command completed | Continue according to `next_action` |
| `2` | Human action or manual review required | Stop and present the checkpoint |
| `1` | Validation or execution failure | Report the error; remediate only within scope |
| `64` | Invalid CLI invocation | Correct the agent command |

The complete agent procedure is defined in
[`deploy-prividium`](../skills/deploy-prividium/SKILL.md).

## 7. Resume and interruption policy

Always begin a new session with `prividiumcli --output json status`.

| Reported stage | Meaning | Permitted response |
| --- | --- | --- |
| `CONFIGURATION_REQUIRED` | Protected configuration is absent | Complete input and run `init` |
| `FUNDING_REQUIRED` | Roles or canary reserve are below target | Reconcile with `fund` |
| `FUNDED` | Funding evidence is complete | Run `preflight`, then `prepare` |
| `READY_TO_BROADCAST` | Simulation is complete | Perform the broadcast approval gate |
| `BROADCAST_REVIEW_REQUIRED` | An approved broadcast may be incomplete | Stop; inspect recorded and on-chain state |
| `READY_TO_DEPLOY` | Public manifest exists | Run `deploy` |
| `DEPLOYMENT_INCOMPLETE` | Service readiness failed | Review protected diagnostics and resume `deploy` |
| `READY_TO_VERIFY` | Core services are healthy | Perform authenticated verification and canary gate |
| `CANARY_REVIEW_REQUIRED` | Canary evidence is ambiguous | Stop; inspect before retrying |
| `READY` | Required product evidence is complete | Do not repeat write operations |

Never delete protected runtime or regenerate identities to bypass a review
stage. Those actions can destroy the link between local evidence and
irreversible Sepolia state.

## 8. Evidence, records, and secret handling

### 8.1 Approved evaluation evidence

These files are designed to be commit-safe and may be attached to an approved
evaluation report after review:

```text
deployment/public/roles.md
deployment/public/manifest.json
deployment/public/deployment-summary.md
deployment/public/happy-path.json
```

Together they establish who the generated public roles are, what was deployed,
which services passed readiness, and which authenticated transaction proved the
happy path.

### 8.2 Restricted material

Never commit, attach to a ticket, paste into chat, or include in a sales or
evaluation report:

- `deployment/secrets/age.key`;
- `deployment/secrets/sandbox.enc.env` unless transferred through approved
  encrypted backup controls;
- `/etc/prividium/runtime`;
- private RPC URLs or credentials;
- Quay credentials;
- private keys, keystores, passwords, or decrypted environment values; or
- terminal output from `prividiumcli credentials show`.

Record human interventions by timestamp, actor, action, and outcome only. Do
not record the associated secret value.

## 9. Failure handling and escalation

Use the narrowest responsible owner:

- Host, Docker access, disk, package, SSH, firewall, or provider failures go to
  the customer platform team.
- DNS and public routing failures go to the customer network or DNS owner.
- RPC capability or quota failures go to the RPC owner.
- Quay authorization failures go to Matter Labs DevOps; credentials require
  pull access only.
- Funding shortfalls go to the Sepolia funding approver.
- `review_required` after broadcast or canary submission goes to a blockchain
  engineer for evidence and on-chain inspection.
- Product or contract failures with intact prerequisites retain all protected
  diagnostics and go to Matter Labs engineering.

For service diagnostics, inspect state without printing the decrypted runtime:

```bash
docker compose \
  -f compose/compose.yaml \
  --env-file /etc/prividium/runtime/sandbox.env \
  ps --all
```

Do not improvise alternate deployment, contract, funding, or recovery commands
when the CLI has stopped at a controlled review boundary.

## 10. Completion and handoff

The technical owner may approve the evaluation for handoff when all of the
following are true:

- `prividiumcli status` reports `READY`;
- the fourteen core services and `chain-preflight` passed;
- the public manifest records Stage-0 Validium and the registered Prividium
  transaction filterer;
- a generated non-administrator user authenticated successfully;
- authenticated RPC returned the configured L2 chain ID;
- the canary deposit has an authenticated L2 receipt;
- Explorer indexed the canary transaction;
- unauthenticated protected RPC is rejected;
- internal-only services are not publicly reachable; and
- the four public evidence files have been reviewed for handoff.

Use [Engineering evaluation and BD handoff](EVALUATION.md) for the product
evaluation and stakeholder report after technical completion.

## 11. End-of-evaluation controls

There is no automated uninstall command. At the approved end of the
evaluation:

1. Retain only approved evidence and explicitly approved secret backups.
2. Revoke the pull-only Quay credential.
3. Revoke or rotate evaluation-specific RPC credentials.
4. Remove the six DNS records.
5. Destroy the VPS and attached volumes unless continued retention is approved.
6. Record the cleanup owner, date, and result.

Sepolia contracts and transactions cannot be removed. Never reuse evaluation
identities for another environment or for assets of value.

## Related documentation

- [Documentation index](README.md)
- [Detailed sequential setup](SETUP.md)
- [VPS prerequisites and ownership boundary](HOST_CONTRACT.md)
- [Deployment components](COMPONENTS.md)
- [Engineering evaluation and BD handoff](EVALUATION.md)
