# Core deployment playbook

| Document metadata | Value |
| --- | --- |
| Status | Draft — blocked for customer release pending the release funding benchmark |
| Purpose | Take a prepared amd64 VPS from an approved release checkout to a healthy core Prividium evaluation |
| Audience | Designated deployment operator, independent reviewer, and customer platform/blockchain engineers |
| Estimated execution | 2–4 hours elapsed after prerequisites; human product acceptance is additional |
| Highest-risk action | Creation of the dedicated ecosystem and chain on Ethereum Sepolia |
| Applicable release | [versions.lock.yaml](../../deployment/versions.lock.yaml) |
| Document version | 0.1-draft |
| Repository commit | Recorded per customer in the adoption record; must match the approved handoff |
| Maintainer | Matter Labs Prividium Engineering |
| Last successful customer-release rehearsal | Not yet recorded |
| Required approvers | Technical and security approvers: TBD before customer release |
| Next review | After the release rehearsal or any locked-release change |
| Last revised | 2026-07-23 |

This playbook deploys the core stack only. Do not add Compose profiles or alter
the locked release during the deployment session.

Use the repository's single operator interface:

```text
tools/sandbox
```

Run all commands from the repository root on the target VPS unless a command
states otherwise.

## Before stage 0: receive and verify the release

Matter Labs must provide the approved repository delivery mechanism and exact
Git commit through the engagement's change record. Place that checkout on the
target VPS before the deployment session.

From the repository root:

```bash
git rev-parse HEAD
git status --short
```

The reported commit must exactly match the approved commit in the adoption
record. The working tree must contain no unapproved change. If the repository
was delivered as a non-Git source bundle, Matter Labs must provide an
equivalent approved artifact digest and verification procedure before customer
handoff; this guide does not invent one.

## Deployment controls

Before the first command:

- name one executing operator and one independent reviewer;
- prohibit parallel funding, broadcast, or deployment sessions;
- open a copy of the [adoption record](templates/ADOPTION_RECORD.md);
- record the repository commit and release-lock identity;
- confirm that the customer approved Sepolia spending and chain creation;
- confirm that no optional capability is part of this deployment.

## Stage plan

| Stage | Initial planning allowance | External wait | On-chain write | Exit evidence |
| --- | ---: | ---: | :---: | --- |
| Approved release verification | 5–10 min | Delivery/approval dependent | No | Commit or artifact digest matches the handoff record |
| Local prerequisites | 5–10 min | None | No | `doctor` has no blocker |
| Generate and review identities | 10–20 min | None | No | Encrypted environment and public role inventory |
| Create protected runtime | 5–10 min | None | No | Runtime environment is mode `0600` |
| Fund and distribute | 15–25 min | Sepolia confirmation | Yes | Protected funding plan is `READY`; distribution completes |
| Prepare chain and prebuild core | 20–60 min | Build/download time | No | Prepared manifest, provenance record, and successful default pull/build |
| Readiness review | 10–20 min | DNS/registry/RPC dependent | No | Protected readiness report is `READY` |
| Broadcast ecosystem and chain | 10–30 min | Sepolia inclusion | **Yes — highest risk** | Public chain manifest |
| Deploy core services | Initial 20–45 min target | Watchdog bridge execution is currently unbounded; image, ACME, and startup waits also vary | Yes, Watchdog bridge deposit | Healthy public deployment summary |

Customer funding, role distribution, chain broadcast, and the Watchdog bridge
deposit all create testnet transactions that cannot be undone locally. The
broadcast is the highest-risk gate because it establishes the chain identity
and contracts.

## 0. Confirm release readiness

Check the release funding status:

```bash
jq -r '.benchmark.status' deployment/funding-policy.json
```

Required result:

```text
complete
```

If the result is `pending`, stop. Matter Labs must complete the release
rehearsal in `docs/FUNDING_BENCHMARK.md`; the customer must not bypass this
control.

A `complete` value alone is not sufficient. Confirm every Gate 0 row in the
adoption record passes, including the approved rehearsal mechanism,
policy-aware customer reports, exact tested host/container versions, evidence,
and independent review.

Check the local environment:

```bash
tools/sandbox doctor
```

