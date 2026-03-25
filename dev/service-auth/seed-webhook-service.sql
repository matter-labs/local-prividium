-- Seed script for local service-auth database entities
-- Creates the webhook service account used by docker-compose-deps.yaml

INSERT INTO services (id, name, public_key, description)
VALUES (
    'svc_local_webhook_0001',
    'Local Webhook Service',
    decode('f39Fd6e51aad88F6F4ce6aB8827279cffFb92266', 'hex'),
    'Seeded local development service account for zksync-webhook-service'
)
ON CONFLICT (public_key) DO UPDATE
SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    updated_at = now();
