# Local Keycloak OIDC Provider

This directory contains the configuration for a local Keycloak instance used for local testing ONLY (DO NOT USE THIS FOR
PRODUCTION).

## Overview

Keycloak is an open-source identity and access management solution that provides OIDC/OAuth 2.0 authentication.

## Access

- **URL**: http://localhost:5080
- **Admin Console**: http://localhost:5080/admin
- **Admin Credentials**:
  - Username: `admin`
  - Password: `admin`

## Realm Configuration

- **Realm Name**: `prividium`
- **Client ID**: `prividium-client`
- **OIDC Endpoints**:
  - Authorization: http://localhost:5080/realms/prividium/protocol/openid-connect/auth
  - Token: http://localhost:5080/realms/prividium/protocol/openid-connect/token
  - JWKS: http://localhost:5080/realms/prividium/protocol/openid-connect/certs
  - UserInfo: http://localhost:5080/realms/prividium/protocol/openid-connect/userinfo

## Test Users

All test users have the password: `password`

**Note**: Each user has a fixed UUID configured in `realm-export.json`. These UUIDs are used as the `sub` claim in JWTs
and are immutable, providing secure user identification.

| Email           | UUID (sub claim)                     | Role        | Purpose                |
| --------------- | ------------------------------------ | ----------- | ---------------------- |
| admin@local.dev | 00000000-0000-0000-0000-000000000001 | admin, user | Administrative testing |
| user@local.dev  | 00000000-0000-0000-0000-000000000002 | user        | Regular user testing   |
| test@local.dev  | 00000000-0000-0000-0000-000000000003 | user        | E2E test automation    |
| user1@local.dev | 00000000-0000-0000-0000-000000000004 | user        | Demo user 1            |
| user2@local.dev | 00000000-0000-0000-0000-000000000005 | user        | Demo user 2            |

The `admin@local.dev` user is automatically granted admin privileges when their UUID is listed in the `OIDC_ADMIN_SUBS`
environment variable.

## Multi-organization demo

A second realm, `acme` (`acme-realm-export.json`), stands in for an organization's own identity provider so the
multi-org login flow can be exercised end-to-end locally. Where production resolves the organization from the `X-Org-Id`
subdomain header, local dev selects it with a `?org=<id>` query parameter on the user panel.

The demo organization, its OIDC provider (the `acme` realm) and a pending org admin are seeded automatically when the
dev stack starts, with `MULTI_ORG_ENABLED` on by default in dev: `pnpm dev` seeds them as part of its database seed
step, and the fully-dockerized `docker compose` stack seeds them from its own setup container. To re-seed manually from
the host (`dev/sso-setup` is a standalone project, not a workspace package, so run it with `-C`, not `--filter`):

```bash
pnpm -C dev/sso-setup setup-multi-org-demo
```

The manual command targets the host Keycloak (`http://localhost:5080`) by default, matching the `pnpm dev` setup, so no
`KEYCLOAK_URL` override is needed.

Then open <http://localhost:3001/?org=acme> and sign in as `admin@acme.local` / `password`. The first sign-in routes to
the `acme` realm, creates the user bound to the Acme organization, and promotes the pre-seeded pending admin to the
org's admin role (`Admin(acme)`, carrying `admin_read`/`admin_write`). Visiting `?org=` (empty) clears the selection
back to the zone provider.

The realm also ships a regular user, `member@acme.local` / `password`, with **no** pending-admin record. Signing in as
that user exercises the other branch of the bootstrap: it is auto-provisioned as a plain organization member
(`organizationId = acme`, `roles = []`) rather than an org admin — the common case for org users.

| Realm  | Client        | User              | Role on first login | sub                                  |
| ------ | ------------- | ----------------- | ------------------- | ------------------------------------ |
| `acme` | `acme-client` | admin@acme.local  | `Admin(acme)`       | 10000000-0000-0000-0000-000000000001 |
| `acme` | `acme-client` | member@acme.local | _(none)_            | 10000000-0000-0000-0000-000000000002 |

### Testing via the SDK popup

