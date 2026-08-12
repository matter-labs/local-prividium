---
name: deploy-prividium
description: Deploy and verify the single-VPS Prividium Sepolia evaluation stack from a prepared repository checkout. Use when a customer asks to deploy, resume, identify the next human checkpoint, or verify that the Prividium sandbox is ready.
---

# Deploy Prividium

Drive the evaluation through `prividiumcli`. For every command the agent
executes, add `--output json`, preserve stdout, and branch only on `outcome`,
`stage`, `next_action`, and `error.code`. Progress and prompts use stderr. The
human-only `credentials show` command is the sole exception.

Exit `2` is an expected human-action or manual-review checkpoint. Exit `1` is
failed validation and exit `64` is agent misuse.

Run this workflow only after the user explicitly invokes the skill. If loaded
implicitly, explain the native invocation and make no changes:

- Codex: `$deploy-prividium`
- Claude Code: `/deploy-prividium`

## Safety boundary

- Support the single-host, fake-proof Sepolia evaluation, never production.
- Treat the host as customer-managed. Never install packages, create users,
  modify sshd or sudo, change Docker daemon policy, configure firewalls or DNS,
  or create provider resources.
- Never print or copy into chat the private RPC value, Quay token, age identity,
  encrypted or decrypted environment, passwords, or private keys.
- Stop before funding transfers and protocol broadcast for explicit human
  authorization.
- Stop before the acceptance canary for separate explicit human authorization.
- If broadcast may have started and then failed, preserve all output and
  `/etc/prividium/runtime/chain`; do not rerun or regenerate identities.
- Never publish, push, or sign images.

## Resume safely

Start every invocation with read-only inspection. Locate the repository root,
confirm `git status --short`, and verify Rust 1.90.0 and Cargo are available.
Then run:

```bash
prividiumcli --output json status
```

Inspect existence and metadata only for:

```text
deployment/input.env
deployment/secrets/age.key
deployment/secrets/sandbox.enc.env
deployment/public/roles.md
/etc/prividium/runtime/reports/funding-ready.json
/etc/prividium/runtime/chain/out/preparation.json
deployment/public/manifest.json
deployment/public/deployment-summary.md
deployment/public/happy-path.json
```

Do not display file contents except the four public Markdown or JSON artifacts.
Continue from the first incomplete stage. Do not recreate completed secret or
protocol state.

## Present human checkpoints

For every pause, state:

1. Why the person must act.
2. The exact action or command.
3. How success is verified.
4. What is sensitive and must stay out of chat.
5. That the user should reinvoke this skill to resume.

Do not claim progress past a checkpoint until its verification passes.

## 1. Confirm the host handoff

Read `runbooks/HOST_CONTRACT.md`. The host engineer is expected to supply the
documented Linux amd64 environment, tools, Docker access, protected runtime
directory, connectivity, and DNS control before deployment begins.

The expected 8-vCPU, 16-GB, and nominal 200-GB nonrotational SSD capacity is
documented but not inspected or enforced. Do not invent capacity, SSH, sudo,
package, service, firewall, or OS-hardening checks.

If the source-installed CLI, required tool, Docker access, or runtime directory
is unavailable, stop and report the specific prerequisite from
`runbooks/HOST_CONTRACT.md`. The engineer owns remediation; do not perform it.

## 2. Collect the human inputs

If encrypted configuration does not exist, create only the empty protected
input copy:

```bash
install -m 0600 deployment/input.env.example deployment/input.env
```

Ask the user to edit it directly on the VPS. It requires:

```text
SANDBOX_DOMAIN
ACME_EMAIL
SEPOLIA_RPC_URL
SEPOLIA_BROWSER_RPC_URL
```

It accepts `L2_CHAIN_ID` in `1073741824..2147483647`. Recommend omission so
`init` generates a high-range ID unless the customer has an approved
allocation.

Explain that `SEPOLIA_RPC_URL` is private and archive-capable and must not be
pasted into chat. The browser RPC must be a different public HTTPS endpoint
with CORS support.

