/**
 * Registers the Watchdog wallet as a crypto-native Prividium user.
 *
 * Idempotent and independent of the optional SSO and webhook profiles.
 */

import postgres from 'postgres';
import { privateKeyToAccount } from 'viem/accounts';

const DATABASE_URL = process.env.DATABASE_URL;
const WATCHDOG_PRIVATE_KEY = process.env.WATCHDOG_PRIVATE_KEY as `0x${string}` | undefined;

if (!DATABASE_URL || !WATCHDOG_PRIVATE_KEY) {
    throw new Error('DATABASE_URL and WATCHDOG_PRIVATE_KEY are required');
}

const sql = postgres(DATABASE_URL, { max: 1 });

async function main() {
    try {
        const watchdog = privateKeyToAccount(WATCHDOG_PRIVATE_KEY);

        await sql`
          INSERT INTO roles (id, role_name, system_permissions, is_system_role)
          VALUES ('role-sandbox-user', 'user', '{}', false)
          ON CONFLICT (organization_id, role_name) DO NOTHING
        `;
        await sql`
          INSERT INTO users (id, display_name, source)
          VALUES ('watchdog-sandbox', 'Sandbox Watchdog', 'crypto_native')
          ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name
        `;
        await sql`
          INSERT INTO user_wallets (wallet_address, user_id)
          VALUES (${Buffer.from(watchdog.address.slice(2), 'hex')}, 'watchdog-sandbox')
          ON CONFLICT (wallet_address) WHERE deleted_at IS NULL DO NOTHING
        `;
        await sql`
          INSERT INTO user_roles (user_id, role_id)
          SELECT 'watchdog-sandbox', id
          FROM roles
          WHERE role_name = 'user' AND organization_id IS NULL
          ON CONFLICT (user_id, role_id) DO NOTHING
        `;

        console.log(`✅ Watchdog wallet registered: ${watchdog.address}`);
    } finally {
        await sql.end();
    }
}

main().catch((err) => {
    console.error('❌ Watchdog permissions seed failed:', err);
    process.exit(1);
});
