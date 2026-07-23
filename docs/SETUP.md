# Deploy the Prividium Sepolia sandbox

This guide takes an enterprise engineer from an empty amd64 VPS to a working,
customer-hosted Prividium evaluation environment.

At the end you will have:

- a dedicated ZKsync ecosystem settled on Ethereum Sepolia;
- Prividium user, administration, protected API/RPC, Explorer, and OIDC
  interfaces on customer DNS with automatic HTTPS;
- monitoring and active Watchdog checks;
- public, commit-safe records of the identities, chain, and deployed release;
- protected funding and readiness records under `/etc/prividium/runtime`.

The environment is a single-VPS, fake-proof sandbox. It is not a production
custody design, production network, or officially supported public testnet.

## Time and irreversible actions

Plan for **2–4 hours elapsed time** after the prerequisites are available.

| Stage | Typical operator time | External wait | Reversible? |
| --- | ---: | ---: | --- |
| Host, DNS, registry, and RPC | 20–40 min | DNS/provider dependent | Yes |
| Identity and funding review | 15–25 min | Sepolia ETH acquisition/confirmation | Yes |
| Prepare and review the chain | 20–45 min | Image/source build dependent | Yes |
| Broadcast the ecosystem | 10–30 min | Sepolia inclusion dependent | **No** |
| Start and validate the stack | 20–45 min | DNS/ACME and service startup | Yes |

The main schedule risks are Sepolia ETH availability, insufficient RPC
capabilities, private registry access, DNS/ACME propagation, and a partially
completed irreversible broadcast. Resolve the first four before broadcasting.

## Before you begin

Use an x86-64 Linux VPS with Docker Engine, Docker Compose v2, and recommended
capacity of 8 vCPU, 16 GB RAM, and 200 GB SSD.

Allow inbound SSH, TCP 80/443, and UDP 443. Point these required `A` records to
the VPS:

| Name | Public interface |
| --- | --- |
| `app.<domain>` | User application |
| `admin.<domain>` | Administration application |
| `api.<domain>` | Authenticated Prividium API and RPC |
| `explorer.<domain>` | Block Explorer |
| `explorer-api.<domain>` | Explorer API |
| `idp.<domain>` | OIDC issuer |

Keep the private Sepolia RPC out of browser configuration. It must support
historical calls and logs, receipts, and EIP-4844 blob fee data. Provide a
separate public CORS-enabled Sepolia endpoint for browser-funded bridging.

Authenticate to the private image registry:

```bash
docker login quay.io
```

Run the environment check:

```bash
tools/sandbox doctor
```

Continue when required tools, Docker access, host architecture, and registry
prerequisites have no blocking result.

## 1. Generate identities

Run:

```bash
tools/sandbox init
```

You will be asked for:

| Input | Used for |
| --- | --- |
| Sandbox domain | Public URLs, CORS, callbacks, SIWE, and WebAuthn origins |
| ACME email | Certificate account notifications |
| Administrator email | The one initial core-realm administrator |
| Private Sepolia RPC | Deployment and server-side settlement |
| Browser Sepolia RPC | Public browser bridging without leaking provider credentials |
| age recipient | Encrypting all generated credentials |

The private RPC input is hidden. The command generates a high 31-bit chain ID,
independent random role and application keys, database passwords, and session
secrets. It commits none of those secrets. Its outputs are:

- `deployment/secrets/sandbox.enc.env` — SOPS encrypted, protected;
- `deployment/public/roles.md` — public addresses and role purposes only.

The encrypted environment is gitignored. Back it up to the customer’s approved
secret-storage system and keep the age private identity in a separate recovery
location. Both are required for recovery.

Completion message:

```text
Public role inventory written to .../deployment/public/roles.md
Next: tools/sandbox decrypt
```

`tools/sandbox roles` safely regenerates the public inventory after an approved
identity change.

## 2. Review the role inventory

Open `deployment/public/roles.md` before moving ETH. It presents four groups:

1. chain deployment and governance;
2. settlement operators;
3. sandbox funding;
4. service and passive accounts.

Confirm the domain and L2 chain ID are the intended values. The sandbox funding
wallet is clearly marked as the **only customer-funded address**. Do not send
ETH directly to the deployer, governor, owner, or operator addresses.

The optional SSO/bundler and institutional-demo identities are dormant and
outside the core one-ETH guarantee.

After review, commit `deployment/public/roles.md` as the first customer-specific
deployment record.

## 3. Create the protected runtime environment

Create the destination once:

```bash
sudo install -d -m 0700 -o "$USER" /etc/prividium/runtime
tools/sandbox decrypt
```

Completion message:

```text
Decrypted runtime environment written to /etc/prividium/runtime/sandbox.env with mode 0600
```

Private keys, passwords, and private provider URLs remain in the encrypted or
mode-`0600` environment. They never appear in generated reports.

## 4. Send 1 Sepolia ETH to one address

Generate the live plan:

```bash
tools/sandbox funding
```

The command derives addresses inside the SOPS child process, confirms the RPC
is Sepolia, queries confirmed balances, and writes:

```text
/etc/prividium/runtime/reports/funding-plan.md
```

The report includes the sponsor address, live balances, per-role targets,
current shortfalls, retained reserve, maximum transfer amount, and a
deterministic plan ID. If the sponsor is empty, the command returns nonzero
after still writing the report.

Send exactly **1 Sepolia ETH** to the sandbox funding wallet shown under
“Customer action.” Wait for confirmation, then rerun:

