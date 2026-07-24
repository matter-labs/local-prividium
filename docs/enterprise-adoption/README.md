# Enterprise Adoption Guide — Customer-hosted Prividium Sepolia evaluation

This guide helps an enterprise engineering team plan, deploy, and evaluate a
customer-hosted Prividium environment on Ethereum Sepolia.

It is written to leave the reader with three clear conclusions:

1. I understand what this system is and what value it demonstrates.
2. I know exactly what my team must provide and deploy.
3. I know how long the work should take, where decisions are required, and
   where the material risks are.

| Guide metadata | Value |
| --- | --- |
| Deployment model | Persistent, customer-hosted evaluation on one VPS |
| Settlement network | Ethereum Sepolia |
| Intended audience | Platform, cloud, security, identity, blockchain, and evaluation teams |
| Applies to | The release pinned in [versions.lock.yaml](../../deployment/versions.lock.yaml) |
| Guide status | Draft — blocked for customer release pending the release funding benchmark |
| Document version | 0.1-draft |
| Repository commit | Recorded per customer in the adoption record; must match the approved handoff |
| Maintainer | Matter Labs Prividium Engineering |
| Last successful customer-release rehearsal | Not yet recorded |
| Required approval | Technical and security approvers recorded in the adoption record |
| Next review | After the release rehearsal or any locked-release change |
| Last revised | 2026-07-23 |

> [!CAUTION]
> This deployment is an enterprise evaluation environment, not a production
> architecture. It uses one VPS, fake proofs, a testnet verifier, and
> operator-funded Sepolia transactions. Do not use it to secure assets of value
> or process confidential production data.

## Decision summary

| Question | Current answer |
| --- | --- |
| What is deployed? | A dedicated ZKsync chain, Prividium permissioning and applications, identity, Explorer, TLS edge, and monitoring |
| Where does it run? | One customer-controlled amd64 Linux VPS |
| What is public? | Six HTTPS hostnames through Caddy; SSH remains customer-controlled |
| What remains private? | PostgreSQL, raw ZKsync OS RPC, Keycloak administration, Prometheus, and service internals |
| What infrastructure is recommended? | 8 vCPU, 16 GB RAM, 200 GB SSD, one public IPv4 address |
| How long does technical deployment take? | Plan for 2–4 hours elapsed after all prerequisites are ready |
| What usually drives calendar time? | Security approvals, DNS, private-image access, RPC procurement, and Sepolia ETH |
| Which steps write to Sepolia? | Customer funding, role distribution, ecosystem/chain broadcast, and the Watchdog bridge deposit; broadcast is the highest-risk gate |
| What does the core funding workflow expect? | One customer transfer of 1 Sepolia ETH to a generated funding wallet, after the release funding policy is benchmarked |
| Is it production-ready? | No |
| Is this checkout customer-release-ready today? | No; Gate 0 lists the funding/rehearsal, generated-report, runtime-ownership, platform-matrix, bridge-timeout, and diagnostic blockers |

The 2–4 hour figure is a planning target from the current deployment workflow.
Record actual stage timings during release rehearsal and the customer
deployment. Enterprise access and change approvals may add customer-specific
lead time that is not included in this estimate.

The current Watchdog bridge job can wait indefinitely for L2 execution before
the deployment-summary ten-minute timer begins. Until that job has a reviewed
timeout and incident path, 2–4 hours is not an upper bound.

## Release handoff gate

The checked-in funding policy is a release gate. Before this repository is
handed to a customer, Matter Labs must complete the release-specific Sepolia
funding rehearsal and set:

```json
"benchmark": {
  "status": "complete"
}
```

in `deployment/funding-policy.json`, with independently reviewed evidence.
Until then, `tools/sandbox doctor`, funding, readiness, and deployment are
designed to stop. Do not ask a customer to fund or broadcast a deployment while
the benchmark remains `pending`.

The current tooling also lacks an approved transaction-capable rehearsal mode
that can satisfy this gate while the benchmark is pending. Matter Labs must
implement and review that engineering-only path before executing the benchmark
procedure. The static `--allow-unbenchmarked` validation option does not
authorize funding or broadcast.

`tools/sandbox init` is not currently gated and its generated role report can
contain the provisional one-ETH and operator-runway language. Do not run or
distribute that customer report before Gate 0. Before release, make report
generation policy-aware or gate initialization on the completed benchmark. The
report must also disclose that keys are decrypted into protected runtime files,
not claim that SOPS is the only key location.

On a normal rootful Docker host, the chain-bootstrap container can create
mode-`0600` runtime files owned by root. The documented unprivileged operator
and readiness tool then cannot review or read them. Matter Labs must implement
and rehearse a supported runtime ownership/user-mapping model before customer
release.

## What the evaluation demonstrates

The core deployment gives the customer a persistent environment in which to
evaluate:

- identity-based access to a permissioned ZKsync environment;
- authenticated application, administration, API/RPC, and Explorer journeys;
- customer-controlled hosting, DNS, secrets, and operational access;
- Sepolia-to-L2 funding and authenticated L2 transactions;
- health, settlement, transfer, and operator-funding visibility;
- pinned release inputs and a reviewable public deployment record.

