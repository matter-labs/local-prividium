/**
 * Registers the optional webhook service M2M role and API key.
 *
 * Idempotent and independent of the optional SSO profile.
 */

import { createHash } from 'node:crypto';
import postgres from 'postgres';

const DATABASE_URL = process.env.DATABASE_URL;
const WEBHOOK_API_KEY = process.env.WEBHOOK_PRIVIDIUM_API_KEY;

if (!DATABASE_URL || !WEBHOOK_API_KEY) {
    throw new Error('DATABASE_URL and WEBHOOK_PRIVIDIUM_API_KEY are required');
}

const sql = postgres(DATABASE_URL, { max: 1 });

async function main() {
    try {
        const webhookHash = createHash('sha256').update(WEBHOOK_API_KEY).digest('hex');
        const webhookPrefix = WEBHOOK_API_KEY.slice(0, 12);

        await sql`
          INSERT INTO roles (id, role_name, system_permissions, is_system_role)
          VALUES (
            'role-sandbox-webhook',
            'sandbox_webhook_service',
            ARRAY[
              'check_user_read_access',
              'contract_metadata_read',
              'rpc_read_eth_getBlockByNumber',
              'rpc_read_eth_getLogs',
              'rpc_read_eth_getTransactionByHash',
              'rpc_read_eth_getTransactionReceipt'
            ]::text[],
            false
          )
          ON CONFLICT (organization_id, role_name) DO UPDATE
          SET system_permissions = EXCLUDED.system_permissions
        `;
        await sql`
          INSERT INTO m2m_applications (id, name, description)
          VALUES ('m2m-sandbox-webhook', 'Sandbox Webhook Service', 'Webhook indexer for the Sepolia sandbox')
          ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description
        `;
        await sql`
          INSERT INTO m2m_app_roles (m2m_app_id, role_id)
          SELECT 'm2m-sandbox-webhook', id
          FROM roles
          WHERE role_name = 'sandbox_webhook_service' AND organization_id IS NULL
          ON CONFLICT (m2m_app_id, role_id) DO NOTHING
        `;
        await sql`
          DELETE FROM api_keys
          WHERE id = 'key-sandbox-webhook' AND key_hash <> ${webhookHash}
        `;
        await sql`
          INSERT INTO api_keys (id, name, key_hash, key_prefix, expires_at, m2m_app_id)
          VALUES (
            'key-sandbox-webhook',
            'Sandbox Webhook API Key',
            ${webhookHash},
            ${webhookPrefix},
            now() + interval '1 year',
            'm2m-sandbox-webhook'
          )
          ON CONFLICT (key_hash) DO UPDATE SET expires_at = EXCLUDED.expires_at
        `;
        await sql`
          INSERT INTO api_keys_ip_whitelist (id, ip_address, description, m2m_app_id)
          VALUES
            ('ipw-sandbox-webhook-10', '10.0.0.0/8', 'Private Compose network', 'm2m-sandbox-webhook'),
            ('ipw-sandbox-webhook-172', '172.16.0.0/12', 'Private Compose network', 'm2m-sandbox-webhook'),
            ('ipw-sandbox-webhook-192', '192.168.0.0/16', 'Private Compose network', 'm2m-sandbox-webhook')
          ON CONFLICT (m2m_app_id, ip_address) DO NOTHING
        `;

        console.log('✅ Webhook M2M permissions and API key seeded');
    } finally {
        await sql.end();
    }
}

main().catch((err) => {
    console.error('❌ Webhook permissions seed failed:', err);
    process.exit(1);
});
