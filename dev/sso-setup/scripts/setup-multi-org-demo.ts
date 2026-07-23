/**
 * Seeds the multi-org demo organization by applying the shared fixture
 * dev/multi-org/seed-multi-org-demo.sql — the single source of truth for the demo org's rows (the same
 * file native `pnpm dev` seeds via the permissions-api seed-runner). The only environment-dependent value
 * are the public issuer and in-network JWKS base supplied through placeholders.
 *
 * This stands in for the operator UI (design-doc A7) that is not built yet. Run it after the stack is up
 * and migrated, with MULTI_ORG_ENABLED=true on the permissions-api. Then open:
 *   https://app.<sandbox-domain>/?org=acme
 *
 * Idempotent: the fixture uses ON CONFLICT DO NOTHING / DO UPDATE. Bypasses the API — no auth required.
 */

import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import postgres from 'postgres';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Defaults target a host run (alongside `pnpm dev`); inside the compose network DATABASE_URL points at the
// `postgres` host and KEYCLOAK_URL at the in-network Keycloak (the host port won't resolve there).
const DATABASE_URL = process.env.DATABASE_URL;
const KEYCLOAK_JWKS_BASE_URL = process.env.KEYCLOAK_JWKS_BASE_URL;
const KEYCLOAK_ISSUER_BASE_URL = process.env.KEYCLOAK_ISSUER_BASE_URL;
const USER_PANEL_URL = process.env.USER_PANEL_URL;
if (!DATABASE_URL || !KEYCLOAK_JWKS_BASE_URL || !KEYCLOAK_ISSUER_BASE_URL || !USER_PANEL_URL) {
    throw new Error(
        'DATABASE_URL, KEYCLOAK_JWKS_BASE_URL, KEYCLOAK_ISSUER_BASE_URL, and USER_PANEL_URL are required'
    );
}

// The shared fixture. This relative path resolves on the host (dev/sso-setup/scripts → dev/multi-org) and
// in the container (the file is mounted at /multi-org/seed-multi-org-demo.sql; /app/scripts → /multi-org).
const SEED_PATH = path.join(__dirname, '../../multi-org/seed-multi-org-demo.sql');

async function main() {
    const seedSql = (await readFile(SEED_PATH, 'utf-8'))
        .replaceAll('__KEYCLOAK_JWKS_BASE_URL__', KEYCLOAK_JWKS_BASE_URL)
        .replaceAll('__KEYCLOAK_ISSUER_BASE_URL__', KEYCLOAK_ISSUER_BASE_URL);
    const sql = postgres(DATABASE_URL);
    try {
        // No parameters → simple-query protocol, which runs the fixture's multiple statements in one call.
        await sql.unsafe(seedSql);
        console.log('✅ Multi-org demo seeded (org acme, OIDC provider, pending admin).');
        console.log(`   Open ${USER_PANEL_URL}/?org=acme and use a SOPS-managed demo credential.`);
    } finally {
        await sql.end();
    }
}

main().catch((err) => {
    console.error('❌ Multi-org demo seed failed:', err);
    process.exit(1);
});