The default deployment starts 15 long-running services and completes three
one-shot prerequisite jobs. Optional SSO/bundler, webhook, and institutional
demo capabilities exist in the repository but are not part of this milestone
guide or the core funding commitment.

## Read this guide in order

| Step | Document | Outcome |
| ---: | --- | --- |
| 1 | [System and value overview](01-system-and-value-overview.md) | Understand the product, topology, interfaces, and boundaries |
| 2 | [Deployment readiness and security](02-deployment-readiness-and-security.md) | Assign owners and complete infrastructure, access, security, DNS, RPC, and funding prerequisites |
| 3 | [Core deployment playbook](03-core-deployment-playbook.md) | Execute the deployment with explicit evidence and stop/go gates |
| 4 | [Evaluation and acceptance](04-evaluation-and-acceptance.md) | Prove platform health and the customer-facing value journeys |
| 5 | [Operating the evaluation](05-operating-the-evaluation.md) | Run routine checks and safely manage the environment during the evaluation |
| 6 | [Adoption record template](templates/ADOPTION_RECORD.md) | Capture readiness, timings, evidence, exceptions, and sign-off |

The repository's [guided setup](../SETUP.md), [component
reference](../COMPONENTS.md), and [operations runbook](../RUNBOOK.md) remain
technical source material. For this customer milestone, the numbered Enterprise
Adoption Guide documents are canonical. The setup and broader runbook are
engineering companions, not alternate customer procedures.

## Expected timeline

The customer and Matter Labs can perform many prerequisite activities in
parallel.

| Phase | Owner | Initial planning allowance | Main variability |
| --- | --- | ---: | --- |
| Access and architecture review | Joint | 30–60 min | Security and network review |
| Host, firewall, DNS, registry, and RPC readiness | Customer | 20–40 min after provisioning | Internal approvals and DNS propagation |
| Identity generation and funding review | Joint | 15–25 min | Sepolia ETH acquisition and confirmation |
| Chain preparation, core prebuild, and review | Joint | 20–60 min | Source/image build time |
| Sepolia broadcast | Joint approval; designated operator executes | 10–30 min | Sepolia inclusion and RPC behavior |
| Stack startup and automated validation | Customer operator | 20–45 min | Image pulls, ACME, and service startup |
| Human acceptance | Joint | Initial target: 60–120 min of tester time | Two batches plus deposit and settlement waits can extend elapsed time; full withdrawal finalization is separate scope |

Recommended scheduling:

- Reserve one operator session for deployment and the main acceptance work
  after prerequisites are complete. Same-day acceptance is not guaranteed
  until rehearsal data includes deposit and settlement timing.
- Start access, DNS, RPC, registry, and funding work before the deployment
  session; the required lead time is customer-specific.
- Do not schedule the irreversible broadcast until the readiness report is
  acceptable to both teams.

## Critical decisions and risks

| Risk or decision | Why it matters | Required treatment |
| --- | --- | --- |
| Evaluation versus production | The topology has a single failure domain and non-production proof security | Obtain explicit scope acceptance before deployment |
| Funding benchmark | The current one-ETH policy must be measured against the exact locked release | Complete and independently review the release rehearsal before customer handoff |
| Sepolia transactions | Funding, role distribution, chain creation, and bridging cannot be undone locally | Apply separate review gates; treat chain broadcast as the highest-risk approval |
| Key custody | Signers control deployment, governance, and settlement roles | Store only in SOPS/runtime controls and restrict operator access |
| RPC capability | An ordinary public RPC may lack required history, receipts, logs, or blob data | Pass the automated RPC capability probe before broadcast |
| DNS and ACME | Browser workflows and strict OIDC issuer validation depend on correct hostnames | Pre-create all six records and open required ports |
| Private registry and build egress | Missing image or source access blocks readiness or startup | Validate access from the target VPS before the change window |
| Public testnet data | Sepolia and rollup data are not a confidential enterprise data store | Use synthetic evaluation identities and data only |
| Persistent local state | Volume deletion can remove chain, identity, application, and monitoring state | Limit Docker privileges and prohibit unreviewed destructive Compose commands |
| Schedule variability | External approvals and resources dominate elapsed time | Track prerequisites separately from hands-on deployment time |

## Definition of done

The adoption milestone is complete when:

- the release funding benchmark is complete;
- both teams approve the scope, security posture, and risk record;
- the readiness report has no blocking issues;
- the chain broadcast and public manifest complete successfully;
- the core stack produces a healthy public deployment summary;
- all required human acceptance journeys pass, and Watchdog remains healthy
  across at least two complete batches;
- the customer receives the encrypted configuration, public records, operating
  instructions, and completed adoption record;
- named customer owners accept responsibility for the VPS, DNS, secrets,
  funding, identity administration, and evaluation lifecycle.

## Out of scope for this milestone

This guide intentionally does not define:

- a production or highly available Prividium architecture;
- disaster recovery or full-volume restoration;
- profile-specific deployment procedures;
- performance or load-testing commitments;
- production SLOs, compliance certification, or regulated-data approval;
- migration from this sandbox into a production network.

Those topics require separate architecture and support decisions rather than an
extension of this single-VPS evaluation procedure.
