# Evaluation and acceptance

| Document metadata | Value |
| --- | --- |
| Status | Draft — blocked for customer release pending the release funding benchmark |
| Purpose | Prove that the deployed environment is healthy and demonstrates the agreed Prividium value journeys |
| Audience | Customer evaluators, platform engineers, identity engineers, security reviewers, and Matter Labs deployment engineering |
| Estimated effort | Initial unmeasured planning allowance: 60–120 minutes of operator/tester time; deposit/L1 settlement and any separately scoped full withdrawal finalization have no validated elapsed-time upper bound yet |
| Applicable release | [versions.lock.yaml](../../deployment/versions.lock.yaml) |
| Document version | 0.1-draft |
| Repository commit | Recorded per customer in the adoption record; must match the approved handoff |
| Maintainer | Matter Labs Prividium Engineering |
| Last successful customer-release rehearsal | Not yet recorded |
| Required approvers | Technical and security approvers: TBD before customer release |
| Next review | After the release rehearsal or any locked-release change |
| Last revised | 2026-07-23 |

Automated startup is necessary, but it is not product acceptance. A deployment
is complete only after the human identity, permission, transaction, Explorer,
and monitoring journeys pass.

Use a copy of the [adoption record](templates/ADOPTION_RECORD.md). Mark every
required test `PASS` or `FAIL` and include a timestamp, tester, and evidence
reference.

## Acceptance model

| Gate | Purpose | Required evidence |
| --- | --- | --- |
| 0. Release readiness | Confirm the repository was eligible for customer handoff | Completed funding benchmark and approved release lock |
| 1. Pre-broadcast approval | Confirm infrastructure, security, identities, funding, and preparation were reviewed | Protected readiness report plus signed pre-broadcast approval and exception record in the adoption record |
| 2. Automated deployment | Confirm the chain identity, core services, HTTPS, protected RPC, and OIDC are reachable | Public manifest and healthy deployment summary |
| 3. Product-value acceptance | Confirm the customer can complete the intended identity, transaction, Explorer, and monitoring journeys | Test evidence and transaction/batch references |
| 4. Handover | Assign ongoing evaluation ownership and record accepted limitations | Completed adoption record and named owners |

Do not describe the environment as accepted while a required Gate 3 test is
unfinished.

## Before testing

Confirm:

- `tools/sandbox deploy` exited successfully;
- `deployment/public/deployment-summary.md` exists and reports `HEALTHY`;
- all six core DNS names point to the intended VPS;
- the designated secret custodian retrieved only the generated
  `SANDBOX_ADMIN_EMAIL` and `SANDBOX_ADMIN_PASSWORD` through the
  customer-approved SOPS/secret-store mechanism and delivered them to the
  evaluator through an approved confidential channel;
- the designated secret custodian delivered `GRAFANA_ADMIN_USER` and
  `GRAFANA_ADMIN_PASSWORD` to the monitoring operator through an approved
  confidential channel;
- the evaluator has a compatible browser and platform WebAuthn authenticator
  with user verification;
- the browser Sepolia RPC works from that browser;
- the evaluator has a small amount of testnet ETH suitable for the approved
  deposit and withdrawal-progression tests;
- the operator can inspect Grafana through an SSH tunnel;
- synthetic identities and transaction data will be used.

Record the custodian, recipient, channel classification, and receipt time in
the confidential adoption record. Never record the credential values, print
the complete decrypted environment, or paste secrets into tickets or terminal
logs.

## Gate 2: Review the automated evidence

Run:

```bash
tools/sandbox summary
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  --profile "*" \
  ps --all --no-trunc
```

Use the public summary to confirm:

- the correct Ethereum Sepolia and L2 chain IDs;
- the locked Protocol, ZKsync OS, Prividium, Explorer, and Watchdog releases;
- fake-proof, testnet-verifier, single-VPS, and non-production limitations;
- the expected six public interfaces;
- HTTPS responses for the user application, administration, API, Explorer, and
  Explorer API;
- successful Prividium API health;
- `401` or `403` for an unauthenticated RPC request;
- the exact OIDC issuer.

Use the `docker compose ... ps --all --no-trunc` output as separate evidence
that:

- all 15 named long-running core services are running or healthy;
- `chain-preflight`, `bridge-funds`, and
  `watchdog-permissions-setup` exited successfully.

The generated public summary reports the aggregate Compose result; it does not
list every service name or exit code.

### What automated health does not prove

The generated `HEALTHY` status is a deployment liveness and reachability
result. It does not prove:

- authenticated application behavior;
- an end-to-end L2 transaction;
- correct Explorer indexing semantics;
- successful deposit or withdrawal;
- Watchdog flow success;
- host CPU, memory, disk, or log capacity;
- staffed monitoring or alert delivery.

Some services without Compose health checks are accepted when running, and the
Explorer API check accepts a non-server-error response rather than validating
business data. Complete every applicable human test below.