When editing is complete, run:

```bash
prividiumcli --output json init
```

Verify that the encrypted environment and age identity are nonempty regular
files with safe modes, `deployment/public/roles.md` exists, and the default
plaintext input is gone. If initialization fails, retain the input for
correction. Never reveal generated passwords.

## 3. Complete external infrastructure

The customer must configure:

- network policy that permits the documented application and administrative
  traffic without publishing internal services; and
- six public IPv4 `A` records pointing to the VPS: `app`, `admin`, `api`,
  `explorer`, `explorer-api`, and `idp` under the sandbox domain.

Do not configure or audit provider or host controls. DNS is required for
deployment. Do not recommend public `AAAA` records unless equivalent IPv6
routing and filtering are in place.

## 4. Authenticate to Quay

Pause for the pull-only credential supplied by Matter Labs DevOps. The human
must run `docker login quay.io` with `--password-stdin` directly in a private
SSH terminal and report only whether it succeeded. Never ask for the token or
put it in `deployment/input.env`.

Application preflight checks access to the digest-pinned images. Preparation
builds only the local `chain-bootstrap` and `operator-balance-exporter` helper
images. Never publish, push, or sign an image.

## 5. Fund generated identities

Run:

```bash
prividiumcli --output json fund --list
prividiumcli --output json fund
```

If the funding wallet is short, pause while the human sends only the reported
Sepolia ETH to the displayed public address. Once funded, require the human to
run `prividiumcli fund` in their private SSH terminal and approve the six
transfers interactively. Resume only when reconciliation reports all targets
and the canary reserve satisfied.

## 6. Validate and prepare

Run:

```bash
prividiumcli --output json preflight
prividiumcli --output json prepare
```

`preflight` is the authoritative application-readiness check. Resolve only
failures inside the documented Prividium boundary. A missing host prerequisite
belongs to the host engineer. Do not weaken RPC, registry, funding, role,
runtime, DNS, or Compose checks.

Confirm preparation created
`/etc/prividium/runtime/chain/out/preparation.json`. Preparation must use
Stage-0 Validium (`da_mode: no_da`), pull the locked product images, and retain
the exact locally built zk-deployer helper identity used for simulation.

## 7. Authorize and broadcast

Run `prividiumcli --output json broadcast` once without confirmation. It
must stop before transactions. Present the network, L2 chain ID, domain,
deployer, preparation timestamp, and manifest digest.

After explicit authorization of that exact deployment, run:

```bash
CONFIRM_BROADCAST=BROADCAST_SEPOLIA_<L2_CHAIN_ID> prividiumcli --output json broadcast
```

Never infer approval from the original skill invocation. Verify that the
public manifest exists and matches the prepared chain ID.

## 8. Deploy the core stack

Run:

```bash
prividiumcli --output json deploy
```

Success requires the generated deployment summary, 14 healthy long-running
services, successful `chain-preflight`, working HTTPS endpoints, and rejection
of unauthenticated protected RPC. Do not activate the unsupported SSO, webhook,
or institutional-demo profiles.

## 9. Authorize the product smoke

Run `prividiumcli --output json verify` once without confirmation. It must
prove a generated non-admin OIDC user can call authenticated `eth_chainId`, then
stop before the Sepolia canary. Present the generated canary address, minimal
value, chain ID, purpose, and exact confirmation.

After separate explicit authorization, run:

```bash
CONFIRM_CANARY=CANARY_SEPOLIA_<L2_CHAIN_ID> prividiumcli --output json verify
```

`READY` requires the authenticated canary receipt and Explorer indexing. Do
not wait for or poll batch settlement. Report
`deployment/public/happy-path.json`. On later invocations, rely on `status` and
never repeat completed funding, protocol broadcast, or canary submission.

## 10. Reveal credentials only on request

Do not run credential reveal through an agent tool. When explicitly requested,
tell the human to run this in a private interactive SSH terminal:

```bash
prividiumcli credentials show
```

It requires `SHOW`, refuses redirected output, and displays only the evaluation
URLs and three generated logins.
