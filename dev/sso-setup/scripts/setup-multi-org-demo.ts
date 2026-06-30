/**
 * Seeds a sample organization so the multi-org login flow can be exercised locally:
 *   1. An organization ("Acme Corp") with branding.
 *   2. Its OIDC provider, pointing at the `acme` Keycloak realm (dev/keycloak/acme-realm-export.json).
 *   3. A pending-admin record for the realm's admin user, who becomes the org's admin on first sign-in.
 *
 * This stands in for the operator UI (design-doc A7) that is not built yet. Run it after the stack is
 * up and migrated, with MULTI_ORG_ENABLED=true on the permissions-api. Then open:
 *   http://localhost:3001/?org=acme   →  log in as admin@acme.local / password
 *
 * Idempotent: uses ON CONFLICT DO NOTHING / DO UPDATE. Bypasses the API — no auth required.
 */

import postgres from 'postgres';

// Defaults target a host run (alongside `pnpm dev`); inside the compose network set DATABASE_URL to the
// `postgres` hostname.
const DATABASE_URL = process.env.DATABASE_URL ?? 'postgres://postgres:postgres@localhost:5432/prividium_api';
// Where the permissions-api fetches the realm's JWKS from. Native `pnpm dev` reaches Keycloak on the
// host port (default); a fully-dockerized stack should set this to http://keycloak:8080.
const KEYCLOAK_URL = process.env.KEYCLOAK_URL ?? 'http://localhost:5080';

const ORG_ID = 'acme';
const ORG_NAME = 'Acme Corp';
// Matches the realm, client and admin user in dev/keycloak/acme-realm-export.json.
const REALM = 'acme';
const CLIENT_ID = 'acme-client';
const PENDING_ADMIN_SUB = '10000000-0000-0000-0000-000000000001';
// The issuer is the realm URL as the browser reaches it (Keycloak stamps `iss` from its frontend URL),
// so it is always the host port — independent of where the API fetches JWKS from.
const ISSUER = `http://localhost:5080/realms/${REALM}`;

async function main() {
    const sql = postgres(DATABASE_URL);
    try {
        await sql`
      INSERT INTO organizations (id, name, brand_name, logo_url, primary_color)
      VALUES (${ORG_ID}, ${ORG_NAME}, ${ORG_NAME}, '/prividium_logo.svg', '#e8590c')
      ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        brand_name = EXCLUDED.brand_name,
        logo_url = EXCLUDED.logo_url,
        primary_color = EXCLUDED.primary_color,
        deleted_at = NULL
    `;
        console.log(`✅ Organization: ${ORG_NAME} (id=${ORG_ID})`);

        // `audience` must match the `aud` claim the acme realm actually issues for acme-client (confirmed
        // against the live token during multi-org e2e). A realm edit that changes the audience mapping must
        // update this value too, or token validation for org users will fail.
        await sql`
      INSERT INTO oidc_providers (organization_id, issuer, jwks_uri, audience, client_id, display_name)
      VALUES (
        ${ORG_ID},
        ${ISSUER},
        ${`${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/certs`},
        ${CLIENT_ID},
        ${CLIENT_ID},
        ${`${ORG_NAME} SSO`}
      )
      ON CONFLICT (organization_id) DO UPDATE SET
        issuer = EXCLUDED.issuer,
        jwks_uri = EXCLUDED.jwks_uri,
        audience = EXCLUDED.audience,
        client_id = EXCLUDED.client_id,
        display_name = EXCLUDED.display_name
    `;
        console.log(`✅ OIDC provider: ${ISSUER}`);

        // `id` has an application-level (not DB) default, so a raw insert must supply it.
        await sql`
      INSERT INTO org_pending_admins (id, organization_id, oidc_sub)
      VALUES (${`pending-${ORG_ID}-admin`}, ${ORG_ID}, ${PENDING_ADMIN_SUB})
      ON CONFLICT (organization_id, oidc_sub) DO NOTHING
    `;
        console.log(`✅ Pending admin sub: ${PENDING_ADMIN_SUB} (admin@acme.local)`);

        console.log(`\n✅ Multi-org demo seeded. Open http://localhost:3001/?org=${ORG_ID} and sign in as`);
        console.log('   admin@acme.local / password — the first login bootstraps the org admin.');
    } finally {
        await sql.end();
    }
}

main().catch((err) => {
    console.error('❌ Multi-org demo seed failed:', err);
    process.exit(1);
});
