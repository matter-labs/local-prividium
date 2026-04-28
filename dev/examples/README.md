# Example Apps

Opt-in Docker Compose profiles. Scripts and contracts always live in the **example app's own repo** — this directory
only contains compose wiring and bind-mount output dirs.

```bash
docker compose --profile <name> up -d
```

---

## Current apps

| Profile              | Port | Description                                   | Instructions                               |
| -------------------- | ---- | --------------------------------------------- | ------------------------------------------ |
| `institutional-demo` | 3500 | Intraday Repo lending demo with ERC-20 tokens | [Demo guide](./institutional-demo/DEMO.md) |

---

## Interface contract

Each example app repo must publish two images:

### Setup image (`<registry>/<app>-setup:<tag>`)

Accepts `deploy` or `seed` as the command argument. Both must be **idempotent**.

**`deploy`** — deploys contracts, writes `NUXT_PUBLIC_*` addresses to `/output/contracts.env` (bind-mounted)

**`seed`** — reads `/output/contracts.env`, seeds Prividium DB directly via postgres:

- Contracts linked to templates by `template_key` (never re-seed shared templates — `erc-20` is owned by core)
- Function permissions for non-template contracts
- OAuth app + demo users + wallet addresses

Required env vars:

| Var                    | local-prividium value                                                |
| ---------------------- | -------------------------------------------------------------------- |
| `RPC_URL`              | `http://zksyncos:3050`                                               |
| `DEPLOYER_PRIVATE_KEY` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| `CHAIN_ID`             | `6565`                                                               |
| `DATABASE_URL`         | `postgres://postgres:postgres@postgres:5432/prividium_api`           |

### App image (`<registry>/<app>:<tag>`)

All contract addresses injected at runtime via `NUXT_PUBLIC_*` env vars — no baked-in addresses. Must accept:

| Var                                        | local-prividium value   |
| ------------------------------------------ | ----------------------- |
| `NUXT_PUBLIC_PRIVIDIUM_CLIENT_ID`          | `<name>-client`         |
| `NUXT_PUBLIC_PRIVIDIUM_AUTH_BASE_URL`      | `http://localhost:3001` |
| `NUXT_PUBLIC_PRIVIDIUM_API_BASE_URL`       | `http://localhost:8000` |
| `NUXT_PUBLIC_PRIVIDIUM_CHAIN_ID`           | `6565`                  |
| `NUXT_PUBLIC_PRIVIDIUM_CHAIN_NAME`         | `Local Prividium`       |
| `NUXT_PUBLIC_PRIVIDIUM_BLOCK_EXPLORER_URL` | `http://localhost:3010` |
| `NUXT_PUBLIC_ZKSYNC_SSO_AUTH_SERVER_URL`   | `http://localhost:3006` |

---

## Conventions

|                    |                                                                         |
| ------------------ | ----------------------------------------------------------------------- |
| Port               | 3500, 3101, 3102…                                                       |
| Profile / dir name | kebab-case                                                              |
| OAuth client ID    | `<name>-client`                                                         |
| OAuth redirect URI | `http://localhost:<port>/auth/callback`                                 |
| OIDC user subs     | N ≥ 6 (1–5 reserved by core stack)                                      |
| SIWE domain        | add `localhost:<port>` to `SIWE_VALID_DOMAINS` in `docker-compose.yaml` |
| Shared templates   | look up by `template_key`, never re-seed                                |
| Selectors          | compute with `toFunctionSelector`, never hardcode hex                   |

---

## Adding a new app

### In the example app repo

1. Create `setup/` with `package.json` (`deploy`/`seed` scripts), `scripts/deploy-contracts.ts`,
   `scripts/setup-permissions.ts`, and `contracts/` (Foundry artifacts)
2. Add `docker/setup.Dockerfile`
3. Publish images via CI

### In local-prividium

1. Create `dev/examples/<name>/` with `.gitkeep` and `.gitignore` (`contracts.env`)

2. Add to `docker-compose-examples.yaml`:

```yaml
<name>-deploy:
  profiles: [<name>]
  image: <registry>/<app>-setup:<tag>
  command: deploy
  volumes:
    - ./dev/examples/<name>:/output
  environment:
    RPC_URL: http://zksyncos:3050
    CHAIN_ID: '6565'
    DEPLOYER_PRIVATE_KEY: '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
    DATABASE_URL: postgres://postgres:postgres@postgres:5432/prividium_api
  depends_on:
    bridge-funds:
      condition: service_completed_successfully

<name>-seed:
  profiles: [<name>]
  image: <registry>/<app>-setup:<tag>
  command: seed
  volumes:
    - ./dev/examples/<name>:/output:ro
  environment:
    DATABASE_URL: postgres://postgres:postgres@postgres:5432/prividium_api
  depends_on:
    <name>-deploy:
      condition: service_completed_successfully
    prividium-api:
      condition: service_healthy
    sso-permissions-setup:
      condition: service_completed_successfully

<name>:
  profiles: [<name>]
  image: <registry>/<app>:<tag>
  platform: linux/amd64
  restart: unless-stopped
  ports:
    - '31XX:<app-port>'
  env_file:
    - path: ./dev/examples/<name>/contracts.env
      required: false
  environment:
    NUXT_PUBLIC_PRIVIDIUM_CLIENT_ID: <name>-client
    NUXT_PUBLIC_PRIVIDIUM_RPC_URL: http://localhost:8000/rpc
    NUXT_PUBLIC_PRIVIDIUM_AUTH_BASE_URL: http://localhost:3001
    NUXT_PUBLIC_PRIVIDIUM_API_BASE_URL: http://localhost:8000
    NUXT_PUBLIC_PRIVIDIUM_CHAIN_ID: 6565
    NUXT_PUBLIC_PRIVIDIUM_CHAIN_NAME: Local Prividium
    NUXT_PUBLIC_PRIVIDIUM_BLOCK_EXPLORER_URL: http://localhost:3010
    NUXT_PUBLIC_ZKSYNC_SSO_AUTH_SERVER_URL: http://localhost:3006
  depends_on:
    <name>-seed:
      condition: service_completed_successfully
```

3. In `docker-compose.yaml`: add `http://localhost:31XX` to `CORS_ORIGIN` and `localhost:31XX` to `SIWE_VALID_DOMAINS`

4. Update the **Current apps** table above.

---

## Testing locally

Build the image in the example app repo:

```bash
docker build -f docker/setup.Dockerfile -t <name>-setup:local .
```

Then run the profile in local-prividium, pointing at the local image via the `*_SETUP_IMAGE` env var (see
`docker-compose-examples.yaml`):

```bash
<NAME>_SETUP_IMAGE=<name>-setup:local docker compose --profile <name> up -d
```

Verify in the admin panel at **http://localhost:3000** (`admin@local.dev` / `password`): contracts, OAuth app, and users
should all appear.
