# Prividium sandbox deployment summary

This commit-safe report is generated only after the core services and public
HTTPS, API, Explorer, and OIDC checks pass.

- Status: **HEALTHY**
- Service model: **14 long-running services and one completed `chain-preflight` job**
- Ethereum settlement network: Sepolia (`11155111`)
- L2 chain ID: `1900000001`
- Base token and protocol fee asset: **ETH**

The generated report lists the sandbox URLs, locked component versions,
on-chain contract addresses, enabled optional capabilities, automated health
results, and the fake-proof/single-VPS sandbox limitations. A failed deployment
writes a protected incomplete diagnostic under the runtime directory and never
overwrites a previous successful public summary.
