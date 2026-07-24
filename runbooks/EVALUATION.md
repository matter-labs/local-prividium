# Engineering evaluation and BD handoff

Use this checklist after `./cli/prividium deploy` completes successfully. It keeps
the technical evaluation focused on product behavior and produces a compact
record that an engineering team can share with its BD stakeholders.

## Evidence to retain

Record the repository commit and keep these commit-safe artifacts:

```text
deployment/public/roles.md
deployment/public/manifest.json
deployment/public/deployment-summary.md
```

Do not attach the SOPS file, age identity, `/etc/prividium/runtime`, private RPC
URL, passwords, or private keys to an evaluation report.

## Automated deployment evidence

Confirm the deployment summary reports:

- the intended Sepolia and L2 chain IDs;
- the locked sandbox release and fake-proof/testnet-verifier boundary;
- 14 long-running services ready;
- `chain-preflight` completed successfully;
- working user, administration, Explorer, API, and OIDC endpoints;
- unauthenticated protected RPC access rejected.

## Human evaluation journeys

### Identity and access

- Sign in as `admin@local.dev` or its configured override.
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

- Submit a low-value authenticated sandbox transaction.
- Confirm it is accepted by the intended L2 chain.
- Confirm the Explorer indexes the transaction, address, block, and status.
- Confirm no raw ZKsync OS RPC port is publicly reachable.

### Settlement and monitoring

- Observe at least one batch progress through commit, prove, and execute.
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
| Operational result | Batch settlement and operator-balance observations |
| Integration fit | Expected SSO, webhook, or workflow requirements |
| Constraints | Single host, fake proofs, testnet verifier, hot keys |
| Recommendation | Continue, continue with conditions, or stop |
| Follow-up owners | Customer engineering and BD contacts |

Deferred SSO, webhook, and demo profiles should be listed as future evaluation
work rather than activated through undocumented commands.
