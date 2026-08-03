# Evaluation VPS host contract

This document defines the supported host boundary for the Prividium Sepolia
sandbox. It is the acceptance contract for the implemented host automation and
the customer-controlled network preparation that surrounds it.

> [!IMPORTANT]
> The Ansible layer implements read-only preflight, reviewable installation,
> and read-only installation verification. Provider firewall rules and
> external network verification remain customer actions documented in
> [SETUP.md](SETUP.md). Host firewall and SSH changes are deferred.

## Purpose

The sandbox gives a prospective customer engineering team a persistent,
shareable Prividium evaluation without representing a production topology. It
uses one customer-controlled VPS, fake proofs, a testnet verifier, hot keys,
and Ethereum Sepolia.

The host must be dedicated to this evaluation. Do not use a workstation, a
shared application server, or a host containing production workloads.

## Supported host

The automated path supports exactly:

- Ubuntu Server 24.04 LTS;
- Linux `amd64`;
- one VPS with a public IPv4 address;
- a non-root, key-authenticated SSH account with passwordless `sudo`;
- at least 4 vCPU, with 8 vCPU recommended;
- at least 8 GB RAM, with 16 GB recommended;
- a nominal 200 GB SSD plan or better; preflight accepts at least 190 GB of
  usable root-filesystem capacity after normal partition overhead;
- a provider recovery console or equivalent out-of-band access;
- a conventional systemd installation;
- Docker Engine with Docker Compose v2.

Other Linux distributions may work with manual preparation, but
they are outside the initial host-automation support contract.

The customer is responsible for the VPS account, provider billing, public IP,
DNS zone, SSH keys, recovery console, and any provider-level firewall.

## Network contract

The provider firewall must implement this inbound policy:

| Protocol | Port | Source | Purpose |
| --- | ---: | --- | --- |
| TCP | Customer-selected SSH port | Customer-approved CIDRs | Administration |
| TCP | 80 | Any | ACME and HTTP-to-HTTPS handling |
| TCP | 443 | Any | Public HTTPS interfaces |
| UDP | 443 | Any | Caddy HTTP/3 |
| TCP | 3100 | Loopback only | Grafana through an SSH tunnel |

All other inbound traffic is denied. PostgreSQL, Keycloak administration,
Prometheus, Grafana, raw ZKsync OS RPC, and container-internal service ports
must not be reachable from an external network.

A future host-firewall layer should mirror this policy, but it is not part of
the current evaluation installer. It must not be added as an ad-hoc UFW step
because Docker manages its own packet-filtering rules.

The current Compose model publishes UDP 443. Removing HTTP/3 in a future
profile must remove both the Compose publication and the corresponding
firewall allowance.

IPv6 must be either:

- configured with rules equivalent to IPv4; or
- explicitly disabled at the provider and host boundary.

An unfiltered public IPv6 address is not an acceptable substitute for an IPv4
firewall policy.

The evaluation automation does not implement restrictive outbound filtering.
The host requires outbound DNS and time synchronization, HTTPS access to
package and image registries, and HTTPS access to the configured Sepolia RPC
providers.

### Docker firewall boundary

Docker manages packet-filtering rules for published container ports. Host
firewall status alone is therefore not proof of the effective exposure.

Verification must inspect all three layers:

1. provider firewall or security group;
2. host listening sockets;
3. rendered Compose publications and Docker packet-filtering behavior.

An external scan from outside the VPS is part of acceptance.

## DNS contract

The following `A` records point to the VPS:

| Name | Interface |
| --- | --- |
| `app.<domain>` | User application |
| `admin.<domain>` | Administration |
| `api.<domain>` | Protected API and RPC |
| `explorer.<domain>` | Block Explorer |
| `explorer-api.<domain>` | Explorer API |
| `idp.<domain>` | OIDC issuer |

Caddy terminates public TLS. Database, monitoring, and raw chain interfaces do
not receive public DNS records.

## Access and SSH safety

