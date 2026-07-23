# Institutional sandbox demo

This optional profile deploys the Intraday Repo demo against the Sepolia-backed Prividium sandbox.

Before enabling it:

1. Add `demo.${SANDBOX_DOMAIN}` to DNS.
2. Add `auth.${SANDBOX_DOMAIN}` and `auth-api.${SANDBOX_DOMAIN}` to DNS.
3. Set `BUNDLER_ENABLED=true` in the encrypted environment and decrypt it again.
4. Confirm the encrypted environment contains two demo credentials and a distinct `INSTITUTIONAL_DEMO_DEPLOYER_PRIVATE_KEY`.
5. Ensure the bridge sponsor has enough Sepolia ETH.

Start the profile:

```bash
tools/sandbox enable demo
```

The identity, funding, deployment, organization seed, and application stages are idempotent. Access the app at `https://demo.${SANDBOX_DOMAIN}` and the organization login at `https://app.${SANDBOX_DOMAIN}/?org=acme`.
