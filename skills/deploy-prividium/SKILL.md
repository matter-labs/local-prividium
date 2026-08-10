---
name: deploy-prividium
description: Deploy and verify the single-VPS Prividium Sepolia evaluation stack from a repository checkout. Use when a customer asks to prepare a blank Ubuntu 24.04 VPS, continue an interrupted evaluation deployment, identify the next human checkpoint, or verify that the Prividium sandbox is ready.
---

# Deploy Prividium

Drive the supported evaluation workflow through `./cli/prividium`. Do not
invent package, Docker, protocol, or recovery commands when a CLI stage exists.

Run this workflow only after the user explicitly invokes the skill. If this
skill was loaded implicitly, explain the native invocation and make no changes:

- Codex: `$deploy-prividium`
- Claude Code: `/deploy-prividium`

## Safety boundary

- Support only a dedicated, initially blank Ubuntu Server 24.04 amd64 VPS.
- Treat this as a single-host, fake-proof Sepolia evaluation, never production.
- Never print, read into chat, or copy the private RPC value, Quay token, age
  identity, encrypted/decrypted environment, passwords, or private keys.
- Never change sshd, host/provider firewall rules, DNS, or provider resources.
- Stop before funding transfers and protocol broadcast for explicit human
  authorization.
- If broadcast may have started and then failed, preserve all output and
  `/etc/prividium/runtime/chain`; do not rerun or regenerate identities.
- Do not attempt to migrate or repair an Ansible-prepared or nonblank host.
  Recommend recreating the disposable VPS.

## Resume safely

Start every invocation with read-only inspection. Locate the repository root,
confirm `git status --short`, and inspect existence and metadata only for:

```text
/etc/prividium/.host-contract-version
deployment/input.env
deployment/secrets/age.key
deployment/secrets/sandbox.enc.env
deployment/public/roles.md
/etc/prividium/runtime/chain/out/preparation.json
deployment/public/manifest.json
deployment/public/deployment-summary.md
```

Do not display file contents except the three public Markdown/JSON artifacts.
Run the verification command for the highest apparent stage. Continue from the
first incomplete stage; do not recreate completed secret or protocol state.

## Present human checkpoints

For every pause, state all five items concisely:

1. Why the person must act.
2. The exact action or command.
3. How success is verified.
4. What value is sensitive and must stay out of chat.
5. Resume by invoking this skill again.

Do not claim progress past a checkpoint until its verification passes.

## 1. Establish the operator

Check `id -u`, Ubuntu release, and architecture.

If already running as a normal passwordless-sudo operator, continue with host
bootstrap.

If running as root, use the constrained repository command. Never choose an
SSH key source silently. Prefer the current provider-installed authorized-keys
file when it exists, after explaining that restrictions are preserved:

```bash
./cli/prividium host operator create --copy-current-authorized-keys --yes
```

Otherwise have the user provide a public key through `--public-key-file`.
Never request or accept a private key. Then stop at this checkpoint:

- Keep the root session open.
- Open a second SSH session as `prividium`.
- Run `sudo -n true` in that second session.
- Clone the repository over HTTPS into the operator's home; do not reuse the
  checkout under `/root`.
- Start the chosen agent from the operator-owned checkout and reinvoke this
  skill.

## 2. Prepare and verify the host

Run in order:

```bash
./cli/prividium host bootstrap
./cli/prividium host preflight
./cli/prividium host install --check
```

Summarize the printed managed and excluded boundaries. Obtain explicit user
approval, then apply without trying to answer the CLI confirmation yourself:

```bash
./cli/prividium host install --yes
```

Stop after installation. Tell the user to reboot first only when
`reboot_required=true`; otherwise reconnect SSH so Docker group membership is
active. Resume from the operator-owned checkout and run:

```bash
./cli/prividium host verify
```

Do not proceed until verification passes.

## 3. Collect the four human inputs

If encrypted configuration does not exist, create the protected input file
without filling its values:

```bash
install -m 0600 deployment/input.env.example deployment/input.env
```

