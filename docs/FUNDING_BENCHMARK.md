# Core funding policy release benchmark

The repository must not advertise the one-ETH core funding guarantee until the
funding policy is calibrated against the exact locked release. The default
policy intentionally has `benchmark.status: pending`; funding, readiness, and
deployment remain blocked while that is true.

## Rehearsal

Use a fresh Sepolia ecosystem, a fresh SOPS identity set, and exactly one
customer-style transfer of 1 Sepolia ETH to the sandbox funding wallet.

1. Record confirmed L1 balances for the deployer, governor, owner, commit,
   prove, execute, and sponsor addresses.
2. Distribute the provisional plan and perform the complete ecosystem and chain
   broadcast.
3. Start the core stack, bridge Watchdog to its 0.05 L2 ETH target, and allow at
   least two ten-minute batches to settle.
4. Record the confirmed post-rehearsal balances, distribution transaction fees,
   bridge amount and fees, batch counts, gas prices, transaction hashes, and
   the public deployment manifest commit.
5. Calculate release targets:
   - each deployment/governance target is observed spend × 1.5 plus a retained
     0.01 ETH floor;
   - each operator target is observed per-batch spend × 2,016 × 1.5, with a
     minimum of 0.01 ETH;
   - the sponsor reserve is Watchdog’s 0.05 ETH plus observed
     distribution/bridge fees × 1.5 plus 0.05 ETH.
6. Confirm role targets plus sponsor reserve are no more than 0.90 ETH and
   therefore leave at least 0.10 ETH unallocated.
7. Update `deployment/funding-policy.json` with the observed values, calculated
   targets, timestamp, and an evidence reference. Set `benchmark.status` to
   `complete` only after independent review.

The evidence reference must identify an internal, access-controlled rehearsal
record. Do not put private RPC URLs, keys, or decrypted configuration in the
policy or in a public report.

## Release check

Run:

```bash
tools/validate-stack deployment/sandbox.env.example
```

The check must fail if the policy is not benchmarked, exceeds the allocation
boundary, or no longer matches the locked Protocol, zk-deployer, Prividium, and
Watchdog release.
