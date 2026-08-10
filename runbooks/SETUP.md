# Deploy the Prividium Sepolia sandbox

This is the authoritative sequential guide for taking a prospective customer
from a blank VPS to a verified Prividium evaluation. The repository skill
normally drives these commands; this document is the manual fallback and
explains every human checkpoint.

The sandbox is a single-host, fake-proof Sepolia deployment. It is not a
production network, custody model, or supported public testnet.

## 1. Prepare access and clone

Provision a dedicated Ubuntu Server 24.04 LTS amd64 VPS with:

- at least 4 vCPU, 8 GB RAM, and a nominal 200 GB SSD;
- preferably 8 vCPU and 16 GB RAM;
- a public IPv4 address and provider recovery console; and
- either a non-root passwordless-sudo SSH operator or initial root access.

Install and authenticate Codex CLI or Claude Code. Clone the public repository
over HTTPS; a GitHub SSH identity is not needed:

```bash
git clone https://github.com/matter-labs/local-prividium.git
cd local-prividium
```

Do not use `git@github.com:matter-labs/local-prividium.git` on a blank VPS.
That URL requires a GitHub SSH identity even for a public repository.

From the repository, start the selected agent and invoke:

```text
Codex:       $deploy-prividium
Claude Code: /deploy-prividium
```

The rest of this guide documents what the skill runs and where it pauses.

### Root-only provider images

If only root can log in, clone temporarily under `/root` and create the
constrained operator:

```bash
apt-get update
apt-get install --yes git python3
git clone \
  https://github.com/matter-labs/local-prividium.git \
  /root/prividium-operator-bootstrap
cd /root/prividium-operator-bootstrap
./cli/prividium host operator create
```

Interactive use detects `/root/.ssh/authorized_keys`, shows the managed
boundary, and requires `CREATE`. Agent-driven use must select the key source
explicitly:

```bash
./cli/prividium host operator create \
  --copy-current-authorized-keys \
  --yes
```

Alternatively use `--public-key-file` with one plain OpenSSH public key. Never
supply a private key. The command creates or verifies the locked-password
`prividium` user, grants validated passwordless sudo, and installs the selected
authorized keys. It does not modify sshd, root access, firewall rules, or
Docker.

Human checkpoint — keep the root session open and verify a second login:

```bash
ssh 'prividium@<vps-address>'
sudo -n true
```

Continue only when both succeed. Clone again over HTTPS from the `prividium`
session, install/authenticate the selected agent for that operator if the
original installation was root-local, start it from the operator-owned
checkout, and reinvoke the skill. Do not reuse a checkout under `/root`.

## 2. Prepare the host

Run the read-only local guard:

```bash
./cli/prividium host bootstrap
```

It confirms Ubuntu 24.04 amd64, systemd, a non-root operator, passwordless
sudo, and bootstrap commands. It installs nothing and creates no inventory.

Assess the dedicated-host boundary:

```bash
./cli/prividium host preflight
```

Preflight blocks below 4 vCPU, approximately 8 GiB nominal RAM, or 190 GB
usable root capacity. It also checks the OS, architecture, sudo, conflicting
container/Kubernetes packages and services, reserved listeners, existing
runtime/containers, and outbound access to Docker and Quay. Eight vCPU and 16
GiB RAM remain recommendations only.

Review the exact managed boundary:

```bash
./cli/prividium host install --check
```

Apply after review:

```bash
./cli/prividium host install
```

Non-interactive agent execution uses `--yes` only after the human has reviewed
the plan. Installation:

- applies safe Ubuntu package upgrades;
- installs the baseline packages, Chrony, age, unattended upgrades, pinned
  SOPS, and pinned Foundry;
- installs Docker Engine, containerd, Buildx, and Compose from Docker's
  official Ubuntu repository;
- merges bounded Docker `json-file` logs: three files of 10 MB per container;
- enables Docker, Chrony, unattended upgrades, and apt maintenance timers;
- disables unattended automatic reboot;
- adds the operator to the root-equivalent Docker group; and
- creates root-owned `/etc/prividium`, the `host-contract-v1` marker, and
  operator-owned mode-`0700` `/etc/prividium/runtime`.

