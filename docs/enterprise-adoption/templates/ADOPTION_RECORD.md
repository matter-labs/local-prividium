# Prividium enterprise adoption record

**Classification: Customer confidential by default.** Store this record only
in the approved engagement evidence location. Do not commit a completed copy to
a public repository.

Use one copy of this document per customer environment. Store it according to
the customer's change and evidence policy. Do not include private keys,
passwords, bearer tokens, private RPC URLs, decrypted configuration, or
protected runtime reports.

## 1. Engagement and release

| Field | Value |
| --- | --- |
| Customer | `<customer>` |
| Environment name | `<environment>` |
| Evaluation objective | `<objective>` |
| Sandbox domain | `<domain>` |
| Target VPS hostname/IP | `<host>` |
| Linux distribution/version | `<rehearsal-tested value>` |
| Docker Engine version | `<rehearsal-tested value>` |
| Docker Compose version | `<rehearsal-tested value>` |
| Repository commit | `<commit>` |
| Release-lock reference | `<versions.lock.yaml commit or hash>` |
| Protocol release | `<version>` |
| ZKsync OS release | `<version>` |
| Prividium release | `<version>` |
| Explorer release | `<version>` |
| Watchdog release | `<version>` |
| Planned deployment date | `<UTC date/time>` |
| Actual deployment date | `<UTC date/time>` |
| Record owner | `<name/team>` |
| Technical approver | `<name/team>` |
| Security approver | `<name/team>` |
| Last updated | `<UTC date/time>` |

## 2. Scope decision

| Decision | Accepted | Approver/evidence |
| --- | :---: | --- |
| Persistent, single-amd64-VPS evaluation | ☐ | |
| Ethereum Sepolia settlement | ☐ | |
| Fake proofs and testnet verifier | ☐ | |
| Software-managed hot keys | ☐ | |
| No prover service | ☐ | |
| No HA, production SLO, or compliance claim | ☐ | |
| Synthetic identities, assets, and data only | ☐ | |
| Core stack only; optional profiles excluded | ☐ | |
| No assets of value | ☐ | |

Evaluation success statement:

> `<Describe the business and technical questions this evaluation must answer.>`

## 3. Named owners

| Area | Name/team | Contact/escalation path |
| --- | --- | --- |
| Customer evaluation owner | | |
| Customer platform/VPS owner | | |
| Customer network/DNS owner | | |
| Customer secret custodian | | |
| Secondary age-identity custodian | | |
| Customer identity administrator | | |
| Customer blockchain/RPC owner | | |
| Customer monitoring owner | | |
| Executing deployment operator | | |
| Independent deployment reviewer | | |
| Matter Labs deployment contact | | |
| Matter Labs product contact | | |

## 4. Release handoff gate

| Check | Result | Evidence |
| --- | --- | --- |
| Funding policy benchmark status is `complete` | ☐ PASS ☐ FAIL | |
| Clean Sepolia rehearsal used the exact locked release | ☐ PASS ☐ FAIL | |
| Funding observations and evidence are recorded | ☐ PASS ☐ FAIL | |
| Funding targets received independent review | ☐ PASS ☐ FAIL | |
| Approved transaction-capable rehearsal mechanism exists | ☐ PASS ☐ FAIL | |
| Provisional funding/runway claims cannot reach generated customer reports | ☐ PASS ☐ FAIL | |
| Generated reports disclose protected runtime key copies | ☐ PASS ☐ FAIL | |
| Runtime ownership permits designated operator review/readiness | ☐ PASS ☐ FAIL | |
| Watchdog bridge wait has a reviewed timeout/incident path | ☐ PASS ☐ FAIL | |
| Generated failure guidance matches the reviewed retry matrix | ☐ PASS ☐ FAIL | |
| Tested Linux/Docker/Compose support matrix is recorded | ☐ PASS ☐ FAIL | |
| Normal static validation passes | ☐ PASS ☐ FAIL | |
| Customer-facing timing/funding claims match rehearsal | ☐ PASS ☐ FAIL | |

