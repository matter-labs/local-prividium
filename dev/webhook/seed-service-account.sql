-- Seed script for service account database entries
-- Local development only
-- Private key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
-- Address: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

INSERT INTO services (id, name, public_key, description)
VALUES
    (
        'svc_seed_local_000001',
        'Local Seed Service',
        decode('f39Fd6e51aad88F6F4ce6aB8827279cffFb92266', 'hex'),
        'Seeded service account for local development'
    )
ON CONFLICT (public_key) DO NOTHING;
