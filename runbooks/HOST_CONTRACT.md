# Prividium VPS prerequisites

This document defines the handoff between the customer-managed VPS and the
repository-managed Prividium deployment.

The repository does not provision, repair, harden, upgrade, or audit the host.
It also does not manage user accounts, SSH, sudo, firewalls, DNS, storage, or
provider resources. The customer engineer prepares those controls using their
normal platform and security standards.

## Qualified target

- Dedicated Linux `amd64` VPS; Ubuntu Server 24.04 LTS is the qualified target.
- Expected capacity: 8 vCPU, 16 GB RAM, and a nominal 200 GB nonrotational SSD.
- Public IPv4 address and control of the intended DNS zone.
- A deployment user that can run Docker Engine and Docker Compose v2.
- A real `/etc/prividium/runtime` directory owned by that user with mode `0700`.

Capacity is documented for planning and is not measured or enforced by the
CLI. The provider is the authoritative source for virtual CPU, storage class,
and disk-media claims.

## Required tools

The deployment user must have these commands available:

```text
git
rustc 1.90.0
cargo
docker
docker compose v2
age
age-keygen
sops
cast
```

The CLI is built from the checkout. Its first invocation requires access to
the Rust crate registry. Docker must already be running and usable by the
deployment user without an agent changing account or daemon policy.

## Required connectivity

Outbound DNS and HTTPS must reach:

- GitHub and the Rust crate registry;
- Docker Hub and Quay;
- Chainlist; and
- the configured private and browser Sepolia RPC endpoints.

The application expects public TCP 80/443 and UDP 443 plus the customer's
chosen administrative SSH access. These services must remain private:

- PostgreSQL;
- Prometheus;
- Keycloak administration;
- Grafana, which binds to `127.0.0.1:3100`; and
- raw ZKsync OS RPC.

The customer decides how to implement and verify this policy across provider
and host controls. The CLI neither changes nor asserts firewall state.

## Required DNS

Six public IPv4 `A` records must resolve to the VPS before deployment:

```text
app.<domain>
admin.<domain>
api.<domain>
explorer.<domain>
explorer-api.<domain>
idp.<domain>
```

Avoid public `AAAA` records unless IPv6 routing and security policy are
configured end to end.

## Repository checks

`prividiumcli preflight` checks only what the application needs at deploy
time: Linux amd64 compatibility, required commands, runtime-directory safety,
Docker and Compose access, configuration, RPC behavior, chain ID, locked image
pulls, roles, funding, and DNS resolution.

It does not inspect or enforce:

- CPU, memory, disk size, or storage media;
- exact Ubuntu packages or services;
- account, SSH, sudo, or password policy;
- OS upgrades, time synchronization, or unattended updates;
- provider or host firewall implementation;
- Docker daemon logging or package source policy; or
- recovery-console, backup, monitoring, or retention policy.

If an application prerequisite is missing, the CLI reports it and asks the
engineer to satisfy this document before rerunning `preflight`. It does not
attempt host remediation.