The implemented installer runs as the current operator and does not alter SSH.
For an initially root-only image, the separate root-only
`host operator create` command may install a customer-selected public-key source
for a locked-password operator. It does not change sshd, disable root access, or
activate a firewall, and requires a human to verify a second SSH connection
before continuing. The customer-selected SSH port and allowed source CIDRs
remain explicit inputs for the deferred SSH/firewall milestone.

SSH changes follow two stages:

1. create and verify the intended operator access without removing the current
   access path;
2. harden SSH only after a new connection succeeds and recovery access is
   confirmed.

The automation must never infer a safe source CIDR from an active SSH session.
Allowing SSH from `0.0.0.0/0` or `::/0` requires an explicit customer
acknowledgement.

Before activating a default-deny firewall, the automation must:

- install the intended SSH allow rule;
- schedule a timed, recoverable firewall rollback where supported;
- retain the current SSH connection;
- verify a second connection through the intended rule;
- cancel the rollback only after verification succeeds.

## Filesystem and credentials

The deployment user owns the protected runtime:

| Path | Expected protection |
| --- | --- |
| `/etc/prividium` | Not writable by unprivileged users |
| `/etc/prividium/runtime` | Deployment user, mode `0700` |
| `/etc/prividium/runtime/sandbox.env` | Deployment user, mode `0600` |
| `deployment/secrets/age.key` | Deployment user, mode `0600`, Gitignored |
| Docker registry credential file | Deployment user, mode `0600` |

The Ansible layer must not receive or manage:

- Quay passwords or tokens;
- SOPS age identities;
- Sepolia RPC credentials;
- protocol private keys;
- generated user passwords;
- decrypted runtime configuration.

Quay credentials are supplied separately by Matter Labs DevOps. They are
pull-only, repository-scoped where supported, and time-limited or revoked at
the end of the evaluation. Authentication uses `docker login --password-stdin`
and must not appear in Git, inventory, command arguments, Ansible output, or
agent transcripts.

## Host security baseline

The supported baseline includes:

- current security updates and configured unattended security updates, with
  automatic reboot disabled and a required-reboot warning;
- synchronized system time;
- key-based SSH access;
- default-deny inbound filtering;
- no unexpected public listeners;
- Docker and Compose from an approved installation source;
- bounded Docker container log growth;
- protected deployment directories;
- no swap, kernel, or filesystem tuning without a measured requirement;
- no Kubernetes, K3s, Helm, or Flux installation;
- no production keys, production assets, or mainnet configuration.

SSH policy changes beyond the safe staged flow are not an implicit side effect
of installing the sandbox.

## Ownership boundaries

| Concern | Owner |
| --- | --- |
| VPS, provider firewall, SSH keys, DNS, recovery console | Customer |
| Pull-only Quay credential issuance and revocation | Matter Labs DevOps |
| Host validation, packages, tools, and Docker | Ansible layer |
| Encrypted configuration, identities, funding, deployment | Prividium CLI |
| Docker services and persistent volumes | Compose deployment |
| Evaluation access and eventual cleanup | Customer evaluation team |
| Production architecture and hardening | Joint production engagement |

## Acceptance criteria

A host satisfies this contract when:

- read-only preflight identifies no blocking host issues;
- a configuration plan is reviewed before any mutation;
- applying the same host configuration twice is idempotent;
- the host survives a reboot with SSH and Docker available;
- only the approved public ports are reachable externally;
- Grafana is reachable only through loopback or an SSH tunnel;
- the complete Compose model renders successfully;
- protected files and directories have the required ownership and modes;
- Quay authentication succeeds without exposing the credential;
- `./cli/prividium preflight` passes after initialization and funding;
- the generated deployment summary reports healthy public interfaces.

## Non-goals

This contract does not provide:

- high availability or multi-host orchestration;
- Kubernetes parity with production;
- production proof generation or verifier settings;
- a production key-management or custody design;
- production backup, disaster recovery, SIEM, compliance, or SRE controls;
- automated cloud-provider provisioning;
- a guarantee for hosts that already contain unrelated workloads.

Those topics belong to the production deployment engagement after the
evaluation.
