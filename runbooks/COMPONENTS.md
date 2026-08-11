# Deployment components

`compose/compose.yaml` is the only Compose entrypoint. The focused CLI passes
that file explicitly.

## Default modules

| Module | Responsibility |
| --- | --- |
| `compose/compose.yaml` | Prividium API, user/admin applications, and Caddy |
| `compose/platform.yaml` | PostgreSQL, Keycloak, chain preparation/preflight, and ZKsync OS |
| `compose/explorer.yaml` | Explorer API, application, worker, and data fetcher |
| `compose/permissioning.yaml` | Retained webhook and SSO permission jobs; unsupported for the happy path |
| `compose/monitoring.yaml` | Prometheus, Grafana, and operator-balance monitoring |
| `compose/optional.yaml` | Retained SSO/bundler and webhook runtime; unsupported for the happy path |
| `compose/demos.yaml` | Retained institutional demo; unsupported for the happy path |

The default deployment has 14 long-running services:

```text
zksyncos
postgres
keycloak
prividium-api
user-panel
admin-panel
caddy
block-explorer-api
block-explorer-app
block-explorer-worker
block-explorer-data-fetcher
prometheus
grafana
operator-balance-exporter
```

`chain-preflight` is a one-shot prerequisite and must exit successfully before
ZKsync OS starts.

Inspect the resolved default model:

```bash
docker compose \
  -f compose/compose.yaml \
  --env-file /etc/prividium/runtime/sandbox.env \
  config
```

## Unsupported retained profiles

| Profile | Default | Intended capability |
| --- | :---: | --- |
| `chain-bootstrap` | Off | CLI-invoked protocol preparation and broadcast |
| `sso` | Off | SSO, EntryPoint deployment, bundler, and related funding |
| `webhook` | Off | Webhook M2M permission seed and service |
| `institutional-demo` | Off | Demo realm, contracts, seed, and application |

The CLI controls `chain-bootstrap` internally for preparation, broadcast, and
the acceptance canary. The other profiles are retained for future work but are
explicitly unsupported: they have no public activation commands and must not
be included in the customer happy path.

## Networks and persistence

- `edge` connects Caddy to browser-facing applications.
- `app` connects application services, ZKsync OS, Explorer, and monitoring.
- `data` connects PostgreSQL to services that need database access.

Persistent named volumes hold PostgreSQL, Keycloak state through PostgreSQL,
ZKsync OS data, Prometheus, Grafana, and deferred-profile data. Protected chain
configuration remains under `/etc/prividium/runtime/chain`.

## Startup invariants

- The public manifest and protected chain configuration must describe the same
  L2 chain, Stage-0 Validium (`no_da`), and registered Prividium filterer.
- `chain-preflight` validates on-chain contracts, genesis, RPC capabilities,
  settlement roles, and operator balances before ZKsync OS starts.
- The three settlement operators remain distinct and funded.
- Remote images and Dockerfile bases are digest-pinned.
- Optional services must remain absent from the default profile.
- Only Caddy and loopback-bound Grafana publish host ports.