Ask the user to edit it directly on the VPS. It contains exactly:

```text
SANDBOX_DOMAIN
ACME_EMAIL
SEPOLIA_RPC_URL
SEPOLIA_BROWSER_RPC_URL
```

Explain that `SEPOLIA_RPC_URL` is the private archive-capable endpoint and must
not be pasted into chat. The browser RPC must be a distinct public HTTPS
endpoint with CORS support.

When the user says editing is complete, validate without printing values:

```bash
tools/parse-input-env deployment/input.env >/dev/null
```

Then initialize:

```bash
./cli/prividium init
```

Verify that the encrypted environment and age identity are nonempty regular
files with safe modes and that `deployment/public/roles.md` exists. Only after
all three checks pass, delete the plaintext input precisely:

```bash
rm -f -- deployment/input.env
```

If initialization fails, retain the input file for correction. Never reveal
generated passwords during initialization.

## 4. Complete external infrastructure

Pause for the customer to configure and verify:

- Provider firewall/security group: administrative SSH only from approved
  CIDRs, TCP 80/443 and UDP 443 publicly, all other inbound traffic denied.
- Six public IPv4 `A` records pointing to the VPS: `app`, `admin`, `api`,
  `explorer`, `explorer-api`, and `idp` under the sandbox domain.
- No public `AAAA` records unless equivalent IPv6 routing and filtering exist.

Do not configure these resources. Later `preflight` and `deploy` verify the
parts visible from the VPS; the customer remains responsible for an external
port scan.

## 5. Authenticate to Quay

Pause for a pull-only credential issued by Matter Labs DevOps. The human must
run `docker login quay.io` with `--password-stdin` directly in their SSH
terminal and report only whether it succeeded. Never ask them to paste the
token into the agent conversation or put it in `deployment/input.env`. The
normal application preflight later performs the authoritative pinned-image
access check without printing registry credentials.

## 6. Fund the generated identities

Run the read-only explanation and reconciliation:

```bash
./cli/prividium fund --list
./cli/prividium fund
```

If it reports a funding-wallet shortfall, pause while the human sends only the
requested Sepolia ETH to that displayed wallet. Once funded, require the human
to run `./cli/prividium fund` directly in their SSH terminal and approve the
six transfers interactively. Resume only after a rerun reports all targets
satisfied.

## 7. Prepare the protocol

Run:

```bash
./cli/prividium preflight
./cli/prividium prepare
```

Resolve only failures within the documented evaluation boundary. Do not weaken
DNS, registry, RPC, funding, role, or Compose checks. Confirm preparation
created `/etc/prividium/runtime/chain/out/preparation.json` before continuing.

## 8. Authorize and broadcast

Run `./cli/prividium broadcast` non-interactively once to display readiness and
the required `BROADCAST_SEPOLIA_<L2_CHAIN_ID>` confirmation; it must block
before transactions. Present the network, L2 chain ID, domain, deployer,
preparation timestamp, and manifest digest to the user.

After the user explicitly authorizes that exact deployment, run:

```bash
CONFIRM_BROADCAST=BROADCAST_SEPOLIA_<L2_CHAIN_ID> ./cli/prividium broadcast
```

Never synthesize approval from the original skill invocation. Verify the
public manifest exists and matches the prepared L2 chain ID.

## 9. Deploy and verify

Run:

```bash
./cli/prividium deploy
```

Success requires the generated deployment summary, 14 healthy long-running
services, successful `chain-preflight`, working HTTPS endpoints, and rejection
of unauthenticated protected RPC access. Report the public URLs and the three
commit-safe evidence files. Do not include secret files in the report.

On a later invocation, treat a passing deployment summary and live health
checks as complete. Do not repeat funding, preparation, or broadcast.

## 10. Reveal credentials only on request

Do not run the reveal command through an agent tool. When the human explicitly
asks for credentials, tell them to run this in a private interactive SSH
terminal outside the agent transcript:

```bash
./cli/prividium credentials show
```

The command requires `SHOW`, refuses redirected output, and displays only the
evaluation URLs and three generated logins.