Proceed only when it reports no blocking local issue. A passing doctor does not
prove that DNS points to this VPS, the browser RPC supports CORS, the host has
enough resources, or every cold-build dependency is reachable. Those items
must already be complete in the readiness checklist.

Record:

- command result;
- host name and public IP;
- Docker and Compose versions;
- executing operator and reviewer;
- any approved exception.

## 1. Generate the sandbox identities

Run:

```bash
tools/sandbox init
```

Provide:

- sandbox base domain;
- ACME notification email;
- initial administrator email;
- private Sepolia RPC URL;
- public browser-safe Sepolia RPC URL;
- customer-controlled age recipient.

The private RPC prompt is hidden. The command generates a high 31-bit L2 chain
ID, distinct role keys, application keys, database passwords, and session
secrets.

Expected outputs:

```text
deployment/secrets/sandbox.enc.env
deployment/public/roles.md
```

The first file is SOPS-encrypted and intentionally gitignored. The second
contains public addresses, roles, domain, chain ID, and a role-set fingerprint.

`init` refuses to overwrite an existing encrypted environment. If an
environment already exists, stop and determine whether this is a resumed
deployment. Do not remove it merely to create a new identity set.

### Review gate

The operator and reviewer must confirm:

- the domain is correct;
- the L2 chain ID is the intended new chain ID;
- every generated role is present and distinct;
- only one address is labelled for customer funding;
- no private key or provider credential appears in the public report;
- the encrypted file is copied to the approved customer secret store;
- named custodians control a separately stored matching age private identity.

Record or commit `deployment/public/roles.md` according to the customer's
change process.

## 2. Create the protected runtime

Create the runtime directory:

```bash
sudo install -d -m 0700 -o "$USER" /etc/prividium/runtime
```

Make the approved age private identity available to SOPS for the designated
operator session. For a customer-approved protected key file, use:

```bash
export SOPS_AGE_KEY_FILE=/approved/protected/path/age-identity.txt
stat -c '%a %n' "$SOPS_AGE_KEY_FILE"
```

The key file must be owned by the approved operator and have mode `0600`.
Customers using a secret-agent or other SOPS integration should follow that
approved mechanism instead. Do not copy the age identity into the repository
or command history.

SOPS needs decryption access again during funding, readiness, and the readiness
rerun inside `tools/sandbox broadcast`. Retain the approved session access
through successful broadcast.

Decrypt:

```bash
tools/sandbox decrypt
```

Expected output:

```text
/etc/prividium/runtime/sandbox.env
```

Verify without printing its contents:

```bash
stat -c '%a %n' /etc/prividium/runtime /etc/prividium/runtime/sandbox.env
```

On Linux, the expected modes are:

```text
700 /etc/prividium/runtime
600 /etc/prividium/runtime/sandbox.env
```

Do not paste, log, commit, or attach the decrypted environment to a support
case.

## 3. Create the funding plan

Generate the live plan:

```bash
tools/sandbox funding
```

The first run may return nonzero when the sandbox funding wallet is empty, but
it still writes:

```text
/etc/prividium/runtime/reports/funding-plan.md
```

Review the report and `deployment/public/roles.md`. The customer sends the
release-approved amount to the one address identified as the sandbox funding
wallet. For the current target policy, that amount is exactly 1 Sepolia ETH
only after the benchmark has completed.

Wait for confirmation, then regenerate the plan:

```bash
tools/sandbox funding
```

Required result:

```text
READY
```

Confirm:

- the plan ID is present;
- recipient addresses match the public role inventory;
- only confirmed shortfalls will be transferred;
- the target allocation and retained buffer match the benchmarked policy;
- optional-profile funding is absent.

The funding plan does not report nonce state. `funding apply` checks the source
wallet for a pending nonce immediately before it sends transfers and stops if
one exists.

## 4. Apply the funding plan

Run:

```bash
tools/sandbox funding apply
```

Enter the complete plan ID when prompted. The command transfers only confirmed
shortfalls and confirms each recipient before continuing.

These are real Sepolia transactions. Do not run this command from a second
session.

If execution is interrupted:

1. Stop all further funding invocations.
2. Wait for any pending sponsor transaction to settle.
3. Regenerate the funding plan.
4. Review confirmed balances and the new plan before applying anything else.

