#!/usr/bin/env bash
# Boot QBFT Besu: generate the genesis + validator key once, then run.
set -euo pipefail

if [[ ! -f /besu-data/networkFiles/genesis.json ]]; then
  besu operator generate-blockchain-config \
    --config-file=/besu-config/besu-network-config.json \
    --to=/besu-data/networkFiles \
    --private-key-file-name=key
fi

KEYFILE=$(ls /besu-data/networkFiles/keys/*/key | head -1)

# FOREST = archive state (the server's bisection reads old blocks); fees zeroed for operator txs.
exec besu \
  --genesis-file=/besu-data/networkFiles/genesis.json \
  --node-private-key-file="$KEYFILE" \
  --data-path=/besu-data/node \
  --data-storage-format=FOREST \
  --rpc-http-enabled --rpc-http-host=0.0.0.0 --rpc-http-port=5010 \
  --rpc-http-api=ETH,NET,WEB3,QBFT,DEBUG,TXPOOL,TRACE \
  --host-allowlist='*' --rpc-http-cors-origins='all' \
  --min-gas-price=0