A dApp using the `prividium` SDK can target the demo organization by setting `org` when it creates the chain:

```ts
const prividium = createPrividiumChain({
  // ...existing config (clientId, chain, authBaseUrl, prividiumApiBaseUrl, redirectUrl)
  org: 'acme'
});
```

`prividium.authorize(...)` then opens the popup against the `acme` org — same `?org=acme` branding and identity-provider
routing as visiting the user panel directly. The acme demo org is seeded automatically by the dev stack (see above), so
no manual step is needed for SDK testing. The `org` option is for local development/testing only; in production the
organization is determined by the deployment subdomain.

## Starting Keycloak

Keycloak starts automatically with other dependencies:

```bash
docker compose -f docker-compose-deps.yaml up
```

Or start just Keycloak:

```bash
docker compose -f docker-compose-deps.yaml up -d keycloak
```

## Configuration File

The realm configuration is stored in `realm-export.json`. This file is automatically imported when Keycloak starts and
includes:

- Realm settings
- OAuth client configuration
- Test users with **fixed UUIDs** and credentials (ensures deterministic `sub` claims across database resets)
- Role definitions
- Protocol mappers for JWT claims

## Modifying Configuration

To modify the realm configuration:

1. Make changes through the Keycloak Admin UI at http://localhost:5080/admin
2. Export the realm:
   - Go to Realm Settings → Export
   - Enable "Export groups and roles" and "Export clients"
   - Download the JSON file
3. Replace `realm-export.json` with the exported configuration
4. Restart the Keycloak container to test the new configuration

## JWT Token Structure

Keycloak issues JWT tokens with the following claims:

```json
{
  "sub": "00000000-0000-0000-0000-000000000001",
  "iss": "http://localhost:5080/realms/prividium",
  "aud": "prividium-client",
  "email": "admin@local.dev",
  "preferred_username": "admin@local.dev",
  "exp": 1234567890,
  "iat": 1234567890
}
```

**Important**: The `sub` claim contains the user's UUID (configured in `realm-export.json`), not their email address.
This UUID is immutable and is used for secure user identification and admin role assignment in the Prividium™ API.

These tokens are compatible with the existing OIDC JWT validation code in the Prividium™ API.

## Troubleshooting

### Keycloak won't start

- Check if port 5080 is already in use: `lsof -i :5080`
- Check Docker logs: `docker compose -f docker-compose-deps.yaml logs keycloak`

### Login fails

- Verify Keycloak is healthy: `docker compose -f docker-compose-deps.yaml ps keycloak`
- Check the realm was imported correctly by accessing the Admin UI

### JWT validation fails

- Verify the JWKS endpoint is accessible: `curl http://localhost:5080/realms/prividium/protocol/openid-connect/certs`
- Check that environment variables point to the correct Keycloak URLs
- Ensure the issuer and audience in the JWT match the configuration

## Environment Variables

The following environment variables configure apps to use local Keycloak:

**API**:

```bash
# Authentication methods (enable both OIDC and crypto-native)
AUTH_METHODS=oidc,crypto_native

# OIDC JWT validation
OIDC_JWKS_URI=http://localhost:5080/realms/prividium/protocol/openid-connect/certs
OIDC_JWT_AUD=prividium-client
OIDC_JWT_ISSUER=http://localhost:5080/realms/prividium

# Admin user configuration (UUID/sub claims from realm-export.json)
# Works with any OIDC provider - comma-separated list of user "sub" claims
OIDC_ADMIN_SUBS=00000000-0000-0000-0000-000000000001

# Crypto-native (SIWE) authentication configuration
SIWE_CHAIN_ID=6565
SIWE_VALID_DOMAINS=localhost:3000,localhost:3001
```

**Frontend Apps**:

```bash
# Authentication methods available in the UI
VITE_AUTH_METHODS=crypto_native,oidc

# OIDC Configuration (Local Keycloak)
VITE_OIDC_AUTHORITY=http://localhost:5080/realms/prividium
VITE_OIDC_CLIENT_ID=prividium-client
VITE_OIDC_BUTTON_TEXT=Sign in with Keycloak
```
