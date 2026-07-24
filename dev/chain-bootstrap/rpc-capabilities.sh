#!/usr/bin/env bash

probe_sepolia_rpc_capabilities() {
  local rpc_url="$1"
  local ETH_RPC_URL="$rpc_url"
  local ETH_RPC_TIMEOUT="${ETH_RPC_TIMEOUT:-45}"
  local latest_hex
  local latest_decimal
  local historical_decimal
  local historical_hex
  local block
  local receipt_block
  local receipt_block_decimal
  local receipt_block_hex
  local offset
  local transaction_hash
  local receipt
  local logs
  local historical_call
  local blob_base_fee
  local historical_hex_lower
  local transaction_hash_lower

  export ETH_RPC_URL ETH_RPC_TIMEOUT

  latest_hex=$(cast rpc eth_blockNumber | tr -d '"')
  if [[ ! "$latest_hex" =~ ^0x[0-9a-fA-F]+$ ]]; then
    echo "Sepolia RPC returned an invalid latest block number" >&2
    return 1
  fi

  latest_decimal=$((16#${latest_hex#0x}))
  if (( latest_decimal < 64 )); then
    echo "Sepolia RPC is unexpectedly below block 64" >&2
    return 1
  fi
  historical_decimal=$((latest_decimal - 64))
  printf -v historical_hex '0x%x' "$historical_decimal"
  historical_hex_lower=$(printf "%s" "$historical_hex" | tr '[:upper:]' '[:lower:]')

  block=$(cast rpc eth_getBlockByNumber "$historical_hex" false)
  if ! jq -e --arg number "$historical_hex_lower" \
    '(.number | ascii_downcase) == $number and (.transactions | type == "array")' \
    <<<"$block" >/dev/null; then
    echo "Sepolia RPC does not provide historical blocks" >&2
    return 1
  fi

  historical_call=$(
    cast rpc --raw eth_call \
      '[{"to":"0x0000000000000000000000000000000000000000","data":"0x"},"'"$historical_hex"'"]'
  )
  if [[ "$historical_call" != '"0x"' && "$historical_call" != "0x" ]]; then
    echo "Sepolia RPC does not support historical eth_call" >&2
    return 1
  fi

  logs=$(
    cast rpc --raw eth_getLogs \
      '[{"fromBlock":"'"$historical_hex"'","toBlock":"'"$historical_hex"'"}]'
  )
  if ! jq -e 'type == "array"' <<<"$logs" >/dev/null; then
    echo "Sepolia RPC does not support historical log queries" >&2
    return 1
  fi

  receipt_block=$(cast rpc eth_getBlockByNumber latest false)
  transaction_hash=$(jq -r '.transactions[0] // empty' <<<"$receipt_block")
  for offset in $(seq 1 8); do
    [[ -n "$transaction_hash" ]] && break
    receipt_block_decimal=$((latest_decimal - offset))
    printf -v receipt_block_hex '0x%x' "$receipt_block_decimal"
    receipt_block=$(cast rpc eth_getBlockByNumber "$receipt_block_hex" false)
    transaction_hash=$(jq -r '.transactions[0] // empty' <<<"$receipt_block")
  done
  if [[ ! "$transaction_hash" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "No recent Sepolia transaction was available for receipt validation" >&2
    return 1
  fi
  receipt=$(cast rpc eth_getTransactionReceipt "$transaction_hash")
  transaction_hash_lower=$(printf "%s" "$transaction_hash" | tr '[:upper:]' '[:lower:]')
  if ! jq -e --arg hash "$transaction_hash_lower" \
    '(.transactionHash | ascii_downcase) == $hash and .blockNumber != null' \
    <<<"$receipt" >/dev/null; then
    echo "Sepolia RPC does not provide transaction receipts" >&2
    return 1
  fi

  blob_base_fee=$(cast rpc eth_blobBaseFee | tr -d '"')
  if [[ ! "$blob_base_fee" =~ ^0x[0-9a-fA-F]+$ ]]; then
    echo "Sepolia RPC does not expose EIP-4844 blob fee data" >&2
    return 1
  fi
}
