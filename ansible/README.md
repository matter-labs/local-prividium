# Prividium evaluation host automation

This directory contains the minimal Ansible layer for one customer-controlled
Prividium evaluation VPS. The implemented surface is currently limited to a
read-only host preflight.

The authoritative requirements are in the
[evaluation VPS host contract](../runbooks/HOST_CONTRACT.md).

> [!IMPORTANT]
> `preflight.yml` gathers evidence and enforces the supported host boundary,
> but does not remediate failures. Host installation, SSH/firewall changes,
> Docker installation, and post-install verification remain deferred.

## Automation boundary

Ansible owns host readiness only:

- host facts and prerequisites;
- safe SSH and firewall configuration;
- Docker Engine and Compose;
- protected directories;
- host-level verification.

The customer-facing CLI continues to own:

- SOPS and age identities;
- RPC and application secrets;
- protocol identities and funding;
- protocol preparation and broadcast;
- Compose deployment and endpoint verification.

Quay credentials are never Ansible variables. The operator authenticates with
the registry separately using a pull-only credential and
`docker login --password-stdin`.

## Execution model

The initial implementation targets exactly one inventory host and runs serially.
The Ansible controller may be:

- the customer engineer or agent workstation targeting the VPS over SSH; or
- the repository checkout on the VPS using an explicit local connection.

The Prividium CLI itself runs on the VPS because it owns the local Docker
Engine and `/etc/prividium/runtime`.

The implemented public command is:

```text
./cli/prividium host preflight --inventory ansible/inventory/hosts.ini
```

The wrapper displays the exact configured host, address, SSH user, and SSH
port before invoking Ansible in check mode. It rejects the documentation
inventory and inventories whose `prividium` group does not contain exactly one
host. SSH host-key checking remains enabled.

## Run the read-only preflight

From a trusted controller with Python 3.12 or newer:

```bash
python3 -m venv ansible/.venv
ansible/.venv/bin/python -m pip install -r ansible/requirements.txt
cp ansible/inventory/example.ini ansible/inventory/hosts.ini
cp \
  ansible/inventory/group_vars/all.example.yml \
  ansible/inventory/group_vars/all.yml
```

Edit both copied files. Confirm the VPS host key through the provider console
or another trusted channel before connecting, then run:

```bash
PATH="${PWD}/ansible/.venv/bin:${PATH}" \
  ./cli/prividium host preflight \
    --inventory ansible/inventory/hosts.ini
```

The copied inventory and variables are Gitignored. They contain only public
host intent; never put Quay credentials or application secrets in them.

## Planned repository shape

```text
ansible/
├── README.md
├── ansible.cfg
├── requirements.txt
├── inventory/
│   ├── example.ini
│   └── group_vars/
│       └── all.example.yml
├── playbooks/
│   └── preflight.yml
└── roles/
    ├── host_preflight/             # Implemented, read-only
    ├── host_security/
    ├── container_runtime/
    ├── prividium_config/
    └── verification/
```

The existing `observability`, `backups`, and `prividium_services` role
directories remain reserved and are outside the first implementation.
`upgrade.yml` and `uninstall.yml` are also deferred.

## Playbooks

### `preflight.yml`

Read-only and safe to run before the customer approves changes. It gathers and
asserts:

- Ubuntu release and `amd64` architecture;
- CPU, memory, disk, systemd, and time synchronization;
- sudo, SSH, IPv4, IPv6, and provider-recovery inputs;
- presence of the declared operator key in the connected user's
  `authorized_keys`;
- current firewall backend and effective rules;
- Docker state and conflicting container runtimes;
- existing listeners and conflicting services;
- required outbound connectivity;
- dedicated-host assumptions.

Preflight may report warnings, but unsupported OS, inadequate resources,
missing recovery access, unsafe SSH inputs, conflicting public listeners, or
an already-used application host are blockers.

Docker, UFW, baseline packages, and active time synchronization are reported as
installable gaps rather than host-compatibility failures. No registry
credential is used: the Quay check is an unauthenticated request to `/v2/`,
where HTTP `401` is an expected proof of reachability.

### `install.yml`