## Acceptance test vector

Agree the exact synthetic test vector before Gate 3. Use the generated sandbox
administrator for core acceptance unless a separate user and permissions have
been explicitly provisioned and recorded.

| Field | Agreed value |
| --- | --- |
| OIDC evaluation email/subject and expected role | `<record in confidential adoption record>` |
| Browser, operating system, and platform authenticator | `<value>` |
| Supported browser wallet type and public address | `<value>` |
| Public browser RPC test method | `<value>` |
| Deposit amount | `<small approved Sepolia ETH amount>` |
| L2 transaction type, amount/data, and recipient | `<value>` |
| Withdrawal amount and observation target | `<small approved L2 ETH amount; L2 inclusion plus state after two batches>` |
| Expected administration views/actions | `<value>` |
| Evidence location | `<customer-approved confidential location>` |

Do not begin Gate 3 with undefined users, wallets, amounts, recipients, or
administration expectations.

## Gate 3: Product-value tests

### Test 1 — Public exposure

**Value:** The customer controls the public entry points and internal services
remain private.

Validate from outside the VPS:

- the six documented HTTPS names are reachable;
- the approved SSH path is reachable;
- no raw application, PostgreSQL, Keycloak administration, Prometheus,
  Grafana, Watchdog, or ZKsync OS port is publicly reachable.

Validate on the VPS that Grafana listens only on `127.0.0.1:3100`.

**Pass condition:** Only customer-approved SSH and Caddy's public web ports are
externally reachable; Grafana is loopback-only.

**Capture:** External scan output or security-tool evidence, host listener
output, date, source address, and reviewer.

### Test 2 — Administrator identity and WebAuthn

**Value:** Access is associated with an authenticated identity and a
user-verified device credential.

1. Open `https://app.<domain>`.
2. Select the Keycloak sign-in journey.
3. Sign in as the initial sandbox administrator through Keycloak OIDC.
4. Change the temporary Keycloak password when prompted.
5. After returning to the Prividium application, register the Prividium
   platform WebAuthn credential using the nominated authenticator.

**Pass condition:** OIDC authentication succeeds, the temporary password is no
longer valid, and the Prividium WebAuthn registration completes with user
verification.

This sandbox does not configure Keycloak WebAuthn as an OIDC MFA factor. The
OIDC login/password change and the Prividium platform-credential registration
are separate parts of the acceptance journey.

**Capture:** Tester identity, timestamp, browser/device type, and screenshots
that contain no credential or token.

### Test 3 — Permission enforcement

**Value:** The public RPC endpoint is not an unauthenticated raw node endpoint.

From an unauthenticated client:

```bash
curl --silent --output /dev/null --write-out '%{http_code}\n' \
  --header 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  https://api.<domain>/rpc
```

**Pass condition:** The request returns `401` or `403`.

Then use the authenticated application/client and RPC method recorded in the
acceptance test vector to query the chain.

**Pass condition:** An authorized user can access the permitted RPC operation.

**Capture:** HTTP status, authenticated user/role, permitted operation, and
timestamp. Do not capture bearer tokens.

### Test 4 — Sepolia deposit

**Value:** The environment participates in the expected Ethereum-to-L2 asset
journey and gives the fresh evaluation account L2 ETH for transaction fees.

1. From the authenticated user journey, deposit a small approved amount of
   Sepolia ETH.
2. Confirm the resulting L2 balance.

**Pass condition:** The L1 deposit transaction is confirmed, the corresponding
L2 transaction succeeds, and the intended evaluation account's L2 balance
reflects the deposited amount.

**Capture:** L1 and L2 transaction hashes, amount, timestamps, resulting
balance, completion state, and observed external wait.

Use testnet funds only. This acceptance test is not a custody, liquidity, or
production bridge assessment.

### Test 5 — Authorized L2 transaction

**Value:** An authorized enterprise user can submit an L2 transaction through
the protected environment.

1. Use the funded account and authenticated identity from the acceptance test
   vector.
2. Submit the recorded low-value transaction type, amount/data, and recipient.
3. Wait for an L2 receipt.

**Pass condition:** The transaction is accepted, executed on the intended L2
chain, and attributable to the approved test identity/account.

**Capture:** L2 transaction hash, chain ID, sender/recipient public addresses,
block/batch number, status, elapsed time, and tester.

### Test 6 — Explorer visibility

**Value:** Authorized users can inspect chain activity and correlate
transactions by public address and transaction hash.

1. Sign in to `https://explorer.<domain>`.
2. Search for the authenticated L2 transaction from Test 5.
3. Confirm its status, block/batch, public addresses, and chain identity.

**Pass condition:** Explorer indexes the transaction and displays information
consistent with its receipt.

**Capture:** Transaction hash, Explorer URL, indexed block/batch, screenshot,
and indexing delay.

