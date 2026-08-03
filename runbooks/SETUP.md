# Deploy the Prividium Sepolia sandbox

This guide takes a prospective engineering team from a clean checkout to a
healthy Prividium evaluation environment.

The sandbox is a single-host, fake-proof deployment. It is not a production
network, custody model, or supported public testnet.

## Before starting

Use a dedicated, initially blank Ubuntu Server 24.04 LTS / amd64 VPS with at
least 4 vCPU, 8 GB RAM, and 200 GB SSD. The recommended compute capacity is
8 vCPU and 16 GB RAM. The
[evaluation VPS host contract](HOST_CONTRACT.md) defines the supported host,
network, access, and credential boundary.

Run the workflow as the VPS's normal passwordless-sudo operator, not as
`root`.

### Root-only VPS images

If the provider initially exposes only `root`, create a dedicated operator
through the constrained bootstrap command. Run these commands once from the
root session:

```bash
apt-get update
apt-get install --yes git python3
git clone \
  https://github.com/matter-labs/local-prividium.git \
  /root/prividium-operator-bootstrap
cd /root/prividium-operator-bootstrap
./cli/prividium host operator create
```

Interactive use detects `/root/.ssh/authorized_keys`, displays the exact
managed boundary, and requires typing `CREATE`. If the root login uses another
access mechanism, supply one public key explicitly with `--public-key` or
`--public-key-file`. Never supply a private key. Agent-driven execution must
make both choices explicit:

```bash
./cli/prividium host operator create \
  --copy-current-authorized-keys \
  --yes
```

Copying the current file preserves any key restrictions exactly. If the
provider installed a root-specific forced command or other restriction that
prevents a normal operator login, rerun with the plain public key through
`--public-key-file` instead. The second-login check below is authoritative.

The command creates or verifies the `prividium` user, locks password login,
installs `sudo` if necessary, grants passwordless sudo, and installs the
selected authorized keys. It does not alter sshd, root access, firewall rules,
or Docker groups.

Keep the root session open and verify a new login from another terminal:

```bash
ssh 'prividium@<vps-address>'
sudo -n true
```

Continue only after both commands succeed. Perform the rest of this guide from
the new `prividium` session; do not reuse a checkout under `/root`.

> [!IMPORTANT]
> Host automation installs packages, tools, Docker, and protected directories.
> It does not alter SSH or activate firewall rules. The provider firewall
> remains a customer action; host firewall automation is deferred until it has
> a safe rollback workflow.

On a blank VPS, install the bootstrap prerequisites and clone over HTTPS:

```bash
sudo apt-get update
sudo apt-get install --yes git python3-apt python3-venv
git clone https://github.com/matter-labs/local-prividium.git prividium-evaluation
cd prividium-evaluation
```

The repository is public, so the HTTPS clone needs no GitHub credential. Do
not use its `git@github.com:...` SSH URL on a blank VPS: SSH clone URLs require
a GitHub SSH identity even for public repositories. If Matter Labs provides a
private fork later, use an approved read-only token over HTTPS or a forwarded
SSH agent. Never copy a workstation private key to the VPS or put a token in a
clone URL.

Then bootstrap the pinned Ansible runtime and Gitignored local inventory:

```bash
./cli/prividium host bootstrap
```

Bootstrap requires Python 3.12 or newer with `venv` and `python3-apt` support.
It detects the current user, creates a local one-host inventory, and installs
only `ansible-core` into the Gitignored `ansible/.venv`. It does not prompt for
future firewall inputs or change system packages.

Then assess the host:

```bash
./cli/prividium host preflight
```

The command is read-only and always enables Ansible check mode. A passing
result confirms host compatibility.

Review the host installation plan:

```bash
./cli/prividium host install --check
```

Then apply it:

```bash
./cli/prividium host install
```

The installer reruns the read-only host preflight immediately before any
mutation and records a root-owned management marker so an immediate second
apply is idempotent. It:

- applies safe Ubuntu package upgrades;
- installs the baseline packages, `age`, pinned SOPS, and pinned Foundry;
- installs Docker Engine, Buildx, and Compose from Docker's official Ubuntu
  repository;
- configures bounded Docker logs and enables Docker;
- enables Chrony and unattended security updates without automatic reboot;
- adds the operator to the root-equivalent Docker group; and
- creates the protected `/etc/prividium/runtime` directory.

Reconnect the SSH session so Docker group membership takes effect, then run:

```bash
./cli/prividium host verify
```

If installation reports `reboot_required=true`, reboot through the normal
provider workflow, reconnect, and rerun verification.

Before application deployment, use the VPS provider console to attach a
default-deny inbound firewall or security group with these rules:

| Protocol | Port | Source |
| --- | ---: | --- |
| TCP | Customer-selected SSH port | Customer-approved administrative CIDRs |
| TCP | 80 | Any |
| TCP | 443 | Any |
| UDP | 443 | Any |

Keep the current SSH session and provider recovery console open while changing
the SSH rule. Verify a second SSH connection through the restricted rule
before removing any broader temporary access. Leave outbound access enabled
for DNS, time synchronization, Ubuntu and Docker repositories, image
registries, and the configured Sepolia RPC providers.

In the authoritative DNS zone, create these `A` records pointing to the VPS
public IPv4 address:

| Name | Interface |
| --- | --- |
| `app.<domain>` | User application |
| `admin.<domain>` | Administration |
| `api.<domain>` | Protected API and RPC |
| `explorer.<domain>` | Block Explorer |
| `explorer-api.<domain>` | Explorer API |
| `idp.<domain>` | OIDC issuer |

Use a short TTL such as 300 seconds during setup. Do not create `AAAA` records
unless public IPv6 and equivalent firewall rules are configured end-to-end.
When using a DNS proxy such as Cloudflare, begin with DNS-only records. All six
names must resolve publicly before `./cli/prividium deploy`.

The installer supplies `age`, `age-keygen`, SOPS, Foundry `cast`, `jq`,
OpenSSL, Docker, and Compose. Prepare:

- a private Sepolia RPC with historical calls/logs, receipts, and blob-fee
  support;
- a separate public Sepolia RPC that permits browser CORS;
- registry access to the pinned Prividium images;
- Sepolia ETH for the generated funding wallet.

Authenticate to the private registry with the pull-only credential supplied by
Matter Labs DevOps. Keep the token out of shell history:

```bash
read -r -s QUAY_TOKEN
printf '%s' "$QUAY_TOKEN" |
  docker login quay.io --username '<issued-username>' --password-stdin
unset QUAY_TOKEN
```

## 1. Initialize

Run:

```bash
./cli/prividium init
```

The command asks for the sandbox domain, ACME email, private Sepolia RPC, and
public browser Sepolia RPC. The private RPC input is hidden.

Outputs:

| File | Protection |
| --- | --- |
| `deployment/secrets/sandbox.enc.env` | SOPS encrypted |
| `deployment/secrets/age.key` | Gitignored, mode `0600` |
| `deployment/public/roles.md` | Public, commit-safe |

Initialization also creates one administrator and two evaluation users:

| Email | Default password | Role |
| --- | --- | --- |
| `admin@local.dev` | `password` | Administrator; password change required |
| `user1@local.dev` | `password` | User |
| `user2@local.dev` | `password` | User |

Environment overrides remain hidden in CLI output. Back up the encrypted
configuration and age identity using the evaluation team’s approved secret
storage.

Review `deployment/public/roles.md`. The sandbox funding wallet is the only
address the customer funds directly.

## 2. Fund protocol identities

Inspect the two groups:

```bash
./cli/prividium fund --list
```

Fund all six required identities:

```bash
./cli/prividium fund
```

The command reads current Sepolia balances and prints the exact additional
amount needed by the funding wallet. After it has enough ETH, the same command
shows the six shortfalls and asks for one `[y/N]` confirmation.