Mutating and limited to one host with `serial: 1` and
`any_errors_fatal: true`. The role order is:

1. `host_preflight`
2. `host_security`
3. `container_runtime`
4. `prividium_config`

The playbook must use idempotent modules, handlers, and explicit file modes.
Shell or command tasks require a documented reason, correct `changed_when`,
check-mode behavior, and a deterministic guard.

SSH hardening is a separate, explicitly confirmed stage after replacement
access has been verified. It is not a default side effect of Docker
installation.

### `verify.yml`

Read-only and expected to report no changes. It verifies:

- approved listeners and firewall rules for IPv4 and IPv6;
- Docker daemon and Compose availability;
- no unexpected Docker port publications;
- runtime directory ownership and modes;
- unattended security updates and system time;
- reboot persistence;
- the static Compose model;
- external reachability when an external probe target is provided.

Application health remains the responsibility of
`./cli/prividium preflight` and `./cli/prividium deploy`.

## Role boundaries

### `host_preflight`

Facts, assertions, supported-host checks, and dedicated-host detection. It
never changes the host.

### `host_security`

Security updates, time synchronization, staged SSH safety, host firewall,
IPv6 policy, and bounded system logging. Firewall tasks preserve the active
session and support a timed rollback.

### `container_runtime`

Approved Docker installation, Compose plugin, daemon log rotation, service
enablement, and Docker-aware exposure checks. It does not configure registry
credentials.

### `prividium_config`

Deployment user and protected `/etc/prividium` directories. It does not clone
arbitrary branches, decrypt configuration, initialize identities, or run the
Prividium CLI.

### `verification`

Assertions and evidence only. It does not remediate failures.

## Inputs

The initial variable surface should remain small:

| Variable | Purpose |
| --- | --- |
| `prividium_operator_user` | Existing or intended deployment operator |
| `prividium_operator_public_key` | Public SSH key, never a private key |
| `prividium_ssh_port` | Customer-selected SSH port |
| `prividium_ssh_allowed_cidrs` | Explicit administrative source ranges |
| `prividium_ipv6_policy` | `configured` or `disabled` |
| `prividium_provider_recovery_confirmed` | Confirms recovery-console access |
| `prividium_enable_http3` | Must match UDP 443 Compose publication |
| `prividium_runtime_dir` | Fixed by default to `/etc/prividium/runtime` |

Inventory and group variables contain no secrets. Allowing unrestricted SSH
requires a separate acknowledgement variable rather than an empty-list
default.

## Safety requirements

- `preflight` and `verify` are read-only.
- `plan` uses Ansible check and diff modes.
- Sensitive tasks set `no_log: true` and `diff: false`, although the initial
  host layer should not handle application secrets at all.
- Every apply shows and confirms the exact target.
- Firewall rules permit the intended SSH connection before default deny.
- A second SSH connection is verified before disabling old access.
- Firewall rollback is scheduled before rules are activated and cancelled
  only after verification.
- IPv4 and IPv6 are evaluated separately.
- Docker exposure is verified independently of host firewall status.
- The playbooks never submit Sepolia transactions or invoke protocol
  broadcast.

## Test and release gate

The read-only preflight milestone is not releasable until it passes:

- YAML parsing and `ansible-playbook --syntax-check`;
- `ansible-lint`;
- check mode on a clean Ubuntu 24.04 LTS VPS;
- existing shell and Compose validation;
- secret scanning.

Apply idempotence, reboot verification, external probing, and SSH rollback
testing remain gates for the later mutating host-automation milestone.

The disposable-VPS test record must identify the image, provider, IPv4/IPv6
state, Ansible version, Docker version, and exact Git revision.

## Implementation order

1. **Complete:** pin Ansible and the controller lint tooling.
2. **Complete:** add example inventory and non-secret variables.
3. **Complete:** implement the read-only host preflight and constrained wrapper.
4. Implement directory and Docker setup.
5. Implement firewall changes with rollback.
6. Implement read-only verification.
7. Add constrained `plan`, `apply`, and `verify` wrapper commands.
8. Exercise the complete flow on a disposable VPS.

No production deployment behavior should be imported into this evaluation
layer unless it directly supports the host contract.
