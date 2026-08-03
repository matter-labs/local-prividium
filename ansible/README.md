# Prividium evaluation host automation

This directory contains the minimal Ansible layer for one customer-controlled
Prividium evaluation VPS. It implements read-only compatibility preflight,
reviewable host installation, and read-only installation verification.

The authoritative requirements are in the
[evaluation VPS host contract](../runbooks/HOST_CONTRACT.md).

> [!IMPORTANT]
> `install.yml` provisions the package, tool, Docker, service, and protected
> directory baseline. It does not alter SSH or activate firewall rules.
> Firewall activation remains deferred until it has a timed rollback and
> second-session verification workflow.

## Automation boundary

Ansible owns host readiness only:

- host facts and prerequisites;
- Ubuntu packages, security updates, and time synchronization;
- pinned host deployment tools;
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

The implemented public commands are:

```text
./cli/prividium host bootstrap
./cli/prividium host preflight
./cli/prividium host install --check
./cli/prividium host install
./cli/prividium host verify
```

`host bootstrap` creates `ansible/.venv` from the pinned runtime requirements,
detects the current user, and writes Gitignored `hosts.ini` and
`group_vars/all.yml` files for a one-host local connection. It does not prompt
for deferred firewall inputs, install system packages, or change host
configuration.

`host preflight` automatically uses that environment and inventory. The
wrapper displays the exact configured host, connection, user, and declared SSH
port for remote inventories before invoking Ansible in check mode. An explicit
`--inventory` remains available for advanced remote-controller use. SSH
host-key checking remains enabled for SSH inventories.

`host install --check` renders the constrained installation plan in Ansible
check and diff modes. `host install` displays the same target and managed
boundary, then requires an interactive `INSTALL` confirmation. Agent-driven
non-interactive apply additionally requires `--yes`.

`host verify` checks only the Ansible-managed installation surface and always
runs in check mode. It reports reboot status and keeps provider-firewall
configuration and Quay login as explicit follow-up actions.

## Run the host workflow

From the repository checkout on the VPS with Python 3.12 or newer,
`python3-apt`, and `venv` support:

```bash
./cli/prividium host bootstrap
./cli/prividium host preflight
./cli/prividium host install --check
./cli/prividium host install
# Reconnect so Docker group membership applies.
./cli/prividium host verify
```

Bootstrap is non-interactive and derives only the current operator. SSH keys,
administrative CIDRs, provider recovery, and IPv6 firewall intent remain
customer-controlled network concerns. The generated inventory and variables
are Gitignored; never put Quay credentials or application secrets in them.

## Repository shape

```text
ansible/
├── README.md
├── ansible.cfg
├── requirements.txt
├── requirements-dev.txt
├── inventory/
│   ├── example.ini
│   └── group_vars/
│       └── all.example.yml
├── playbooks/
│   ├── preflight.yml
│   ├── install.yml
│   └── verify.yml
└── roles/
    ├── host_preflight/             # Implemented, read-only
    ├── host_packages/              # Ubuntu packages and safe upgrades
    ├── host_security/              # Time and unattended-upgrade policy
    ├── prividium_tools/            # Pinned SOPS and Foundry
    ├── container_runtime/          # Docker Engine and Compose
    ├── prividium_config/           # Protected directories
    └── verification/               # Read-only installation assertions
```

The existing `observability`, `backups`, and `prividium_services` role
directories remain reserved. Firewall activation, `upgrade.yml`, and
`uninstall.yml` are deferred.

## Playbooks

### `preflight.yml`

Read-only and safe to run before the customer approves changes. It gathers and
asserts:

- Ubuntu release and `amd64` architecture;
- CPU, memory, disk, systemd, and time synchronization;
- current operator and passwordless sudo;
- current IPv6 and firewall state as evidence;
- Docker state and conflicting container runtimes;
- existing listeners and conflicting services;
- required outbound connectivity;
- dedicated-host assumptions.

Preflight may report warnings, but unsupported OS, inadequate resources,
conflicting runtime packages, public listeners, or an already-used application
host are blockers.

Docker, baseline packages, and active time synchronization are reported as
installable gaps rather than host-compatibility failures. No registry
credential is used: the Quay check is an unauthenticated request to `/v2/`,
where HTTP `401` is an expected proof of reachability.

