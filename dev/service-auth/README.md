# Service authentication

The sandbox no longer commits a webhook API key or SQL seed. Webhook runtime is disabled by default and belongs to the `webhook` Compose profile.

`dev/sso-setup/scripts/setup-webhook-permissions.ts` hashes the SOPS-managed `WEBHOOK_PRIVIDIUM_API_KEY`, creates the minimum read-only M2M role, and restricts it to private Compose address ranges. Rotating the key requires updating SOPS, decrypting the runtime environment, and rerunning the idempotent profile with `tools/sandbox enable webhook`.
