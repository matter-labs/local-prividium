# Deployment components

`docker-compose.yaml` is the only operator entrypoint. It keeps the public Prividium applications together and includes smaller Compose files grouped by responsibility.

## Compose map

| File | Responsibility | Services |
| --- | --- | --- |
| `docker-compose.yaml` | Core public application edge | Caddy, Prividium API, user panel, admin panel |
| `docker-compose-platform.yaml` | Durable platform and chain | PostgreSQL, Keycloak, chain bootstrap/preflight, ZKsync OS |
| `docker-compose-explorer.yaml` | Block Explorer | API, application, worker, data fetcher |
| `docker-compose-permissioning.yaml` | Idempotent database authorization | Watchdog user, webhook M2M, SSO contracts/templates |
| `docker-compose-monitoring.yaml` | Health and funding | Watchdog, Watchdog funding, Prometheus, Grafana, operator balance exporter |
| `docker-compose-optional.yaml` | Opt-in infrastructure | SSO, EntryPoint, bundler, webhook runtime |
| `docker-compose-demos.yaml` | Example applications | Institutional demo identity, funding, contracts, seed, and app |

Inspect the resolved model at any time:

```bash
tools/sandbox components
tools/sandbox validate
docker compose --env-file /etc/prividium/runtime/sandbox.env config
```

## Profiles

| Profile | Default | Adds | Required configuration |
| --- | --- | --- | --- |
| `chain-bootstrap` | Off | Operator-invoked zk-deployer job | Explicit prepare/broadcast workflow |
| `sso` | Off | EntryPoint, SSO contracts/apps, bundler and funding | `BUNDLER_ENABLED=true`, `auth` DNS |
| `webhook` | Off | Webhook M2M seed and webhook service | `WEBHOOK_ENABLED=true` |
| `institutional-demo` | Off | Demo realm, contracts, seed and app | `sso` profile, `demo` DNS |

Use `tools/sandbox enable` instead of spelling profile combinations manually.

## Networks

| Network | Purpose |
| --- | --- |
| `edge` | Caddy’s public edge |
| `app` | Internal service-to-service HTTP/RPC |
| `data` | Internal-only database access |

Only Caddy publishes wildcard-bound ports. Grafana binds to `127.0.0.1:3100`; every other internal port remains on Compose networks.

## Persistent state

| Volume/path | Stores |
| --- | --- |
| `zksyncos_db` | L2 node state |
| `postgres_data` | Prividium, Explorer, Keycloak, and webhook databases |
| `keycloak_data` | Keycloak runtime state |
| `caddy_data`, `caddy_config` | ACME account and certificates |
| `prometheus_data`, `grafana_data` | Monitoring history and Grafana state |
| `sso_runtime` | SSO artifacts, addresses, and verified runtime code hashes |
| `institutional_demo_runtime` | Demo contract output |
| `/etc/prividium/runtime/chain` | Secret chain intent, wallets, state, genesis, and server configuration |
| `/etc/prividium/runtime/reports/funding-plan.md` | Protected live balances, allocation, reserve, and plan ID |
| `/etc/prividium/runtime/reports/readiness.md` | Protected pre-broadcast decision record |
| `/etc/prividium/runtime/reports/deployment-summary.incomplete.md` | Protected failed-start diagnostic; present only after an incomplete deployment |
| `deployment/public/roles.md` | Commit-safe role purposes and public addresses |
| `deployment/public/manifest.json` | Non-secret public deployment identity |
| `deployment/public/deployment-summary.md` | Commit-safe URLs, versions, enabled capabilities, health result, and limitations |

## Initialization dependencies

- `chain-preflight` must validate manifest, genesis, provider features, on-chain roles, and balances before ZKsync OS starts.
- `watchdog-permissions-setup` runs after Prividium migrations and before Watchdog.
- SSO funding and EntryPoint deployment run only inside the `sso` profile.
- Permission jobs and contract deployments are idempotent; existing contract bytecode is verified before a job skips it.
- The institutional demo depends on SSO permission setup and cannot be enabled by itself.
