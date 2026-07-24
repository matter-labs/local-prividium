# `host_preflight`

Read-only compatibility assessment for one dedicated Prividium evaluation VPS.

The role gathers facts, reads service/package/firewall/socket state, probes
passwordless sudo, and performs unauthenticated HTTPS requests to the Docker
Ubuntu repository and Quay registry. It never installs packages, edits files,
changes services or firewall rules, logs into a registry, or invokes the
Prividium application CLI.

Run it through `ansible/playbooks/preflight.yml`, preferably via:

```bash
./cli/prividium host preflight --inventory ansible/inventory/hosts.ini
```
