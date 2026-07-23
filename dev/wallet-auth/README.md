# Wallet authentication

Deterministic local wallets and seeded private keys were removed from the sandbox.

Human users authenticate with OIDC or their own wallet. Watchdog uses a distinct SOPS-managed key and is registered idempotently by `setup-watchdog-permissions.ts`. Service wallets receive only the configured minimum L2 balance through the Sepolia bridge-funding job. SSO/bundler wallets are funded only when the `sso` profile is enabled.
