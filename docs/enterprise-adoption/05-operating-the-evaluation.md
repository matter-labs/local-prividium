# Operating the evaluation

| Document metadata | Value |
| --- | --- |
| Status | Draft — blocked for customer release pending the release funding benchmark |
| Purpose | Define the minimum day-to-day operating practices for an accepted Prividium evaluation |
| Audience | Customer platform operators, identity administrators, blockchain operators, and evaluation owners |
| Scope | Routine status, logs, monitoring, restart, funding, configuration, identity, DNS, and issue triage |
| Applicable release | [versions.lock.yaml](../../deployment/versions.lock.yaml) |
| Document version | 0.1-draft |
| Repository commit | Recorded per customer in the adoption record; must match the approved handoff |
| Maintainer | Matter Labs Prividium Engineering |
| Last successful customer-release rehearsal | Not yet recorded |
| Required approvers | Technical and security approvers: TBD before customer release |
| Next review | After the release rehearsal or any locked-release change |
| Last revised | 2026-07-23 |

This document keeps the accepted core environment usable during its evaluation
window. It is not a production operations manual, disaster-recovery plan, or
support SLA.

## Assign operating owners

Before handover, name owners for:

| Area | Responsibility |
| --- | --- |
| VPS and Docker | Host access, patching policy, capacity, disk, logs, and container lifecycle |
| DNS and TLS | Core DNS records, inbound routing, and ACME reachability |
| Secrets | Encrypted environment and age private-identity custody |
| Identity | Core realm users, credentials, and authorized administration |
| Blockchain | Private RPC, operator balances, Sepolia transactions, and chain-state review |
| Monitoring | Routine dashboard review and response to local alerts |
| Evaluation | Test schedule, user coordination, findings, and closeout |
| Matter Labs liaison | Product/deployment questions and agreed escalation path |

The presence of dashboards and alert rules does not mean either party is
staffing an alert-response service.

## Routine command set

Run from the repository root on the VPS.

Show currently running enabled services:

```bash
tools/sandbox status
```

Show running and completed/stopped services, including one-shot exit state:

```bash
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  --profile "*" \
  ps --all --no-trunc
```

Follow the default core path:

```bash
tools/sandbox logs
```

Follow named services:

```bash
tools/sandbox logs zksyncos prividium-api watchdog
```

Validate the configured deployment model:

```bash
tools/sandbox validate
```

Recheck the local operator environment:

```bash
tools/sandbox doctor
```

Regenerate the public health summary:

```bash
tools/sandbox summary
```

Do not include terminal output containing secrets or provider credentials in
shared tickets or evaluation records.

## Recommended operating cadence

| Frequency | Check |
| --- | --- |
| Before an evaluation session | Core service status, public summary, DNS/HTTPS, private RPC, disk free space, and operator balances |
| Daily while actively evaluating | Watchdog flows, API availability, operator balances, failed/restarting containers, and host disk/memory |
| After configuration change | Static validation, affected service logs, public summary, and the relevant human smoke test |
| Across at least two batches after chain-affecting work | Watchdog RPC, auth, transfer, and settlement flows |
| At evaluation review | Open exceptions, test evidence, remaining Sepolia runway, and customer findings |

Host CPU, memory, disk, and Docker-log growth are customer responsibilities;
the bundled Prometheus configuration does not collect a complete host and
container platform view.

## Understand service state

The accepted core state contains:

- 15 long-running services that should remain running;
- three one-shot jobs that should remain successfully exited:
  `chain-preflight`, `bridge-funds`, and
  `watchdog-permissions-setup`.

Do not restart a successful one-shot merely because it is not running.
Investigate a job when it has a nonzero exit code, its prerequisite changed, or
the documented convergent workflow calls for it.

## Monitoring coverage

The bundled monitoring provides:

- Prividium API availability;
- Watchdog RPC, authentication, transfer, and settlement flows;
- L1 operator balances;
- Prometheus target health;
- a local Grafana interface.

Default alert rules cover:

