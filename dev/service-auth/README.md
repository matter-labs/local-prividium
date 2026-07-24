# Service authentication

The sandbox no longer commits a webhook API key or SQL seed. Webhook runtime is disabled by default and belongs to the `webhook` Compose profile.

`dev/sso-setup/scripts/setup-webhook-permissions.ts` hashes the SOPS-managed
`WEBHOOK_PRIVIDIUM_API_KEY`, creates the minimum read-only M2M role, and
restricts it to private Compose address ranges. The implementation is retained
for a future public profile command; the focused sandbox CLI does not activate
or rotate the webhook profile yet.
