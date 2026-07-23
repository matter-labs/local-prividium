# Sandbox example profiles

Example applications are opt-in Compose profiles and are not started by the core deployment.
Their complete Compose lifecycle is isolated in `docker-compose-demos.yaml`.

## Institutional demo

The `institutional-demo` profile requires the optional `sso` profile and:

- Uses `https://demo.${SANDBOX_DOMAIN}`.
- Creates a separate `acme` Keycloak realm through the admin API.
- Creates two users whose emails and passwords come from the SOPS environment.
- Uses a dedicated deployer key and an idempotent Sepolia-to-L2 funding job.
- Persists deployed contract addresses in the `institutional_demo_runtime` volume.

Start it after the core stack is healthy:

```bash
tools/sandbox enable demo
```

Do not add example users or deployer keys to the core realm or default services.
See the [optional capability setup](../../docs/SETUP.md#8-enable-optional-capabilities)
for DNS, encrypted configuration, and funding prerequisites.