**Gate decision:** ☐ CUSTOMER RELEASE READY ☐ BLOCKED

Approver and timestamp:

```text
<name, role, UTC timestamp>
```

## 5. Customer prerequisite checklist

### Host and access

- [ ] x86-64/amd64 Linux VPS provisioned.
- [ ] Rehearsal-tested Linux distribution/version recorded and matched.
- [ ] Recommended 8 vCPU, 16 GB RAM, and 200 GB SSD reviewed.
- [ ] Resource recommendation accepted as unbenchmarked for production scale.
- [ ] Rehearsal-tested/minimum Docker Engine version recorded and matched.
- [ ] Rehearsal-tested/minimum Docker Compose version/features recorded and matched.
- [ ] Bash and Git installed.
- [ ] Current operator can reach the Docker daemon.
- [ ] SSH follows the customer's approved access path.
- [ ] Host clock synchronization verified.
- [ ] Host disk and memory monitoring assigned.

### Network and DNS

- [ ] Required TCP 80/443 reaches Caddy.
- [ ] Optional UDP 443/HTTP3 policy recorded.
- [ ] SSH exposure is separately approved.
- [ ] `app.<domain>` returns the intended VPS address.
- [ ] `admin.<domain>` returns the intended VPS address.
- [ ] `api.<domain>` returns the intended VPS address.
- [ ] `explorer.<domain>` returns the intended VPS address.
- [ ] `explorer-api.<domain>` returns the intended VPS address.
- [ ] `idp.<domain>` returns the intended VPS address.
- [ ] No unintended `AAAA` record is present.
- [ ] Public exposure review method is agreed.

### Registries, builds, and external services

- [ ] Quay private-image entitlement works from the VPS.
- [ ] Required public registries work from the VPS.
- [ ] Cold-build source and package egress is approved.
- [ ] Chainlist access works.
- [ ] ACME egress and notifications are approved.
- [ ] Private Sepolia RPC returns chain ID `11155111`.
- [ ] Private RPC passes history, log, receipt, and blob capability checks.
- [ ] Public browser RPC is separate from the private provider URL.
- [ ] Browser RPC passes a target-browser Sepolia and CORS test.
- [ ] Sepolia ETH is available under an approved transaction process.

### Secrets and evaluation users

- [ ] SOPS, age, cast, jq, OpenSSL, and curl are installed.
- [ ] Customer-controlled age recipient selected.
- [ ] Matching age private identity stored separately.
- [ ] Approved target-host SOPS/age access method recorded.
- [ ] Named primary and secondary secret custodians assigned.
- [ ] Initial administrator email approved for synthetic evaluation use.
- [ ] Compatible WebAuthn browser/device nominated.
- [ ] No production or regulated data will be used.

**Prerequisite decision:** ☐ READY ☐ BLOCKED

## 6. Risk and exception register

| Condition | Impact | Control | Decision gate | Owner | Status/evidence |
| --- | --- | --- | --- | --- | --- |
| Single VPS/no HA | Environment outage affects all capabilities | Evaluation-only scope and customer host monitoring | Scope approval | | |
| Fake proofs/testnet verifier | No production proof security | No assets of value; explicit limitation | Scope approval | | |
| Funding benchmark | Unvalidated cost/runway claim | Complete exact-release rehearsal | Release handoff | | |
| Sepolia broadcast | Irreversible chain creation | Readiness report and chain-specific approval | Broadcast | | |
| Partial broadcast | Ambiguous on-chain state | Preserve runtime; stop and review before retry | Broadcast | | |
| Secret/age identity loss | Loss of administrative or operator capability | Separate protected custody and named owners | Predeployment | | |
| RPC mismatch/outage | Bootstrap or settlement failure | Capability probe and provider ownership | Readiness | | |
| Registry/build egress | Build or startup failure | Cold prepare/rehearsal on target host | Readiness | | |
| Root-owned protected runtime artifacts | Operator/readiness cannot review chain output | Rehearsed ownership/user mapping | Release handoff | | |
| Unbounded Watchdog bridge wait | Deployment elapsed time and retry state become ambiguous | Reviewed timeout and transaction-state procedure | Release handoff/deploy | | |
| DNS/ACME delay | Public and OIDC acceptance failure | Verify records point to VPS before broadcast | Readiness | | |
| Public-testnet data | Confidentiality or privacy exposure | Synthetic data only | Scope approval | | |
| Resource uncertainty | Capacity or disk exhaustion | Host monitoring and bounded evaluation | Scope approval | | |
| Monitoring gaps | Undetected host/service issue | Named operator and supplemental customer monitoring | Handover | | |

