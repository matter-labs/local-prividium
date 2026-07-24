# Deployment readiness and security

| Document metadata | Value |
| --- | --- |
| Status | Draft — blocked for customer release pending the release funding benchmark |
| Purpose | Define everything that must be owned, supplied, reviewed, and approved before deployment |
| Audience | Customer platform, network, security, identity, and blockchain teams; Matter Labs deployment engineering |
| Deployment model | Persistent, single-VPS Prividium evaluation settled on Ethereum Sepolia |
| Applicable release | [versions.lock.yaml](../../deployment/versions.lock.yaml) |
| Document version | 0.1-draft |
| Repository commit | Recorded per customer in the adoption record; must match the approved handoff |
| Maintainer | Matter Labs Prividium Engineering |
| Last successful customer-release rehearsal | Not yet recorded |
| Required approvers | Technical and security approvers: TBD before customer release |
| Next review | After the release rehearsal or any locked-release change |
| Last revised | 2026-07-23 |

## Readiness outcome

Do not begin the deployment session until both teams can answer yes to all of
the following:

- Every Matter Labs Gate 0 release-handoff check passes, including the funding
  rehearsal, runtime ownership, platform matrix, bridge timeout, generated
  reports, and retry guidance.
- The customer accepts the evaluation-only architecture and data boundary.
- A correctly sized amd64 VPS is available and under customer administration.
- DNS, ingress, egress, image access, RPCs, tools, and Sepolia ETH are ready.
- Named people own the encrypted configuration and age private identity.
- A single designated operator will execute funding, broadcast, and deployment.
- The customer has approved the on-chain changes and evaluation funding.
- The customer has a compatible browser/device for the required WebAuthn test.

## Gate 0: Matter Labs release readiness

This gate is completed by Matter Labs before customer handoff.

| Check | Required result |
| --- | --- |
| `deployment/funding-policy.json` | `benchmark.status` is `complete` |
| Release rehearsal | A clean deployment of the exact locked release completed on Sepolia |
| Funding evidence | Observed spend, operator cost, distribution/bridge fees, and evidence reference recorded |
| Independent review | Funding targets and the one-ETH boundary approved |
| Rehearsal mechanism | An approved engineering-only path can fund and broadcast while the policy is pending |
| Generated claims and custody wording | Initialization/report generation is gated or policy-aware; provisional funding/runway language cannot reach customers; protected plaintext runtime key copies are disclosed |
| Runtime ownership | Chain-bootstrap artifacts are readable by the designated operator/readiness tool without broadening secret access |
| Bridge timeout | The Watchdog L1-to-L2 funding wait has a reviewed bound and explicit ambiguous-transaction procedure |
| Failure diagnostics | Generated guidance distinguishes endpoint-only `summary` recovery from container/job `deploy` recovery and an ambiguous bridge transaction |
| Static validation | `tools/sandbox validate` passes without engineering-only bypass flags |
| Documentation | Timing, funding, and known-risk language reflects measured results |

The checked-in policy is currently `pending`, and the repository does not yet
provide a transaction-capable rehearsal mode that can complete the benchmark
while that policy is pending. Both are customer-release blockers, not customer
action items. The `--allow-unbenchmarked` flag applies only to static
validation and must not be treated as broadcast authorization.

The current rootful chain-bootstrap ownership behavior and unbounded Watchdog
bridge wait are additional release blockers. Resolve and exercise both in the
same release rehearsal.

## Responsibility model

Assign named individuals in the [adoption
record](templates/ADOPTION_RECORD.md). One person may hold multiple roles, but
every responsibility must have an owner.