### `install.yml`

Mutating and limited to one host with `serial: 1` and
`any_errors_fatal: true`. The role order is:

1. `host_packages`
2. `host_security`
3. `prividium_tools`
4. `container_runtime`
5. `prividium_config`

The playbook uses idempotent modules, handlers, explicit file modes, pinned
third-party checksums, safe package upgrades, and an explicit check-mode path.
It reruns `host_preflight` immediately before mutation and records a
root-owned marker so a second apply can safely accept the managed runtime
directory.

SSH hardening is a separate, explicitly confirmed stage after replacement
access has been verified. It is not a default side effect of Docker
installation.

### `verify.yml`

Read-only and expected to report no changes. It verifies:

- baseline Ubuntu and Docker packages;
- pinned SOPS and Foundry versions;
- Docker daemon and Compose availability;
- bounded Docker log configuration and service enablement;
- operator Docker group membership;
- runtime directory ownership and modes;
- Chrony service state; and
- reboot status as explicit follow-up evidence.

Provider-firewall acceptance and external exposure remain customer workflow
responsibilities. Host firewall automation is deferred. Application health
remains the responsibility of `./cli/prividium preflight` and
`./cli/prividium deploy`.

## Role boundaries

### `host_preflight`

Facts, assertions, supported-host checks, and dedicated-host detection. It
never changes the host.

### `host_security`

Unattended security-update policy, automatic-reboot prevention, and Chrony
time synchronization. It enables Ubuntu's apt metadata and unattended-upgrade
timers. It does not install, activate, or configure a firewall.

### `host_packages`

Safe Ubuntu upgrades and the evaluation package baseline.

### `prividium_tools`

Checksum-pinned SOPS and Foundry binaries plus Ubuntu-managed `age`. It does
not create SOPS identities or application secrets.

### `container_runtime`

Approved Docker installation, Compose plugin, merged daemon log rotation,
service enablement, and explicit operator membership in Docker's
root-equivalent group. It does not configure registry credentials or firewall
rules.

### `prividium_config`

Protected `/etc/prividium` directories. It does not clone arbitrary branches,
decrypt configuration, initialize identities, or run the Prividium CLI.

### `verification`

Assertions and evidence only. It does not remediate failures.

## Inputs

The implemented variable surface is deliberately small:

| Variable | Purpose |
| --- | --- |
| `prividium_operator_user` | Existing deployment operator |
| `prividium_runtime_dir` | Fixed by default to `/etc/prividium/runtime` |

Inventory and group variables contain no secrets. Network-security inputs will
be introduced only with the deferred, rollback-protected firewall milestone.

## Safety requirements

- `preflight` and `verify` are read-only.
- `host install --check` uses Ansible check and diff modes.
- Sensitive tasks set `no_log: true` and `diff: false`, although the initial
  host layer should not handle application secrets at all.
- Every apply shows and confirms the exact target.
- SSH and firewall configuration is not an implicit installation side effect.
- Static Compose exposure and external reachability are validated outside the
  host installer.
- The playbooks never submit Sepolia transactions or invoke protocol
  broadcast.

## Test and release gate

The host-installation milestone is not releasable until it passes:

- YAML parsing and `ansible-playbook --syntax-check`;
- `ansible-lint`;
- check mode, first apply, second idempotent apply, and verification on a clean
  Ubuntu 24.04 LTS VPS;
- existing shell and Compose validation;
- secret scanning.

Reboot verification remains a gate for this milestone. External probing and
SSH/firewall rollback testing remain gates for the later network-security
milestone.

The disposable-VPS test record must identify the image, provider, IPv4/IPv6
state, Ansible version, Docker version, and exact Git revision.

## Implementation order

1. **Complete:** pin the Ansible runtime separately from CI lint tooling.
2. **Complete:** add example inventory and non-secret variables.
3. **Complete:** implement guided controller bootstrap, read-only host
   preflight, and constrained wrappers.
4. **Complete:** implement packages, pinned tools, protected directories, and
   Docker setup.
5. Implement firewall changes with rollback.
6. **Complete:** implement read-only installation verification.
7. **Complete:** add constrained check, apply, and verify wrapper commands.
8. Exercise the complete flow on a disposable VPS.

No production deployment behavior should be imported into this evaluation
layer unless it directly supports the host contract.