- a Watchdog flow failing for five minutes;
- missing Watchdog metrics for five minutes;
- an operator remaining below 0.01 Sepolia ETH for five minutes;
- Prividium API metrics being unavailable for five minutes.

Prometheus retains seven days of data. No Alertmanager or external notification
channel is configured. The stack does not provide comprehensive metrics for
host capacity, PostgreSQL, Keycloak, Explorer, Caddy, Docker logs, or ZKsync OS
internals.

Access Grafana through an SSH tunnel:

```bash
ssh -L 3100:127.0.0.1:3100 <user>@<vps>
```

Then open `http://127.0.0.1:3100`.

Use Grafana Explore with the Prometheus data source for the core checks:

```promql
watchdog_status
```

A series for each required flow—RPC, SIWE/authentication, 1-wei transfer, and
settlement—must be present and report `1`. A missing series is not healthy.

```promql
up{job="watchdog"} == 1
```

```promql
up{job="prividium-api"} == 1
```

The current bundled dashboard does not include dedicated Watchdog status
panels; use Explore or add customer-approved dashboards during the evaluation.

## Restarting the stack

Restart only the 15 long-running services:

```bash
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  restart --no-deps \
  zksyncos postgres keycloak prividium-api user-panel admin-panel caddy \
  block-explorer-api block-explorer-app block-explorer-worker \
  block-explorer-data-fetcher watchdog prometheus grafana \
  operator-balance-exporter
```

Keep `--no-deps` and the explicit service list. A bare `docker compose restart`
can start completed one-shot containers again, including the Watchdog
bridge-funding job.

Review status and key logs afterward:

```bash
tools/sandbox status
tools/sandbox logs zksyncos prividium-api caddy watchdog
tools/sandbox summary
```

Use the explicit `ps --all --no-trunc` command above when one-shot exit status
is relevant.

If rendered configuration or an image changed through an approved change,
rerun:

```bash
tools/sandbox deploy
```

This validates, builds, recreates the core model as needed, and performs the
public summary checks. It also includes the balance-convergent Watchdog bridge
job. If a previous deploy was interrupted while `bridge-funds` may have
submitted a transaction, inspect its logs and transaction state before
rerunning.

## Operator funding

The release funding policy targets a defined core evaluation runway. Actual
runway varies with Sepolia gas prices, batch activity, and the completed
release benchmark.

Monitor the public operator addresses from
`deployment/public/roles.md`. Refill an operator before it reaches the
configured low-balance floor.

After `deployment/public/manifest.json` exists, the provisioning distribution
helper is intentionally disabled. It must not replenish one-time deployer,
governor, or chain-owner accounts.

For an evaluation extending beyond the funded runway:

1. Review the operator address and current confirmed balance.
2. Obtain the customer's normal testnet-transaction approval.
3. Move additional Sepolia ETH from the sandbox funding wallet to only the
   settlement operator that requires it.
4. Record the operational transaction outside the initial provisioning plan.
5. Confirm the balance exporter and alert return to the expected state.

Do not rotate a commit, prove, or execute key by editing the environment alone.
The on-chain role must be changed first under a separately reviewed procedure.

## Configuration and secret changes

The edit/decrypt/deploy sequence is sufficient only for an environment setting
that is read at container start and has no corresponding database, identity,
on-chain, DNS, or release-state change.

For such an approved restart-read setting, open the encrypted environment:

```bash
tools/sandbox edit-secrets
```

Render the protected runtime environment:

```bash
tools/sandbox decrypt
```

Recreate and validate the affected services:

```bash
tools/sandbox deploy
```

Do not use this generic sequence by itself for:

- domains, public origins, OIDC issuer, or client settings;
- database credentials;
- signing keys or on-chain roles;
- the L2 chain ID;
- product, protocol, or image versions.

Those changes require separately reviewed procedures that update every
corresponding stateful or external system. For example, editing a database
password only in the environment breaks connectivity, and changing a domain
does not update an existing Keycloak realm import.