| Responsibility | Customer | Matter Labs |
| --- | :---: | :---: |
| Confirm evaluation objectives and scope | Accountable | Consulted |
| Approve architecture and security exceptions | Accountable | Provides technical evidence |
| Provision and administer the VPS | Accountable | Advises |
| Configure firewall, DNS, SSH, and time synchronization | Accountable | Provides requirements |
| Provide private and browser Sepolia RPCs | Accountable | Validates required capabilities |
| Provide private-image entitlement | Joint | Accountable for entitlement |
| Select SOPS/age custodians | Accountable | Advises |
| Complete release funding benchmark | Informed | Accountable |
| Acquire evaluation Sepolia ETH | Accountable | Provides measured target |
| Review role inventory and funding plan | Approves | Supports |
| Approve Sepolia chain creation | Joint | Joint |
| Execute the operator commands | Designated customer or agreed operator | Supports |
| Perform product acceptance | Joint | Joint |
| Operate host, DNS, identity, and monitoring during evaluation | Accountable | Supports under the agreed engagement |

This guide does not establish a support SLA, staffed alert response, or
production responsibility model.

## Host requirements

| Requirement | Target |
| --- | --- |
| Architecture | x86-64/amd64 |
| Tested operating-system distribution/version | **TBD before customer release** |
| CPU | 8 vCPU recommended |
| Memory | 16 GB RAM recommended |
| Storage | 200 GB SSD recommended |
| Addressing | One stable public IPv4 address |
| Tested/minimum Docker Engine version | **TBD before customer release** |
| Tested/minimum Docker Compose version | **TBD before customer release**; must support `include`, remote Git build contexts, and `dockerfile_inline` |
| Administration | SSH through the customer's approved access path |
| Clock | Working NTP/time synchronization |

The resource recommendation is not a capacity benchmark or performance
commitment. The repository does not enforce CPU, memory, disk, container
resource limits, or log rotation. The customer should monitor host disk and
memory independently.

Before customer release, Matter Labs must record the tested Linux distribution,
Docker Engine version, and Docker Compose version from the release rehearsal,
and set the supported minimums. Until then, the target-platform specification
is incomplete. `tools/sandbox doctor` currently confirms Compose v2 but not
each required feature version.

## Inbound network and DNS

Allow only the customer's approved SSH path plus:

| Port | Protocol | Purpose |
| ---: | --- | --- |
| 80 | TCP | ACME validation and HTTP-to-HTTPS handling |
| 443 | TCP | HTTPS applications and APIs |
| 443 | UDP | Optional HTTP/3; Compose publishes it, but it is not required for core HTTPS/ACME acceptance |

Create these `A` records, all pointing to the selected VPS:

- `app.<domain>`
- `admin.<domain>`
- `api.<domain>`
- `explorer.<domain>`
- `explorer-api.<domain>`
- `idp.<domain>`

Do not publish an `AAAA` record unless IPv6 is intentionally routed and
firewalled to the same host.

Before deployment, verify the returned address for every name, not only that
the name resolves. The automated readiness check confirms resolution but does
not prove that the answer is the intended VPS.

Only Caddy should be wildcard-bound on the host. Grafana binds to loopback on
port 3100. Raw ZKsync OS RPC, PostgreSQL, Keycloak administration, Prometheus,
and service ports must remain private.

## Outbound network access

The deployment is not an offline or air-gapped artifact. A cold build and
deployment can require:

- the customer's private Sepolia RPC;
- public browser-RPC access from evaluator browsers;
- Quay private images;
- pinned public images from GHCR and Docker Hub;
- GitHub repositories and submodules used by locked local builds;
- operating-system, Rust, Cargo, npm, pnpm, Yarn, Foundry/Soldeer, and related
  transitive package sources used by Docker builds;
- `chainid.network` for the L2 chain-ID collision check;
- the ACME certificate authority selected by Caddy.

Enterprise egress teams should either allow the required transitive sources
during the deployment window or require Matter Labs to deliver a separately
approved prebuilt artifact set. Registry access alone is not enough to prove
that the cold build will succeed.