Additional exceptions:

| ID | Exception | Consequence | Owner | Due date | Approved by | Status |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |

## 7. Deployment timing

Record measured times rather than copying the planning estimate.

| Stage | Start UTC | End UTC | Operator time | External wait | Result/notes |
| --- | --- | --- | ---: | ---: | --- |
| Doctor/local prerequisites | | | | | |
| Identity generation and review | | | | | |
| Protected runtime creation | | | | | |
| Customer funding confirmation | | | | | |
| Funding distribution | | | | | |
| Chain preparation and review | | | | | |
| Readiness review | | | | | |
| Ecosystem/chain broadcast | | | | | |
| Core deployment and summary | | | | | |
| Human acceptance | | | | | |

Total hands-on operator time: `<duration>`

Total deployment elapsed time after prerequisites: `<duration>`

Prerequisite lead time: `<duration>`

## 8. Deployment gates and evidence

### Identity and runtime

| Field | Value/evidence |
| --- | --- |
| L2 chain ID | |
| Role-set fingerprint | |
| Public role inventory reference | |
| Encrypted environment custody reference | |
| Age private-identity custody confirmed by | |
| Initial administrator credential handoff evidence (no values) | |
| Grafana credential handoff evidence (no values) | |
| Runtime directory mode `0700` | ☐ |
| Runtime environment mode `0600` | ☐ |

### Funding

| Field | Value/evidence |
| --- | --- |
| Funding-policy version | |
| Funding plan ID | |
| Customer funding transaction hash | |
| Distribution evidence reference | |
| Plan final status | |
| Optional funding absent | ☐ |

### Preparation and readiness

| Field | Value/evidence |
| --- | --- |
| Prepared manifest hash/reference | |
| Preparation record reference | |
| Protected runtime owner/mode/operator-readability evidence | |
| Protocol source commit | |
| zk-deployer source commit | |
| Default remote-image pull result | |
| Default local-image build result | |
| Readiness report timestamp | |
| Readiness result | ☐ READY ☐ READY WITH WARNINGS ☐ BLOCKED |
| Approved warning/exception IDs | |

Pre-broadcast approval:

```text
<operator, reviewer, customer approver, Matter Labs approver, UTC timestamp>
```

### Broadcast

| Field | Value/evidence |
| --- | --- |
| L2 chain ID confirmation | |
| Broadcast start/end UTC | |
| Public manifest reference | |
| Ecosystem/chain address evidence | |
| Sepolia transaction evidence | |
| Broadcast result | ☐ COMPLETE ☐ PARTIAL/STOPPED ☐ FAILED BEFORE WRITE |

### Core deployment

| Field | Value/evidence |
| --- | --- |
| Deployment summary reference | |
| Summary generated UTC | |
| 15 long-running services accepted | ☐ |
| Three one-shot jobs completed | ☐ |
| Watchdog bridge deposit L1/L2 transaction evidence | |
| Watchdog bridge deposit completion state | |
| Public endpoints accepted | ☐ |
| Exact OIDC issuer accepted | ☐ |
| Unauthenticated RPC denied | ☐ |
| Incomplete-report reference, if applicable | |

## 9. Product acceptance results

### Acceptance test vector