```bash
tools/sandbox funding
```

Continue when the report status is `READY`. The guarantee covers the default
core sandbox, a 14-day/2,016-batch operator runway, Watchdog’s 0.05 L2 ETH
target, transaction costs, reserve, and buffer. It does not cover SSO/bundler
or the institutional demo.

## 5. Review and apply the funding plan

Read the protected funding report. Confirm:

- every recipient matches `deployment/public/roles.md`;
- only confirmed shortfalls will be transferred;
- the sponsor retains the stated core reserve;
- the total policy allocation is no more than 0.90 ETH;
- at least 0.10 ETH remains unallocated.

Apply the exact plan:

```bash
tools/sandbox funding apply
```

Type the full plan ID when prompted. Each recipient is funded sequentially and
confirmed before the next transfer. A rerun sends only newly observed
shortfalls and normally becomes a no-op.

For controlled non-interactive execution:

```bash
CONFIRM_FUNDING=FUND_SEPOLIA_<FULL_PLAN_ID> tools/sandbox funding apply
```

The helper refuses to run if the sponsor has a pending nonce. If execution is
interrupted, wait for the pending transaction to settle and rerun; confirmed
balances are the source of truth and there is no local funding journal.

## 6. Prepare the chain

Run:

```bash
tools/sandbox prepare
```

This builds the locked zk-deployer and Protocol sources and simulates the
ecosystem/chain bootstrap without submitting transactions. Review:

- `/etc/prividium/runtime/chain/out/manifest.json`;
- `/etc/prividium/runtime/chain/out/preparation.json`;
- generated Safe bundles and calldata;
- the chain ID and rollup DA configuration;
- the locked commits in `deployment/versions.lock.yaml`.

The preparation record cryptographically binds the dry-run manifest to its
chain ID and locked source commits.

## 7. Review readiness and broadcast

Generate the pre-broadcast record:

```bash
tools/sandbox readiness
```

It writes `/etc/prividium/runtime/reports/readiness.md` and returns one result:

- `READY` — all blocking checks pass;
- `READY WITH WARNINGS` — all blocking checks pass, but DNS is unresolved;
- `BLOCKED` — do not broadcast.

Blocking checks cover protected configuration permissions, role identity,
Sepolia RPC capabilities, the release-benchmarked funding policy, confirmed
funding targets and reserve, chain-ID collision, preparation provenance,
source locks, Compose/architecture, private images, and manifest conflicts.
Unresolved DNS is a warning because it can complete while Sepolia transactions
settle.

Broadcast:

```bash
tools/sandbox broadcast
```

Broadcast reruns readiness automatically; there is no bypass flag. It then asks
for the L2 chain ID and submits irreversible Sepolia transactions. For
automation, the exact authorization is:

```bash
CONFIRM_BROADCAST=BROADCAST_SEPOLIA_<L2_CHAIN_ID> tools/sandbox broadcast
```

A partial broadcast can leave real Sepolia contracts even if the command
fails. Do not generate a new chain ID or discard runtime state. Preserve the
output and follow the incident guidance in the operations runbook.

Success creates `deployment/public/manifest.json`. Review and commit that
non-secret record. After it exists, core deployment-role distribution is
disabled to avoid accidentally replenishing spent one-time accounts.

## 8. Deploy and review the final record

Run:

```bash
tools/sandbox deploy
```

The command renders browser configuration, validates Compose, builds maintained
images, starts the core stack, and waits up to ten minutes for:

- all core long-running services to run and all one-shot jobs to complete;
- HTTPS for user, administration, API, Explorer, and Explorer API;
- the strict OIDC discovery issuer.

Only after those checks pass does it write:

```text
deployment/public/deployment-summary.md
```

The summary contains URLs, versions, chain identity, enabled capabilities,
on-chain addresses, health results, and sandbox limitations. It is commit-safe.

If checks fail, deploy returns nonzero and writes:

```text
/etc/prividium/runtime/reports/deployment-summary.incomplete.md
```

It never overwrites an earlier successful public summary. Inspect
`tools/sandbox status` and `tools/sandbox logs`, fix the cause, then run:

```bash
tools/sandbox summary
```

## 9. Complete the human acceptance checks

Automated startup is necessary but not the full product evaluation. Confirm:

- the administrator changes the temporary password, logs in, and registers
  WebAuthn with user verification;
- unauthenticated RPC is denied and authenticated transaction submission works;
- a user-funded Sepolia deposit and withdrawal complete;
- Explorer indexes the authenticated transaction;
- Watchdog’s RPC, SIWE/auth, 1-wei transfer, and settlement flows remain healthy
  across at least two batches;
- only SSH and Caddy are publicly reachable;
- Grafana is reachable only through
  `ssh -L 3100:127.0.0.1:3100 user@vps`.

## Optional capabilities

Add `auth` and `auth-api` DNS records before SSO, and `demo` before the
institutional demo.

```bash
tools/sandbox edit-secrets
# Set BUNDLER_ENABLED=true and/or WEBHOOK_ENABLED=true.
tools/sandbox decrypt

tools/sandbox enable sso
tools/sandbox enable webhook
tools/sandbox enable demo
```

SSO/bundler and demo commands explicitly state that they are outside the core
1 ETH guarantee and run an incremental sandbox-funding-wallet preflight.
Webhook has no service-wallet funding requirement. All setup jobs remain
idempotent.

For restarts, upgrades, backups, certificates, provider changes, SOPS recovery,
and incident handling, use the [operations runbook](RUNBOOK.md).