It does not alter SSH, host/provider firewalls, DNS, Quay credentials, RPC
credentials, protocol keys, or application services.

Human checkpoint — if installation reports `reboot_required=true`, reboot
through the normal provider workflow. Otherwise close and reopen SSH so the
Docker group becomes active. Then verify:

```bash
./cli/prividium host verify
```

Do not continue until verification passes.

## 3. Create the human input file

Create a protected copy of the four-field template:

```bash
install -m 0600 deployment/input.env.example deployment/input.env
```

Edit it directly on the VPS:

```dotenv
SANDBOX_DOMAIN=sandbox.example.com
ACME_EMAIL=platform@example.com
SEPOLIA_RPC_URL="https://private-archive-sepolia-rpc.example.com"
SEPOLIA_BROWSER_RPC_URL="https://public-browser-sepolia-rpc.example.com"
```

`SEPOLIA_RPC_URL` is the private archive-capable Sepolia endpoint. It must
support historical calls/logs, receipts, and blob-fee behavior. Keep its
credential out of chat and terminal logs. `SEPOLIA_BROWSER_RPC_URL` must be a
distinct public HTTPS endpoint that permits browser CORS.

The parser allows blank lines, comments, and fully quoted or unquoted values.
It rejects missing, duplicate, unknown, malformed, shell-expansion, or escaped
content, as well as symlinks and modes other than `0600`.

Validate without printing values:

```bash
tools/parse-input-env deployment/input.env >/dev/null
```

`deployment/sandbox.env.example` is not this input. It documents the larger
generated runtime environment and supports static Compose validation.

## 4. Initialize encrypted configuration

Run:

```bash
./cli/prividium init
```

Use `--env-file <path>` only when an approved alternate input path is needed.
Initialization generates a chain ID, funding wallet, protocol/service
identities, database secrets, and strong random passwords for the fixed
evaluation logins. Passwords are not printed.

Verify these outputs:

| Path | Protection | Purpose |
| --- | --- | --- |
| `deployment/secrets/sandbox.enc.env` | SOPS-encrypted and Gitignored | Configuration, credentials, and private keys |
| `deployment/secrets/age.key` | Mode `0600` and Gitignored | Local decryption identity |
| `deployment/public/roles.md` | Public and commit-safe | Public identities and funding wallet |

After all three exist and are nonempty, remove the plaintext human input:

```bash
rm -f -- deployment/input.env
```

If `--env-file` selected another approved path, remove that path instead.

If initialization fails, retain the input file for correction. Back up the
encrypted configuration and age identity together using approved secret
storage; the encrypted file cannot be recovered without the identity.

Review `deployment/public/roles.md`. The sandbox funding wallet is the only
address the customer funds directly.

## 5. Configure external infrastructure

Host automation deliberately does not modify networking outside the VPS.

In the provider firewall/security group, apply default-deny inbound rules:

| Protocol | Port | Source |
| --- | ---: | --- |
| TCP | Customer-selected SSH port | Approved administrative CIDRs only |
| TCP | 80 | Internet |
| TCP | 443 | Internet |
| UDP | 443 | Internet |

Keep the existing SSH connection and provider recovery console open. Verify a
second SSH connection through the restricted rule before removing any broader
temporary access. Leave outbound DNS, time, HTTPS repositories/registries, and
the configured Sepolia RPC endpoints reachable.

Create these public IPv4 `A` records pointing to the VPS:

```text
app.<domain>
admin.<domain>
api.<domain>
explorer.<domain>
explorer-api.<domain>
idp.<domain>
```

Use a short TTL during setup. Do not create `AAAA` records unless IPv6 routing
and equivalent firewall rules are configured end to end. Start with DNS-only
records when using a proxying DNS provider. All six names must resolve before
deployment.

The customer should perform an external port scan after deployment. Host
firewall state alone is not proof of exposure because Docker manages its own
packet-filtering rules.

## 6. Authenticate to Quay

