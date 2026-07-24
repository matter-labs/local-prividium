# Sandbox operations runbook

This runbook covers an already deployed sandbox. For first-time deployment, use [Sandbox setup](SETUP.md).

## Routine checks

Show currently running state:

```bash
tools/sandbox status
```

Include completed/stopped one-shot containers and full exit details:

```bash
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  --profile "*" \
  ps --all --no-trunc
```

Follow the default startup path:

```bash
tools/sandbox logs
```

Follow specific services:

```bash
tools/sandbox logs zksyncos prividium-api watchdog
```

Run configuration and security checks:

```bash
tools/sandbox validate
tools/sandbox doctor
tools/sandbox summary
```

Monitor operator balances in Grafana/Prometheus. The default alert fires after an operator remains below 0.01 Sepolia ETH for five minutes.

## Restart

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

If configuration or images changed, rerun the normally convergent deployment:

```bash
tools/sandbox deploy
```

If an earlier run may have submitted a Watchdog bridge deposit before
`bridge-funds` failed, inspect its logs and transaction state before rerunning
deployment.

For an optional capability:

```bash
tools/sandbox enable sso
tools/sandbox enable webhook
tools/sandbox enable demo
```

## Funding after deployment

The provisioning distribution helper is intentionally disabled after
`deployment/public/manifest.json` exists. It must not replenish one-time
deployer, governor, or chain-owner accounts after broadcast.

The initial policy funds commit, prove, and execute operators for a 14-day
evaluation runway. For a longer evaluation:

1. Review operator addresses in `deployment/public/roles.md`.
2. Review current balances and the low-balance alert.
3. Send additional Sepolia ETH from the sandbox funding wallet to only the
   operator that needs it, using the customer’s normal transaction approval
   process.
4. Record that operational transfer outside the provisioning reports.

Customers still add ETH only to the sandbox funding wallet; they do not fund
role accounts directly.

Do not rotate commit, prove, or execute keys by editing the environment alone. Update the on-chain role first, then update SOPS, decrypt, and restart ZKsync OS.

Optional SSO/bundler and demo deposits are outside the benchmarked core
one-ETH policy. Their enable commands perform a conservative incremental
sponsor preflight before starting the bridge jobs. A bridge job is
balance-convergent after its prior transaction is confirmed; if a transaction
may still be in flight, inspect its nonce, receipt, logs, and balances before
retrying.

## Edit or rotate secrets

The edit/decrypt/deploy sequence is sufficient only for settings read at
container restart that do not require a corresponding database, identity,
on-chain, DNS, or release-state change.

Open the encrypted environment:

```bash
tools/sandbox edit-secrets
```

Render the new protected runtime file:

```bash
tools/sandbox decrypt
```

Then recreate affected services:

```bash
tools/sandbox deploy
```

Domain/OIDC changes, database passwords, signing keys/on-chain roles, chain
identity, and release upgrades require separately reviewed procedures. For
example, database password rotation also requires changing the PostgreSQL role
inside the existing database, and domain changes require updates to the
existing Keycloak realm. Editing only the environment will break connectivity.

## Upgrade

1. Update the component version/source entry in `deployment/versions.lock.yaml`.
2. Update the corresponding image digest or source commit in its Compose component file.
3. Build and validate:

   ```bash
   tools/sandbox validate
   docker compose \
     --env-file /etc/prividium/runtime/sandbox.env \
     build
   ```

4. Pull registry images and deploy:

   ```bash
   docker compose \
     --env-file /etc/prividium/runtime/sandbox.env \
     pull

   tools/sandbox deploy
   ```

5. Confirm Watchdog remains healthy across two batch cycles.

Never change an on-chain protocol version by replacing only the server image.

## Database backup

Create a protected destination:

```bash
install -d -m 0700 backups
```

Dump all sandbox databases:

```bash
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  exec -T postgres \
  pg_dumpall -U postgres --clean --if-exists \
  > "backups/postgres-$(date -u +%Y%m%dT%H%M%SZ).sql"
```

Keep at least seven daily backups and copy them off the VPS if the sandbox data matters.

Test restore procedures on a disposable host. A backup that has not been restored is not a verified backup.

## Certificates and DNS

If an enabled hostname has no certificate:

1. Verify its `A` record points to the VPS.
2. Verify TCP 80/443 reaches Caddy.
3. Check Caddy:

   ```bash
   tools/sandbox logs caddy
   ```

4. Confirm the ACME email and hostname in the runtime environment.

Caddy state persists in `caddy_data`. SSO and demo hostnames use on-demand issuance because those services are optional.

## Provider outage

ZKsync OS retries provider failures. If the provider must be replaced:

```bash
tools/sandbox edit-secrets
# Replace SEPOLIA_RPC_URL.

tools/sandbox decrypt
tools/sandbox deploy
```

The replacement must support historical calls, historical logs, receipts, and EIP-4844 blob data. Chain preflight verifies these capabilities before ZKsync OS starts.

## Keycloak administration

The Keycloak admin console has no host port and Caddy blocks it publicly. Use `kcadm.sh` inside the Keycloak container:

```bash
docker compose \
  --env-file /etc/prividium/runtime/sandbox.env \
  exec keycloak /opt/keycloak/bin/kcadm.sh --help
```

The core realm import runs only against a new Keycloak database. Apply later identity changes through `kcadm.sh`; do not delete the volume merely to reimport JSON.

## Initialization failures

Permission seeding and contract setup jobs are designed to be idempotent.
Funding and bridge jobs are balance-convergent only after any prior transaction
is confirmed. If their transaction state is ambiguous, inspect the nonce,
receipt, logs, and balances before retrying.

1. Read the failed job:

   ```bash
   docker compose \
     --env-file /etc/prividium/runtime/sandbox.env \
     ps --all
   ```

2. Inspect its logs:

   ```bash
   tools/sandbox logs <service-name>
   ```

3. Fix the prerequisite and rerun `tools/sandbox deploy` or the relevant `tools/sandbox enable` command.

Contract jobs verify existing bytecode before skipping. Do not bypass a bytecode mismatch without independently verifying the deployed address.

## Partial chain broadcast

A broadcast failure can occur after irreversible Sepolia transactions have
confirmed but before the public manifest is complete.

1. Do not delete `/etc/prividium/runtime/chain`, create a new chain ID, or rerun
   funding distribution.
2. Preserve the readiness report, bootstrap output, state file, and transaction
   output.
3. Compare confirmed transaction hashes with
   `/etc/prividium/runtime/chain/out/executed/transactions.json`.
4. Resolve the provider, nonce, or funding failure.
5. Rerun the same chain bootstrap only after confirming the deployer’s
   idempotency behavior for the completed steps.

Escalate an ambiguous on-chain state before taking further action. A local
cleanup cannot remove already deployed Sepolia contracts.

## SOPS recovery

The encrypted sandbox environment is intentionally not committed. Restore both
`deployment/secrets/sandbox.enc.env` from the customer’s secret-storage backup
and the corresponding age private identity from its separate recovery
location, then:

```bash
tools/sandbox decrypt
tools/sandbox doctor
```

Confirm the regenerated runtime server configuration still corresponds to `deployment/public/manifest.json`.

## Destructive reset

`docker compose down -v` deletes chain state, databases, identity data, monitoring history, certificates, and optional contract metadata. Sepolia contracts remain deployed.

Do not use volume deletion as a redeployment mechanism for an existing chain ID. If a full reset is truly intended, back up all required data and create a new sandbox chain ID.
