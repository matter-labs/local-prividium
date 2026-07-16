-- Seed script for local service-auth database entities
-- Creates the webhook service account used by docker-compose-deps.yaml

INSERT INTO services (id, name, public_key, description)
VALUES (
    'svc_local_webhook_001',
    'Local Webhook Service',
    decode('f39Fd6e51aad88F6F4ce6aB8827279cffFb92266', 'hex'),
    'Seeded local development service account for zksync-webhook-service'
)
ON CONFLICT (public_key) DO UPDATE
SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    updated_at = now();

-- ---------------------------------------------------------------------------
-- M2M app for the webhook service (/m2m-app-queries path).
--
-- Raw API key (dev only, committed intentionally):
--   priv_sk_DEV000000000000000000000000000000000000000000000000000000WEBHOOK
-- ---------------------------------------------------------------------------

-- 1. Role granting the two new system permissions
INSERT INTO roles (id, role_name, system_permissions, is_system_role)
VALUES (
    'role-local-webhook-service',
    'local_webhook_service_role',
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
SET system_permissions = EXCLUDED.system_permissions;

-- 2. M2M application
INSERT INTO m2m_applications (id, name, description)
VALUES (
    'm2m_local_webhook_001',
    'Local Webhook Service',
    'Seeded local development M2M app for zksync-webhook-service'
)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description;

-- 3. Bind role to the M2M app. Resolve the role id by name rather than hardcoding it: on a database
-- upgraded in place, a role that predated the surrogate-id migration carries a backfilled nanoid,
-- not the id above, so a hardcoded reference would break the foreign key.
INSERT INTO m2m_app_roles (m2m_app_id, role_id)
SELECT 'm2m_local_webhook_001', r.id
FROM roles r
WHERE r.role_name = 'local_webhook_service_role' AND r.organization_id IS NULL
ON CONFLICT (m2m_app_id, role_id) DO NOTHING;

-- 4. API key (hash stored, raw key in header comment above)
INSERT INTO api_keys (
    id, name, key_hash, key_prefix, expires_at, m2m_app_id
)
VALUES (
    'key_local_webhook_001',
    'Local Webhook Dev Key',
    encode(sha256('priv_sk_DEV000000000000000000000000000000000000000000000000000000WEBHOOK'::bytea), 'hex'),
    'priv_sk_DEV0',
    now() + interval '100 years',
    'm2m_local_webhook_001'
)
ON CONFLICT (key_hash) DO UPDATE
SET expires_at = EXCLUDED.expires_at;

-- 5. IP whitelist (loopback + all RFC1918 private LAN ranges)
INSERT INTO api_keys_ip_whitelist (id, ip_address, description, m2m_app_id)
VALUES
    ('ipw_local_webhook_001', '127.0.0.1', 'localhost', 'm2m_local_webhook_001'),
    ('ipw_local_webhook_002', '10.0.0.0/8', 'RFC1918 private (10.0.0.0/8)', 'm2m_local_webhook_001'),
    ('ipw_local_webhook_003', '172.16.0.0/12', 'RFC1918 private (172.16.0.0/12)', 'm2m_local_webhook_001'),
    ('ipw_local_webhook_004', '192.168.0.0/16', 'RFC1918 private (192.168.0.0/16)', 'm2m_local_webhook_001')
ON CONFLICT (m2m_app_id, ip_address) DO NOTHING;