Matter Labs DevOps supplies a pull-only credential. Run this directly in a
private SSH terminal, not an agent conversation:

```bash
read -r -p 'Quay username: ' QUAY_USERNAME
read -r -s -p 'Quay token: ' QUAY_TOKEN
printf '\n'
printf '%s' "$QUAY_TOKEN" |
  docker login quay.io --username "$QUAY_USERNAME" --password-stdin
unset QUAY_USERNAME QUAY_TOKEN
```

Do not store the Quay token in `deployment/input.env`, Git, command arguments,
or an agent transcript.

## 7. Fund protocol identities

Inspect the two groups:

```bash
./cli/prividium fund --list
```

Reconcile current balances:

```bash
./cli/prividium fund
```

If the generated funding wallet is short, the command prints the exact
additional Sepolia ETH needed. Send only that amount to that one wallet, wait
for confirmation, and rerun the command.

Human checkpoint — once the funding wallet has enough ETH, the command shows
the six current shortfalls. Review them and approve the interactive `[y/N]`
prompt. It transfers only the shortfalls, waits for receipts, and verifies
final balances. A completed rerun is a no-op.

## 8. Validate and prepare

Run the read-only application preflight:

```bash
./cli/prividium preflight
```

It checks the encrypted configuration, RPC capabilities, private image access,
DNS visibility, funding, public roles, and all Compose profiles. Correct the
reported prerequisite rather than weakening a check.

Prepare without submitting transactions:

```bash
./cli/prividium prepare
```

Preparation decrypts the protected runtime, builds locked sources, simulates
the ecosystem/L2 deployment, pulls or builds the default images, and records
preparation provenance under `/etc/prividium/runtime/chain`.

## 9. Authorize protocol broadcast

Run:

```bash
./cli/prividium broadcast
```

The command displays Ethereum Sepolia, the generated L2 chain ID, domain,
deployer, preparation time, and prepared-manifest digest. Interactive use
requires typing the L2 chain ID. Agent-driven use must stop, show the same
details, obtain explicit human approval, and only then provide the displayed
`CONFIRM_BROADCAST=BROADCAST_SEPOLIA_<L2_CHAIN_ID>` value.

This creates irreversible Sepolia contracts. If the command fails after
broadcast begins, do not rerun it, regenerate identities, or delete
`/etc/prividium/runtime/chain`. Preserve the terminal output and inspect the
recorded and on-chain transaction state first.

Success writes `deployment/public/manifest.json`.

## 10. Deploy and verify services

After all six DNS names resolve:

```bash
./cli/prividium deploy
```

The command validates DNS, runtime, protocol manifest, and Compose; renders
browser configuration; starts the prebuilt services; and waits for health.
Success requires 14 long-running services and a successful one-shot
`chain-preflight` job, then writes
`deployment/public/deployment-summary.md`.

Review the public interfaces:

```text
https://app.<domain>
https://admin.<domain>
https://api.<domain>
https://explorer.<domain>
https://explorer-api.<domain>
https://idp.<domain>/realms/prividium
```

Grafana remains on `127.0.0.1:3100` and is accessed through an SSH tunnel.
Database, Prometheus, Keycloak administration, and raw node RPC are not public.

## 11. Reveal evaluation credentials

Only when an authorized human requests them, run outside the agent transcript:

```bash
./cli/prividium credentials show
```

The command requires an interactive terminal, refuses redirected output, and
requires typing `SHOW`. It decrypts and displays only the evaluation URLs and
three generated logins. Close or clear the terminal afterwards.

## Evidence and cleanup

Retain only these commit-safe records in the evaluation report:

```text
deployment/public/roles.md
deployment/public/manifest.json
deployment/public/deployment-summary.md
```

Never share the age identity, SOPS file, decrypted runtime, private RPC URL,
passwords, registry token, or private keys.

There is no automated uninstall command. At the end of the evaluation, revoke
Quay and RPC credentials, remove DNS, and destroy the dedicated VPS and its
volumes unless retention is explicitly approved. Sepolia contracts and
transactions cannot be removed; never reuse their evaluation keys.
