# Wallet authentication

Deterministic local wallets and seeded private keys were removed from the sandbox.

Human users authenticate with OIDC or their own wallet. Optional service wallets
receive only the configured minimum L2 balance when their Compose profile is
enabled. SSO/bundler wallets are funded only by the `sso` profile.
