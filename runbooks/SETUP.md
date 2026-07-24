# Deploy the Prividium Sepolia sandbox

This guide takes a prospective engineering team from a clean checkout to a
healthy Prividium evaluation environment.

The sandbox is a single-host, fake-proof deployment. It is not a production
network, custody model, or supported public testnet.

## Before starting

Use a dedicated Ubuntu Server 24.04 LTS / amd64 VPS with Docker Engine,
Docker Compose v2, at least 4 vCPU and 8 GB RAM, and recommended capacity of
8 vCPU, 16 GB RAM, and 200 GB SSD. The
[evaluation VPS host contract](HOST_CONTRACT.md) defines the supported host,
network, access, and credential boundary.

> [!IMPORTANT]
> Host automation currently provides a read-only compatibility preflight only.
> It does not install packages, Docker, or firewall rules. Prepare the VPS
> manually after the preflight passes.

From a trusted controller, install the pinned Ansible tools and copy the
Gitignored host-intent examples:

```bash
python3 -m venv ansible/.venv
ansible/.venv/bin/python -m pip install -r ansible/requirements.txt
cp ansible/inventory/example.ini ansible/inventory/hosts.ini
cp \
  ansible/inventory/group_vars/all.example.yml \
  ansible/inventory/group_vars/all.yml
```

Edit both copies, verify the VPS SSH host-key fingerprint through the provider,
then assess the host:

```bash
PATH="${PWD}/ansible/.venv/bin:${PATH}" \
  ./cli/prividium host preflight \
    --inventory ansible/inventory/hosts.ini
```

The command is read-only and always enables Ansible check mode. A passing
result confirms host compatibility; its final gap report identifies items that
still need manual installation or configuration.

Restrict the customer-selected SSH port to approved administrative source
ranges. Allow inbound TCP 80 and 443 and UDP 443. Point these required records
at the host:

| Name | Interface |
| --- | --- |
| `app.<domain>` | User application |
| `admin.<domain>` | Administration |
| `api.<domain>` | Protected API and RPC |
| `explorer.<domain>` | Block Explorer |
| `explorer-api.<domain>` | Explorer API |
| `idp.<domain>` | OIDC issuer |

Prepare:

- a private Sepolia RPC with historical calls/logs, receipts, and blob-fee
  support;
- a separate public Sepolia RPC that permits browser CORS;
- registry access to the pinned Prividium images;
- `age`, `age-keygen`, `sops`, `cast`, `jq`, `openssl`, and `curl`;
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

The protected runtime must be owned by the deployment user with mode `0700`:

```bash
sudo install -d -m 0700 -o "$USER" /etc/prividium/runtime
```

Then run:

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