The plan is balance-convergent; confirmed chain balances, not local terminal
output, are the source of truth.

## 5. Prepare the chain

Run the non-broadcasting preparation:

```bash
tools/sandbox prepare
```

This builds the locked zk-deployer and Protocol sources, simulates the
ecosystem/chain creation, and generates review artifacts without submitting
transactions.

As the designated operator, verify that the protected review outputs are
readable without `sudo`:

```bash
test -r /etc/prividium/runtime/chain/out/manifest.json
test -r /etc/prividium/runtime/chain/out/preparation.json
```

Both commands must exit successfully. If either fails, stop. Do not compensate
with broad file modes or an ad hoc recursive ownership change. The rootful
Docker ownership model must be fixed and rehearsed as a release issue before
customer handoff.

Review:

```text
/etc/prividium/runtime/chain/out/manifest.json
/etc/prividium/runtime/chain/out/preparation.json
/etc/prividium/runtime/chain/out/
deployment/versions.lock.yaml
```

The reviewer must confirm:

- L1 is Ethereum Sepolia;
- the L2 chain ID matches the role inventory;
- ETH is the base and fee token;
- rollup DA and expected batch configuration are selected;
- Protocol and zk-deployer commits match the release lock;
- Safe bundles, targets, and calldata are consistent with the intended
  deployment;
- preparation provenance binds the manifest, chain ID, and source commits;
- the cold build completed without unapproved source substitution.

Preparation is non-broadcasting. Rerun it only against the same approved
identity set and chain intent.

### Pull and build the complete default stack

`tools/sandbox prepare` builds the chain-bootstrap artifact only. Before
creating the chain, verify every default remote image and local core build:

```bash
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  pull --ignore-buildable

docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  build
```

These commands do not start services or submit transactions. They move the
cold image, source, and package-egress test before the irreversible broadcast.
Proceed only when both commands complete successfully.

Record the results, elapsed build time, and any customer-approved egress
exception in the adoption record.

## 6. Run the pre-broadcast readiness gate

Run:

```bash
tools/sandbox readiness
```

Expected protected report:

```text
/etc/prividium/runtime/reports/readiness.md
```

The gate checks:

- encrypted and decrypted configuration controls;
- role-set identity;
- benchmarked funding policy and current balances;
- private RPC chain and capabilities;
- high-range L2 chain ID and Chainlist collision;
- preparation provenance and source locks;
- absence of a conflicting public manifest;
- amd64 architecture, Docker, Compose, and static model validation;
- access to the core private Prividium images;
- DNS resolution.

### Stop/go policy

- `READY`: proceed after joint review.
- `READY WITH WARNINGS`: stop by default. Proceed only with a documented joint
  exception, named owner, and resolution deadline.
- `BLOCKED`: do not broadcast.

The current tool treats unresolved DNS as a warning. The customer-facing
applications cannot pass final HTTPS and OIDC checks until DNS points to this
VPS, so the preferred enterprise policy is to resolve DNS before broadcast.

The operator and reviewer sign the readiness section of the adoption record
before continuing.

## 7. Broadcast the ecosystem and chain

Run:

```bash
tools/sandbox broadcast
```

The command reruns readiness, prints the chain ID, and requires a
chain-specific confirmation. Verify the readiness output displays the intended
sandbox domain and L2 chain ID before entering the requested value.

This stage creates the dedicated ecosystem and chain contracts, records the
testnet verifier, generates chain runtime configuration, and writes:

```text
deployment/public/manifest.json
```

Review and record:

- L1 and L2 chain IDs;
- ecosystem and chain contract addresses;
- genesis hash;
- source commits;
- operator addresses;
- Sepolia transaction hashes;
- fake-proof/testnet-verifier declarations.

Commit or otherwise retain the public manifest under the customer's change
process.

After successful broadcast, the core deploy reads the protected runtime
environment and no longer needs to decrypt the SOPS file. End the authorized
age-key session if customer policy requires it:

```bash
unset SOPS_AGE_KEY_FILE
```

Remove any temporary target-host key access through the customer's approved
secret mechanism. Reauthorize it later only for an operation that must decrypt
or edit the encrypted environment.

