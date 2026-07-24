# Sandbox example profiles

Example applications are opt-in Compose profiles and are not started by the core deployment.
Their complete Compose lifecycle is isolated in `compose/demos.yaml`.

## Institutional demo

The `institutional-demo` profile requires the optional `sso` profile and:

- Uses `https://demo.${SANDBOX_DOMAIN}`.
- Creates a separate `acme` Keycloak realm through the admin API.
- Creates two users whose emails and passwords come from the SOPS environment.
- Uses a dedicated deployer key and an idempotent Sepolia-to-L2 funding job.
- Persists deployed contract addresses in the `institutional_demo_runtime` volume.

The implementation is retained for a future public profile command, but the
focused sandbox CLI does not activate optional profiles yet.

Do not add example users or deployer keys to the core realm or default services.
See [Components](../../runbooks/COMPONENTS.md) for the boundary between the focused
default stack and deferred profiles.