It transfers only current shortfalls, waits for each receipt, and verifies final
balances. A completed rerun is a no-op.

To reconcile one group:

```bash
./cli/prividium fund deployment
./cli/prividium fund operators
```

Funding transactions are irreversible testnet writes. If interrupted, wait for
the funding-wallet nonce to settle before rerunning.

## 3. Run preflight

Run:

```bash
./cli/prividium preflight
```

Preflight is read-only and non-interactive. It checks:

- the encrypted configuration, identities, and role inventory;
- Linux/amd64, required tools, Docker, and Compose;
- private and browser Sepolia RPC behavior;
- Chainlist collision and chain-ID range;
- private image access and public DNS visibility;
- the exact six role targets and funding-wallet pending nonce;
- the rendered default and deferred-profile Compose models.

`PREFLIGHT PASSED WITH WARNINGS` is possible while DNS is still propagating.
Preflight creates no persistent runtime or report and submits no transactions.

## 4. Prepare

The host installer created the protected runtime. Run:

```bash
./cli/prividium prepare
```

Preparation:

1. decrypts the configuration atomically to
   `/etc/prividium/runtime/sandbox.env` with mode `0600`;
2. builds the locked zk-deployer and Protocol source;
3. simulates ecosystem and chain creation;
4. pulls every pinned default remote image;
5. builds every default local image;
6. verifies focused pre-broadcast readiness.

Review these protected outputs:

```text
/etc/prividium/runtime/chain/out/manifest.json
/etc/prividium/runtime/chain/out/preparation.json
```

They must be readable by the deployment user without sudo. Preparation writes
local runtime state and Docker artifacts but submits no Sepolia transaction.
Unresolved DNS is a warning here because it does not affect protocol creation.

## 5. Broadcast

Run:

```bash
./cli/prividium broadcast
```

The command reruns focused readiness and displays:

- Ethereum Sepolia and the L2 chain ID;
- sandbox domain;
- ecosystem deployer address;
- preparation timestamp;
- prepared-manifest digest.

It then requires the L2 chain ID. This authorization creates irreversible
Sepolia contracts.

For non-interactive execution, use the exact chain-bound token:

```bash
CONFIRM_BROADCAST=BROADCAST_SEPOLIA_<L2_CHAIN_ID> ./cli/prividium broadcast
```

Success writes:

```text
deployment/public/manifest.json
```

Review its contract addresses, source locks, fake-proof declaration, genesis,
operator addresses, and transaction hashes.

If broadcast fails after it begins, stop. Do not rerun it, regenerate
identities, or remove `/etc/prividium/runtime/chain`. Preserve the terminal
output and inspect the recorded transactions and on-chain state first.

## 6. Deploy

All six public DNS records must resolve before deployment.

Run:

```bash
./cli/prividium deploy
```

The command:

1. verifies public DNS;
2. validates the runtime and public protocol manifest;
3. renders browser configuration;
4. validates the complete Compose model;
5. starts the prebuilt default stack without rebuilding;
6. waits up to ten minutes for services and public interfaces.

The initial default contains no service-wallet bridge. Once ZKsync OS is
running, the funded settlement operators can produce normal Sepolia
transactions as batches progress.

Success writes:

```text
deployment/public/deployment-summary.md
```

If startup fails, inspect the complete state and logs:

```bash
docker compose \
  -f compose/compose.yaml \
  --env-file /etc/prividium/runtime/sandbox.env \
  --profile "*" \
  ps --all --no-trunc

docker compose \
  -f compose/compose.yaml \
  --env-file /etc/prividium/runtime/sandbox.env \
  logs --tail 200
```

Fix the prerequisite and rerun `./cli/prividium deploy`. The default services and
database setup are designed to converge on the existing sandbox state.

Continue with [evaluation and BD handoff](EVALUATION.md).

## Deferred profiles

SSO/EntryPoint/bundler, webhook, and institutional-demo Compose implementations
remain in the repository for later CLI profiles. They are disabled by default,
not covered by this setup track, and have no public activation command in this
iteration.