`tools/sandbox prepare` exercises the locked chain-bootstrap build without
creating the Sepolia chain, but it does not build the core Watchdog,
permissioning, bridge, or monitoring images. Before broadcast, pull the default
remote images and build every default buildable service using the commands in
the core deployment playbook. This prevents first discovering a core
build/egress failure after chain creation.

## RPC requirements

### Private server-side RPC

Provide a private HTTPS Ethereum Sepolia endpoint. It must:

- return chain ID `11155111`;
- support current and historical calls;
- support historical logs;
- return transaction receipts;
- expose EIP-4844 blob fee data;
- support the reads and transaction submission required by the chain
  deployment and settlement operators.

The readiness workflow probes the core read capabilities. It cannot guarantee
future provider availability or rate-limit behavior.

### Public browser RPC

Provide a separate public HTTPS endpoint that:

- serves Ethereum Sepolia;
- permits browser CORS requests from the customer application;
- is safe to embed in browser configuration;
- supports the wallet and bridge flows used in acceptance.

The current automation renders this URL but does not verify its chain ID, CORS
headers, or browser behavior. Test it from an evaluator's target browser before
the deployment session.

Never place a private provider credential in `SEPOLIA_BROWSER_RPC_URL`.

## Operator workstation and access

The documented path runs the operator commands on the target host. Install:

- `bash`;
- `git`;
- `docker`;
- Docker Compose v2;
- `sops`;
- `age`;
- Foundry `cast`;
- `jq`;
- `openssl`;
- `curl`;
- the standard `sudo` and `install` utilities used to create the runtime
  directory.

Authenticate to the Matter Labs private registry from that host:

```bash
docker login quay.io
```

Run:

```bash
tools/sandbox doctor
```

`doctor` checks local tooling, Docker access, the funding-policy gate, and
available local configuration. It does not replace the DNS, browser-RPC,
resource, cold-build, or full readiness checks in this document.

## Required customer inputs

Prepare these inputs before `tools/sandbox init`:

| Input | Owner | Security treatment |
| --- | --- | --- |
| Sandbox base domain | Customer platform/network | Non-secret |
| ACME notification email | Customer platform | Non-secret |
| Initial administrator email | Customer identity owner | Personal data; use an evaluation identity |
| Private Sepolia RPC URL | Customer blockchain/platform | Secret if it contains a provider credential |
| Public browser Sepolia RPC URL | Customer application/platform | Public browser configuration |
| age recipient | Customer secret custodian | Public encryption recipient; retain the matching private identity separately |
| Sepolia ETH | Customer change/funding owner | Testnet asset; approval and transaction evidence still required |

The workflow generates the L2 chain ID, signing keys, service wallets,
passwords, and session secrets. Do not preselect or reuse keys from another
environment.

## Security model

### Evaluation constraints

The customer must explicitly accept:

- one host and one Docker daemon form a shared trust and failure domain;
- all chain and service keys are software-managed hot keys for this evaluation;
- fake proofs and a testnet verifier are used;
- no prover service runs;
- Ethereum Sepolia and rollup data are public-testnet data;
- the environment has no production SLO, compliance attestation, or security
  certification;
- automatic TLS and digest pinning do not constitute complete host or
  application hardening.

Use no assets of value and no confidential, regulated, or production customer
data.

### Secret custody

`tools/sandbox init` creates:

- `deployment/secrets/sandbox.enc.env`, encrypted to the provided age
  recipient;
- `deployment/public/roles.md`, containing public addresses and purposes only.

The encrypted environment is intentionally not committed. Store a protected
copy in the customer's approved secret system. Store the matching age private
identity separately and restrict it to named custodians.

The decrypted runtime environment is written to:

```text
/etc/prividium/runtime/sandbox.env
```

It must have mode `0600`; its parent directory must have mode `0700`. Docker
administrators and root can access the secrets supplied to containers, so
privileged host access is equivalent to deployment-secret access.

### Generated records