Explorer transaction visibility is not an identity-aware enterprise audit
trail or a compliance record.

### Test 7 — Withdrawal initiation and settlement progression

**Value:** The environment demonstrates the L2-to-Ethereum half of the asset
journey using ETH as the base and fee asset.

1. From the authenticated user journey, initiate the withdrawal amount in the
   acceptance test vector.
2. Confirm the L2 withdrawal transaction is included.
3. Observe the application/Explorer withdrawal or settlement state across at
   least two complete batch cycles.

**Pass condition:** The L2 withdrawal transaction succeeds and the recorded
application/Explorer state advances without error across the agreed two-batch
observation.

**Capture:** L2 transaction hash, any available L1 reference, amount,
timestamps, start/end state, batch numbers, and observed external wait.

Full L1 withdrawal finalization is not part of this milestone because the
repository does not yet define a deterministic release-specific procedure and
terminal evidence rule. If it is required for the engagement, define and
rehearse that procedure before deployment and track it as additional scope.

### Test 8 — Active Watchdog flows

**Value:** Operators can see continuing evidence of RPC, identity/permission,
transaction, and settlement behavior.

Open an SSH tunnel:

```bash
ssh -L 3100:127.0.0.1:3100 <user>@<vps>
```

Open `http://127.0.0.1:3100` locally. In Grafana **Explore**, select the
Prometheus data source and run:

```promql
watchdog_status
```

The current bundled dashboard does not provide dedicated Watchdog panels, so
use this Explore query for acceptance.

Observe at least two complete ten-minute batch cycles and confirm returned flow
series for:

- RPC;
- SIWE/authentication;
- the 1-wei transfer;
- settlement.

**Pass condition:** A series for each named flow—RPC, SIWE/authentication,
1-wei transfer, and settlement—is present and remains `1` throughout at least
two complete batch cycles, and the settlement observation advances. Missing
flow series fail the test.

**Capture:** Observation start/end times, batch references, Grafana evidence,
and any alert state.

Also confirm the scrape targets during the observation:

```promql
up{job="watchdog"} == 1
```

```promql
up{job="prividium-api"} == 1
```

Prometheus retains seven days in this configuration. Alert rules exist, but no
Alertmanager or external notification channel is configured. Monitoring does
not comprehensively cover host capacity, Docker logs, PostgreSQL, Keycloak,
Explorer, Caddy, or ZKsync OS internals.

### Test 9 — Administration journey

**Value:** An authorized administrator can reach the intended Prividium
management interface without exposing the identity-provider administration
console.

1. Open `https://admin.<domain>`.
2. Authenticate with the authorized administrator.
3. Verify the expected core administration views and permitted actions.
4. Confirm public requests to the Keycloak administration and master-realm
   paths are rejected.

**Pass condition:** The Prividium administration journey works for the approved
administrator while Keycloak administration remains unavailable through the
public edge.

**Capture:** Administrator role, tested views/actions, public-path denial
results, and screenshots without personal or secret data.

## Value review

After the technical tests, conduct a short joint review.

| Evaluation topic | Question for the customer |
| --- | --- |
| Identity | Does the OIDC/WebAuthn journey fit the customer's intended access model well enough to justify deeper IdP integration work? |
| Permissioning | Did the protected RPC and role behavior demonstrate the required control point? |
| Application integration | Can the customer's engineering team see how its application would authenticate and transact? |
| Explorer transaction visibility | Did Explorer provide the required address/hash-based transaction visibility for the evaluation? |
| Ethereum integration | Did deposit, withdrawal progression, and settlement behavior meet the evaluation objective? |
| Operations | Are the available health and funding signals sufficient for this evaluation, and what would be required for production? |
| Ownership | Is the division of customer and Matter Labs responsibilities clear? |

Record conclusions, gaps, and follow-up decisions. Do not translate a
successful sandbox test into a production security, scale, or compliance
claim.

## Gate 4: Acceptance and handover

All Tests 1–9 are required for this core adoption milestone and must be marked
`PASS` or `FAIL`. A required test cannot be deferred. Removing a test from the
agreed evaluation requires a scope exception approved before deployment. The
exception records:

- a reason;
- an owner;
- a due date;
- the effect on the evaluation conclusion;
- explicit approval by both teams.

An evaluation with a removed or failed core test must be reported as incomplete
or accepted with exceptions; it must not be presented as a complete core
evaluation success.

Handover is complete when the adoption record contains:

- customer and Matter Labs owners;
- environment URLs and chain identity;
- release and repository versions;
- role inventory, public manifest, and healthy deployment summary;
- actual deployment timings;
- every test result and evidence reference;
- accepted risks and unresolved exceptions;
- monitoring and operator-funding owner;
- customer technical sign-off.

Continue to [Operating the
evaluation](05-operating-the-evaluation.md).
