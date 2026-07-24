# Deploy the Prividium Sepolia sandbox

This technical companion takes an enterprise engineer from a prepared amd64
VPS containing the approved release checkout to a working, customer-hosted
Prividium evaluation environment.

> [!IMPORTANT]
> Start with the [Enterprise Adoption
> Guide](enterprise-adoption/README.md). Its [core deployment
> playbook](enterprise-adoption/03-core-deployment-playbook.md) is the canonical
> customer procedure. The checked-in funding policy currently has a pending
> release benchmark, so the normal customer workflow is intentionally blocked
> until Matter Labs completes and independently reviews the exact-release
> Sepolia rehearsal.

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

Use **2–4 hours elapsed time** as the initial execution-planning target after
the prerequisites are available. It is not an SLA; replace it with measured
rehearsal and customer-deployment data.

| Stage | Typical operator time | External wait | On-chain write? |
| --- | ---: | ---: | --- |
| Host, DNS, registry, and RPC | 20–40 min | DNS/provider dependent | No |
| Identity and funding review/distribution | 15–25 min | Sepolia ETH acquisition/confirmation | **Yes — funding transfers** |
| Prepare and review the chain | 20–45 min | Image/source build dependent | No |
| Broadcast the ecosystem | 10–30 min | Sepolia inclusion dependent | **Yes — highest-risk gate** |
| Start and validate the stack | 20–45 min | DNS/ACME and service startup | **Yes — Watchdog bridge deposit** |

The main schedule risks are Sepolia ETH availability, insufficient RPC
capabilities, private registry access, DNS/ACME propagation, and a partially
completed irreversible broadcast. Resolve the first four before broadcasting.

## Before you begin

Use an x86-64 Linux VPS with Docker Engine, Docker Compose v2, and recommended
capacity of 8 vCPU, 16 GB RAM, and 200 GB SSD.

Allow inbound SSH and TCP 80/443. Compose also publishes UDP 443 for optional
HTTP/3; allow it only when consistent with customer policy. Point these
required `A` records to the VPS:

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

Continue when required tools and Docker access have no blocking result.
Separately confirm the host is amd64, the private registry is accessible, the
DNS records point to this VPS, the browser RPC works with CORS, and the cold
build egress described in the Enterprise Adoption Guide is permitted.

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
outside the benchmarked core one-ETH policy.

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

Private keys, passwords, and private provider URLs remain in the encrypted
environment or protected runtime files. Chain preparation also writes
mode-`0600` plaintext wallet/configuration artifacts under
`/etc/prividium/runtime/chain`; they must remain operator-restricted and never
appear in public generated reports.

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

After the release funding benchmark is complete, send exactly **1 Sepolia
ETH** to the sandbox funding wallet shown under “Customer action.” Wait for
confirmation, then rerun:

```bash
tools/sandbox funding
```

Continue when the report status is `READY`. Once the exact-release benchmark
is complete, the approved policy is intended to cover the default core
sandbox, a 14-day/2,016-batch operator target, Watchdog’s 0.05 L2 ETH target,
transaction costs, reserve, and buffer. Actual runway varies with Sepolia gas
conditions. The policy does not cover SSO/bundler or the institutional demo.

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

As the designated operator, confirm that
`/etc/prividium/runtime/chain/out/manifest.json` and
`/etc/prividium/runtime/chain/out/preparation.json` are readable without
`sudo`. Stop if either is not. Do not broaden their file modes or apply an ad
hoc recursive ownership change; customer release requires a rehearsed
rootful-Docker ownership model.

Preparation builds only the chain-bootstrap artifact. Before broadcast, pull
and build the complete default stack without starting it:

```bash
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  pull --ignore-buildable

docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  build
```

Both commands must succeed. This exercises core image, source, and package
egress before chain creation.

## 7. Review readiness and broadcast

Generate the pre-broadcast record:

```bash
tools/sandbox readiness
```

It writes `/etc/prividium/runtime/reports/readiness.md` and returns one result:

- `READY` — all blocking checks pass;
- `READY WITH WARNINGS` — all blocking checks pass, but DNS is unresolved;
- `BLOCKED` — do not broadcast.

The customer procedure requires `READY` by default. Proceed with
`READY WITH WARNINGS` only through a documented joint exception; DNS must be
correct before final acceptance.

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
images, and starts the core stack. The Watchdog bridge prerequisite currently
has no execution deadline; the customer-release Gate 0 requires a reviewed
timeout and ambiguous-transaction procedure. After startup prerequisites
complete, the deployment summary waits up to ten minutes for:

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
`tools/sandbox logs` and all container states:

```bash
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  --profile "*" \
  ps --all --no-trunc
```

If the services and one-shot jobs are already in their expected state and only
endpoint readiness failed, fix the external condition, then run:

```bash
tools/sandbox summary
```

If a container is missing/stopped or a one-shot job failed, fix the cause and
rerun `tools/sandbox deploy`. If `bridge-funds` may have submitted a deposit
before it failed, inspect its logs and transaction state before rerunning
anything.

## 9. Complete the human acceptance checks

Automated startup is necessary but not the full product evaluation. Confirm:

- the administrator changes the temporary password, logs in, and registers
  WebAuthn with user verification;
- unauthenticated RPC is denied and authenticated transaction submission works;
- a user-funded Sepolia deposit completes and withdrawal initiation/settlement
  progression meets the Enterprise Adoption Guide acceptance definition;
- Explorer indexes the authenticated transaction;
- Watchdog’s RPC, SIWE/auth, 1-wei transfer, and settlement flows remain healthy
  across at least two batches;
- only SSH and Caddy are publicly reachable;
- Grafana is reachable only through
  `ssh -L 3100:127.0.0.1:3100 user@vps`.

## Optional capabilities

Optional SSO/bundler, webhook, and institutional-demo capabilities are outside
the current Enterprise Adoption Guide milestone. Enable them only under a
separately approved evaluation scope after the core environment has passed
acceptance. They add DNS, funding, contracts, state, dependencies, and
acceptance work that are not covered by this procedure.

For restarts, upgrades, backups, certificates, provider changes, SOPS recovery,
and incident handling, use the [operations runbook](RUNBOOK.md).
