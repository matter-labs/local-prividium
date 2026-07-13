-- Multi-org demo fixture: the single source of truth for the demo org's rows, applied only when
-- MULTI_ORG_ENABLED is on. Both seed paths run THIS file — native `pnpm dev` (the permissions-api
-- seed-runner) and the dockerized stack (dev/sso-setup/scripts/setup-multi-org-demo.ts) — each
-- substituting `__KEYCLOAK_URL__` for the environment's Keycloak base (host port for native,
-- in-network for docker). Backs the `?org=acme` login flow: open http://localhost:3001/?org=acme and
-- sign in as admin@acme.local / password (the first login bootstraps the org admin).

INSERT INTO organizations (id, name, brand_name, logo_url, primary_color)
VALUES ('acme', 'Acme Corp', 'Acme Corp', '/prividium_logo.svg', '#e8590c')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    brand_name = EXCLUDED.brand_name,
    logo_url = EXCLUDED.logo_url,
    primary_color = EXCLUDED.primary_color,
    deleted_at = NULL;

-- issuer is the realm URL as the browser reaches it (Keycloak stamps `iss` from its frontend URL), so
-- it is always the host port. jwks_uri is where the API fetches certs from, which differs by environment
-- (host port for native, in-network for docker) — hence the `__KEYCLOAK_URL__` placeholder each seed
-- path substitutes. audience must match the `aud` claim the acme realm issues for acme-client.
INSERT INTO oidc_providers (organization_id, issuer, jwks_uri, audience, client_id, display_name)
VALUES (
    'acme',
    'http://localhost:5080/realms/acme',
    '__KEYCLOAK_URL__/realms/acme/protocol/openid-connect/certs',
    'acme-client',
    'acme-client',
    -- Composes the same "Sign in with Keycloak" button label as the zone env default, via the org path.
    'Keycloak'
)
ON CONFLICT (organization_id) DO UPDATE SET
    issuer = EXCLUDED.issuer,
    jwks_uri = EXCLUDED.jwks_uri,
    audience = EXCLUDED.audience,
    client_id = EXCLUDED.client_id,
    display_name = EXCLUDED.display_name;

-- The org-admin system role a pending admin is promoted into on first login (see jwt-validator-service).
-- roles-repository.orgAdminRole(orgId) upserts it lazily on that login, so for `pnpm dev` and the
-- dockerized stack this is idempotent -- but a truncate-then-seed harness (e2e) wipes the table, so the
-- fixture must re-create it to stay self-sufficient. Must match orgAdminRole('acme'): role name Admin,
-- permissions {admin_read, admin_write}, scoped to the org. An explicit id is required because the
-- application default (nanoid) is not available in raw SQL; role name is unique per organization.
INSERT INTO roles (id, role_name, system_permissions, is_system_role, organization_id)
VALUES ('role-acme-admin', 'Admin', '{admin_read,admin_write}', true, 'acme')
ON CONFLICT (organization_id, role_name) DO NOTHING;

INSERT INTO org_pending_admins (id, organization_id, oidc_sub)
VALUES ('pending-acme-admin', 'acme', '10000000-0000-0000-0000-000000000001')
ON CONFLICT (organization_id, oidc_sub) DO NOTHING;
