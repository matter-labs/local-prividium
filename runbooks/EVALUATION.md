# Engineering evaluation and BD handoff

Use this checklist after `prividiumcli verify` reports `READY`. It
keeps the technical evaluation focused on product behavior and produces a
compact record that an engineering team can share with its BD stakeholders.

Before handoff, BD confirms that the customer has the approved repository
revision, this evaluation-only boundary, a suitable VPS, a private
archive-capable Sepolia RPC, a distinct browser RPC, and a pull-only Quay
credential issued by Matter Labs DevOps. The customer installs and
authenticates Codex CLI or Claude Code before invoking the repository skill.

## Evidence to retain

Record the repository commit and keep these commit-safe artifacts:

```text
deployment/public/roles.md
deployment/public/manifest.json
deployment/public/deployment-summary.md
deployment/public/happy-path.json
```

Do not attach the SOPS file, age identity, `/etc/prividium/runtime`, private RPC
URL, passwords, or private keys to an evaluation report.

For the disposable-VPS qualification, record the wall-clock start and finish,
the customer engineer's host-readiness handoff, and each human intervention:
DNS or network action, pull-only Quay login, funding-wallet top-up and transfer
approval, protocol broadcast approval, and canary approval. Record only the
time, action, actor, and outcome—never the credential or secret value.
`happy-path.json` records the automated product/canary elapsed time;
the qualification log supplies the full blank-VPS elapsed time.

## Automated deployment evidence

Confirm the deployment summary reports:

- the intended Sepolia and L2 chain IDs;
- the locked sandbox release and fake-proof/testnet-verifier boundary;
- 14 long-running services ready;
- `chain-preflight` completed successfully;
- working user, administration, Explorer, API, and OIDC endpoints;
- unauthenticated protected RPC access rejected.

Confirm `happy-path.json` reports a generated non-admin OIDC login,
authenticated RPC, a successful canary receipt, and Explorer indexing.

## Human evaluation journeys

An authorized engineer retrieves the generated logins directly from a private
SSH terminal with `prividiumcli credentials show`. The command must not be
run through an agent transcript or redirected to a file.

### Identity and access

- Sign in as `admin@local.dev`.
- Confirm the administrator must change the initial password.
- Sign in as both evaluation users.
- Confirm users cannot access administrator-only behavior.
- Confirm OIDC discovery advertises the exact sandbox issuer.

### Protected RPC and applications

- Confirm unauthenticated protected RPC requests receive `401` or `403`.
- Confirm an authenticated user can access the permitted application and RPC
  experience.
- Confirm the user and administration applications load without browser CORS,
  certificate, or mixed-content errors.

### Transaction and Explorer

- Review the confirmation-gated canary recorded in `happy-path.json`.
- Confirm it was accepted by the intended L2 chain and indexed by Explorer.
- Confirm no raw ZKsync OS RPC port is publicly reachable.

### Monitoring

- Confirm the three settlement-operator balances match the public role
  inventory and remain above their configured targets.
- Access Grafana through an SSH tunnel and confirm Prometheus and the
  operator-balance exporter are healthy.

## Security boundary

Verify:

- only SSH and Caddy are publicly reachable;
- Grafana remains loopback-bound;
- PostgreSQL, Keycloak administration, Prometheus, and raw node RPC are private;
- the public artifacts contain no secret or private provider value;
- all evaluation participants understand that proofs are fake and custody is
  not production-grade.

## Suggested BD report

Keep the handoff short:

| Topic | Record |
| --- | --- |
| Evaluation objective | What the team intended to validate |
| Environment | Domain, Sepolia, generated L2 chain ID |
| Deployment result | Completion date and deployment-summary reference |
| Identity result | Administrator/user and access-control observations |
| Product result | Authenticated API/RPC and application observations |
| Transaction result | Example transaction and Explorer link |
| Operational result | Service health and operator-balance observations |
| Integration fit | Expected SSO, webhook, or workflow requirements |
| Constraints | Single host, fake proofs, testnet verifier, hot keys |
| Recommendation | Continue, continue with conditions, or stop |
| Follow-up owners | Customer engineering and BD contacts |

The unsupported SSO, webhook, and demo profiles should be listed as future
evaluation work rather than activated through undocumented commands.

## End of evaluation

There is currently no automated uninstall workflow. When the evaluation ends:

- retain only the approved public evidence and any separately approved secret
  backup needed for an intentional extension;
- have Matter Labs DevOps revoke the pull-only Quay credential;
- run `docker logout quay.io` if the VPS will be retained;
- revoke or rotate evaluation-specific RPC credentials;
- remove the six public DNS records;
- destroy the VPS and attached volumes through the provider, unless the
  evaluation owner explicitly approves continued retention; and
- record the cleanup owner and completion date in the BD report.

Running `docker compose down` is not complete cleanup because encrypted files,
the age identity, protected runtime, Docker volumes, and on-chain Sepolia
contracts remain. Destroying the dedicated evaluation VPS is the expected
cleanup boundary. Sepolia contracts and transactions cannot be removed; never
reuse their evaluation keys for another environment or assets of value.