### Partial-broadcast stop procedure

If the command fails after any Sepolia transaction may have been submitted:

1. Stop. Do not rerun broadcast.
2. Preserve `/etc/prividium/runtime/chain` and the complete terminal output.
3. Do not generate a new chain ID.
4. Do not rerun funding distribution.
5. Record every known transaction hash and its confirmed state.
6. Escalate for an explicit state review before any retry.

Deleting the VPS or Docker volumes cannot remove confirmed Sepolia contracts.
This safety procedure is part of deployment control, not a disaster-recovery
plan.

## 8. Deploy the core services

Run:

```bash
tools/sandbox deploy
```

The command:

1. renders browser configuration;
2. validates the complete Compose model;
3. builds locally maintained images;
4. starts the default core stack;
5. after startup prerequisites complete, waits up to ten minutes for core
   service and public-interface checks.

Core startup includes the `bridge-funds` job, which submits the Watchdog
L1-to-L2 deposit when its target balance is not met. In the current
implementation, that job can poll indefinitely for L2 execution before the
ten-minute deployment-summary timer starts. Gate 0 requires a reviewed timeout
and ambiguous-transaction procedure before customer release.

Successful completion writes:

```text
deployment/public/deployment-summary.md
```

An incomplete deployment writes a protected diagnostic:

```text
/etc/prividium/runtime/reports/deployment-summary.incomplete.md
```

The current generated diagnostic ends with a generic instruction to rerun
`tools/sandbox summary`. Use the decision below instead. Gate 0 requires the
generated guidance to be aligned before customer release.

If deployment fails:

```bash
tools/sandbox logs
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  --profile "*" \
  ps --all --no-trunc
```

For a specific service:

```bash
tools/sandbox logs <service-name>
```

If all required containers and one-shot jobs are already in their expected
state and only a slow DNS, certificate, or endpoint check failed, fix that
condition and regenerate the summary:

```bash
tools/sandbox summary
```

If a required container is missing/stopped or a one-shot job failed, correct
the cause and rerun:

```bash
tools/sandbox deploy
```

`deploy` is normally convergent, but do not rerun it if `bridge-funds` may have
submitted a deposit and then lost progress before L2 execution. Inspect the job
logs and transaction state first; resume only after the deposit state is
unambiguous.

## 9. Review automated deployment evidence

The successful deployment summary proves that:

- the public manifest matches the runtime chain and locked sandbox release;
- 15 core long-running services are running or healthy;
- three core one-shot jobs completed successfully;
- user, administration, API, Explorer, and Explorer API HTTPS endpoints
  responded within the tool's acceptance ranges;
- API health responded successfully;
- an unauthenticated protected RPC request was denied;
- OIDC discovery advertises the exact configured issuer.

It does not prove authenticated end-to-end transactions, complete Explorer
semantics, Watchdog flow health, host capacity, or the product-value journey.
Those require the next document.

Record:

- `deployment/public/roles.md`;
- `deployment/public/manifest.json`;
- `deployment/public/deployment-summary.md`;
- actual stage start/end times;
- approved warnings or exceptions;
- operator and reviewer sign-off.

Continue to [Evaluation and
acceptance](04-evaluation-and-acceptance.md).

## Retry reference

| Command | Retry guidance |
| --- | --- |
| `tools/sandbox doctor` | Read/check operation; rerun after local fixes |
| `tools/sandbox init` | Creates a new identity set and refuses an existing encrypted file; do not force replacement during a resumed deployment |
| `tools/sandbox decrypt` | Regenerates the protected runtime environment from SOPS |
| `tools/sandbox funding` | Read/report operation; safe to regenerate |
| `tools/sandbox funding apply` | Sends transactions; wait for pending nonce and regenerate the plan before retrying |
| `tools/sandbox prepare` | Non-broadcasting; rerun only with the same approved intent and identities |
| `tools/sandbox readiness` | Read/report gate; rerun after blockers are fixed and before broadcast |
| `tools/sandbox broadcast` | Never blindly retry after possible partial success |
| `tools/sandbox deploy` | Normally convergent, but inspect an ambiguous Watchdog bridge transaction first |
| `tools/sandbox summary` | Read/check operation; rerun after service or endpoint fixes |