The supported private-RPC replacement sequence is documented in the next
section.
The corresponding PostgreSQL role must be changed in the existing database as
part of the same approved change.

Never change the L2 chain ID after broadcast.

## Replacing the private RPC

The replacement endpoint must serve Ethereum Sepolia and support historical
calls/logs, receipts, and blob fee data.

Use:

```bash
tools/sandbox edit-secrets
# Replace SEPOLIA_RPC_URL, save, and exit.

tools/sandbox decrypt
tools/sandbox deploy
```

Then inspect ZKsync OS and Watchdog across at least two batches:

```bash
tools/sandbox logs zksyncos watchdog
```

Record the provider change without recording the credential-bearing URL.

## DNS and certificate triage

When a core hostname has no valid certificate:

1. Confirm its `A` record returns the intended VPS IPv4 address.
2. Remove an unintended `AAAA` record or verify the IPv6 route and firewall.
3. Confirm TCP 80/443 reaches Caddy.
4. Confirm the host clock is synchronized.
5. Inspect:

   ```bash
   tools/sandbox logs caddy
   ```

6. Confirm the ACME email and hostname configuration through the approved
   secret-review process.

Caddy certificate state persists in `caddy_data`. Do not delete the volume as
a routine certificate fix.

## Accessing Keycloak administration

The Keycloak administration interface is deliberately not public. Use the
administration CLI inside the container:

```bash
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  exec keycloak /opt/keycloak/bin/kcadm.sh --help
```

Apply the customer's normal identity change and audit process.

The core realm import runs only when initializing a new Keycloak database.
Editing `dev/keycloak/realm-export.json` does not update an existing realm.
Likewise, PostgreSQL initialization scripts run only against a new data
directory.

This milestone does not define exact add-user, disable-user, or role-mapping
commands for an existing core realm. Agree, test, and record that lifecycle
procedure before assigning customer identity operations beyond the generated
administrator. The `kcadm.sh --help` command above proves the private
administration path; it is not itself a user-provisioning procedure.

## Issue triage

| Symptom | First checks |
| --- | --- |
| Public application unavailable | DNS target, Caddy logs, certificate, upstream container status |
| OIDC login fails | Exact issuer URL, Keycloak state/logs, host clock, browser cookies/WebAuthn support |
| API or RPC unavailable | `prividium-api` health/logs, PostgreSQL, ZKsync OS, private RPC |
| Explorer missing a transaction | Worker/data-fetcher logs, ZKsync OS, database state, indexing delay |
| Watchdog flow failing | Named flow, wallet balance, API/RPC health, settlement progress |
| Operator low-balance alert | Public role address, confirmed Sepolia balance, approved refill |
| One-shot job failed | Job logs, prerequisite service, confirmed on-chain state before retry |
| Public summary incomplete | Protected incomplete report, service status, public endpoint checks |

Use:

```bash
tools/sandbox logs <service-name>
```

Fix the prerequisite, then use the documented convergent entry point. Do not
bypass bytecode, manifest, role, funding, or chain-identity checks.

## Prohibited routine actions

Do not:

- run `docker compose down -v`;
- delete or recreate `/etc/prividium/runtime/chain`;
- generate a new identity set for an existing chain;
- change the L2 chain ID;
- expose raw RPC, databases, Keycloak administration, Prometheus, or Grafana;
- commit decrypted secrets or protected runtime reports;
- edit operator keys without the corresponding on-chain role change;
- run on-chain operator commands concurrently;
- enable optional profiles as an unreviewed core change;
- update a server image without reviewing on-chain protocol compatibility.

## Evaluation closeout

At the end of the evaluation:

- record the final product and technical findings;
- record remaining operator and sponsor balances;
- identify any data or evidence the customer must retain;
- revoke temporary user and operator access under the customer's policy;
- decide whether the VPS remains active;
- create a separate approved decommissioning plan if removal is required.

Removing local infrastructure does not remove Sepolia contracts or testnet
transaction history.