| Record | Classification | Handling |
| --- | --- | --- |
| `deployment/public/roles.md` | Non-secret public addresses and purposes | Review and commit |
| `deployment/public/manifest.json` | Non-secret chain identity and transaction evidence | Review and commit |
| `deployment/public/deployment-summary.md` | Non-secret URLs, versions, health, and limitations | Review and commit |
| `/etc/prividium/runtime/reports/*` | Protected operational details | Restrict to operators |
| `/etc/prividium/runtime/chain/*` | Secret keys, provider data, intent, state, and server configuration | Restrict to operators; never commit |

### Identity controls

The core realm creates one initial administrator with a temporary password.
The administrator must change it at first login and register WebAuthn with user
verification. Nominate a compatible browser and platform authenticator before
acceptance.

The Keycloak admin interface has no host port and is blocked by Caddy. The
initial realm import is first-database-start behavior; later JSON edits do not
update an existing realm.

### Supply-chain controls

The repository:

- pins remote container images by digest;
- pins product and source versions;
- rejects floating remote images and known development secrets during static
  validation;
- builds several maintained images from locked sources and pinned base images.

The customer should still apply its normal image scanning, source review,
registry policy, and vulnerability acceptance process. The version lock is not
a formal SBOM.

## Funding readiness

After the release benchmark is complete, the intended core workflow asks the
customer to transfer the release-approved amount—currently designed as exactly
1 Sepolia ETH—to one generated sandbox funding wallet.

The protected funding plan allocates current shortfalls to deployment,
governance, settlement, and the core Watchdog flow while retaining a policy
buffer. The claimed 14-day operator runway is conditional on the completed
release benchmark and actual Sepolia gas conditions; it is not an uptime SLA.

Only the generated sandbox funding wallet is customer-funded. The workflow
distributes to role addresses after a plan-ID confirmation. Do not manually
fund individual generated roles unless the documented post-deployment
operations process calls for it.

## Execution controls

Apply these controls during the deployment:

- Name one executing operator and one reviewer.
- Run `funding apply`, `broadcast`, and `deploy` from one operator session.
- Do not invoke on-chain stages concurrently; the workflow has no distributed
  execution lock.
- Capture command start/end times and resulting report paths.
- Require independent review before funding distribution and broadcast.
- Treat `READY` as the normal broadcast requirement.
- Accept `READY WITH WARNINGS` only through a documented joint exception with
  an owner and deadline. DNS must be correct before final acceptance.
- Preserve `/etc/prividium/runtime/chain` if broadcast returns after submitting
  any transaction.

## Pre-session checklist

- [ ] Funding benchmark is complete and independently reviewed.
- [ ] Evaluation-only scope and public-testnet data policy are approved.
- [ ] VPS matches the rehearsal-tested Linux, Docker Engine, Docker Compose,
      architecture, capacity, disk, and clock requirements.
- [ ] Bash and Git are installed.
- [ ] SSH and firewall rules are approved.
- [ ] All six DNS records return the intended VPS address.
- [ ] Quay entitlement and public registry access work from the VPS.
- [ ] Cold-build egress is approved.
- [ ] Default remote-image pull and core local-image build complete before
      broadcast.
- [ ] Private Sepolia RPC is provisioned.
- [ ] Browser RPC passes a real browser/CORS test.
- [ ] Sepolia ETH is available under an approved transaction process.
- [ ] SOPS and age tools are installed.
- [ ] The target-host operator session can access the age identity through an
      approved protected file or SOPS integration.
- [ ] The age private identity has named custodians and a separate protected
      location.
- [ ] Initial administrator and WebAuthn test device are nominated.
- [ ] Executing operator and reviewer are named.
- [ ] An operator session based on the unmeasured 2–4 hour planning target is
      reserved, with external and human-acceptance waits tracked separately.
- [ ] The [adoption record](templates/ADOPTION_RECORD.md) is opened and ready
      for evidence.

When every item is complete, continue to the [Core deployment
playbook](03-core-deployment-playbook.md).
