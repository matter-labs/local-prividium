# Keycloak sandbox configuration

The core realm import contains one administrator with a stable subject. Its email and temporary password are substituted from the SOPS runtime environment during the first import.

Keycloak runs with PostgreSQL persistence, strict HTTPS hostname handling, and forwarded proxy headers. Caddy exposes OIDC realm endpoints but blocks `/admin*` and `/realms/master*` publicly.

Realm imports are skipped when a realm already exists. Apply later configuration changes through `kcadm.sh` or the private admin console rather than expecting a container restart to reimport JSON.

The institutional demo realm is not mounted into the core server. Its profile runs `setup-demo-realm.sh` through Keycloak’s admin API and provisions two SOPS-managed users idempotently.