| Field | Agreed value |
| --- | --- |
| OIDC evaluation email/subject and expected role | |
| Browser/OS and platform authenticator | |
| Browser wallet type and public address | |
| Authenticated RPC method | |
| Deposit amount | |
| L2 transaction type, amount/data, and recipient | |
| Withdrawal amount and two-batch observation target | |
| Expected administration views/actions | |
| Evidence location | |

All rows below are required for the complete core milestone. A required test
cannot be deferred. A scope removal must be approved before deployment, linked
to the exception register, and results in `ACCEPTED WITH EXCEPTIONS` rather
than a complete core success.

| Test | Required for core | Status | Tester/time | Evidence | Notes/exception ID |
| --- | :---: | --- | --- | --- | --- |
| Public exposure and loopback-only Grafana | Yes | ☐ PASS ☐ FAIL | | | |
| Administrator login and password change | Yes | ☐ PASS ☐ FAIL | | | |
| Prividium WebAuthn registration with user verification | Yes | ☐ PASS ☐ FAIL | | | |
| Unauthenticated RPC denied | Yes | ☐ PASS ☐ FAIL | | | |
| Authenticated RPC/chain access | Yes | ☐ PASS ☐ FAIL | | | |
| Sepolia deposit and resulting L2 balance | Yes | ☐ PASS ☐ FAIL | | | |
| Authenticated L2 transaction | Yes | ☐ PASS ☐ FAIL | | | |
| Explorer indexing | Yes | ☐ PASS ☐ FAIL | | | |
| Withdrawal initiation and two-batch settlement progression | Yes | ☐ PASS ☐ FAIL | | | |
| Watchdog RPC flow across two batches | Yes | ☐ PASS ☐ FAIL | | | |
| Watchdog auth flow across two batches | Yes | ☐ PASS ☐ FAIL | | | |
| Watchdog transfer flow across two batches | Yes | ☐ PASS ☐ FAIL | | | |
| Watchdog settlement flow across two batches | Yes | ☐ PASS ☐ FAIL | | | |
| Administration journey | Yes | ☐ PASS ☐ FAIL | | | |
| Public Keycloak administration denied | Yes | ☐ PASS ☐ FAIL | | | |

Key evidence:

| Evidence | Value |
| --- | --- |
| Authenticated L2 transaction hash | |
| L2 block/batch | |
| Deposit L1/L2 transaction hashes | |
| Withdrawal transaction hash/state/batches | |
| Explorer evidence reference | |
| Two-batch observation window | |
| External exposure evidence | |

## 10. Customer value review

| Topic | Customer conclusion | Follow-up |
| --- | --- | --- |
| Identity and access fit | | |
| Permission enforcement | | |
| Application integration model | | |
| Transaction and Ethereum journey | | |
| Explorer transaction visibility | | |
| Operational visibility | | |
| Production-gap assessment | | |

## 11. Handover

- [ ] Customer has the intended repository release.
- [ ] Public role inventory, manifest, and deployment summary are retained.
- [ ] Encrypted environment and age identity have approved separate custodians.
- [ ] VPS/Docker owner is named.
- [ ] DNS/TLS owner is named.
- [ ] Identity administrator is named.
- [ ] RPC and operator-funding owner is named.
- [ ] Monitoring owner is named.
- [ ] Routine command set has been demonstrated.
- [ ] Known monitoring limitations are accepted.
- [ ] Optional profiles remain disabled.
- [ ] Open exceptions have owners and dates.
- [ ] Evaluation closeout owner is named.

## 12. Final decision

Technical deployment:

- ☐ ACCEPTED
- ☐ ACCEPTED WITH EXCEPTIONS
- ☐ NOT ACCEPTED

Evaluation conclusion:

```text
<summary of what was demonstrated, what remains open, and recommended next decision>
```

Customer technical approver:

```text
<name, role, UTC timestamp>
```

Customer security approver:

```text
<name, role, UTC timestamp>
```

Matter Labs technical approver:

```text
<name, role, UTC timestamp>
```
