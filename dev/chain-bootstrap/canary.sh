#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly expected_confirmation="CANARY_SEPOLIA_${L2_CHAIN_ID:-missing}"
readonly attempt=/runtime/chain/canary-attempt.json
readonly submission=/runtime/chain/canary-submission.json
readonly forge_root=/opt/era-contracts/l1-contracts
readonly script_output="${forge_root}/script-out/prividium-canary.json"
readonly broadcast_output="${forge_root}/broadcast/PrividiumCanaryDeposit.s.sol/11155111/run-latest.json"
readonly canary_amount_wei="${CANARY_L2_VALUE_WEI:-1000000000000}"

for name in L2_CHAIN_ID SEPOLIA_RPC_URL BRIDGE_SPONSOR_PRIVATE_KEY CONFIRM_CANARY; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required canary setting: ${name}" >&2
    exit 1
  fi
done
if [[ "$CONFIRM_CANARY" != "$expected_confirmation" ]]; then
  echo "Set CONFIRM_CANARY=${expected_confirmation} to authorize the Sepolia canary" >&2
  exit 1
fi
if [[ ! "$L2_CHAIN_ID" =~ ^[0-9]+$ || ! "$canary_amount_wei" =~ ^[0-9]+$ ]] ||
   (( canary_amount_wei < 1 )); then
  echo "Canary chain ID or amount is invalid" >&2
  exit 1
fi
if ! jq -e --argjson chain_id "$L2_CHAIN_ID" '
  .l1_chain_id == 11155111 and
  .l2_chain_id == $chain_id and
  .data_availability.mode == "no_da" and
  .transaction_filterer.deposits_allowed == true
' /public/manifest.json >/dev/null; then
  echo "Public manifest is missing the approved Validium/filterer configuration" >&2
  exit 1
fi

canary_address=$(cast wallet address --private-key "$BRIDGE_SPONSOR_PRIVATE_KEY")
if [[ -s "$submission" ]] && jq -e \
  --argjson chain_id "$L2_CHAIN_ID" \
  --arg address "${canary_address,,}" '
    .l1_chain_id == 11155111 and
    .l2_chain_id == $chain_id and
    (.canary_address | ascii_downcase) == $address and
    (.l1_transaction_hash | test("^0x[0-9a-fA-F]{64}$")) and
    (.l2_transaction_hash | test("^0x[0-9a-fA-F]{64}$"))
  ' "$submission" >/dev/null 2>&1; then
  l1_transaction_hash=$(jq -r '.l1_transaction_hash' "$submission")
  if [[ "$(cast receipt "$l1_transaction_hash" status --rpc-url "$SEPOLIA_RPC_URL")" == "1" ]]; then
    echo "Reusing the previously confirmed Prividium canary submission."
    cat "$submission"
    exit 0
  fi
  echo "Existing canary evidence does not have a successful Sepolia receipt" >&2
  exit 1
fi
if [[ -e "$attempt" || -L "$attempt" ]]; then
  if [[ ! -f "$attempt" || ! -s "$attempt" ]] ||
     ! jq -e \
       --argjson chain_id "$L2_CHAIN_ID" \
       --arg address "${canary_address,,}" '
         .schema_version == 1 and
         .status == "STARTED" and
         .l1_chain_id == 11155111 and
         .l2_chain_id == $chain_id and
         (.canary_address | ascii_downcase) == $address
       ' "$attempt" >/dev/null; then
    echo "Canary attempt evidence is invalid; preserve runtime state for manual review" >&2
    exit 1
  fi
  echo "CANARY REVIEW REQUIRED" >&2
  echo "An approved Sepolia canary previously started without durable submission evidence." >&2
  echo "Do not submit another canary until the prior transaction state is inspected." >&2
  exit 1
fi

bridgehub=$(jq -r '.l1_contracts.bridgehub' /public/manifest.json)
rm -f -- "$script_output" "$broadcast_output"
jq -n \
  --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson l2_chain_id "$L2_CHAIN_ID" \
  --arg canary_address "$canary_address" \
  --arg amount_wei "$canary_amount_wei" \
  '{
    schema_version: 1,
    status: "STARTED",
    started_at: $started_at,
    l1_chain_id: 11155111,
    l2_chain_id: $l2_chain_id,
    canary_address: $canary_address,
    amount_wei: $amount_wei
  }' >"${attempt}.tmp"
mv "${attempt}.tmp" "$attempt"
chmod 0600 "$attempt"
(
  cd "$forge_root"
  forge script \
    deploy-scripts/PrividiumCanaryDeposit.s.sol:PrividiumCanaryDeposit \
    --sig "run(address,uint256,address,uint256)" \
    "$bridgehub" "$L2_CHAIN_ID" "$canary_address" "$canary_amount_wei" \
    --rpc-url "$SEPOLIA_RPC_URL" \
    --private-key "$BRIDGE_SPONSOR_PRIVATE_KEY" \
    --broadcast \
    --slow
)

l2_transaction_hash=$(jq -er '.l2_transaction_hash | select(test("^0x[0-9a-fA-F]{64}$"))' "$script_output")
l1_transaction_hash=$(
  jq -er '[.receipts[].transactionHash | select(test("^0x[0-9a-fA-F]{64}$"))] | last' \
    "$broadcast_output"
)
if [[ "$(cast receipt "$l1_transaction_hash" status --rpc-url "$SEPOLIA_RPC_URL")" != "1" ]]; then
  echo "The Sepolia canary transaction did not succeed" >&2
  exit 1
fi

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson l2_chain_id "$L2_CHAIN_ID" \
  --arg canary_address "$canary_address" \
  --arg amount_wei "$canary_amount_wei" \
  --arg l1_transaction_hash "$l1_transaction_hash" \
  --arg l2_transaction_hash "$l2_transaction_hash" \
  '{
    schema_version: 1,
    generated_at: $generated_at,
    l1_chain_id: 11155111,
    l2_chain_id: $l2_chain_id,
    canary_address: $canary_address,
    amount_wei: $amount_wei,
    l1_transaction_hash: $l1_transaction_hash,
    l2_transaction_hash: $l2_transaction_hash
  }' >"${submission}.tmp"
mv "${submission}.tmp" "$submission"
chmod 0600 "$submission"
jq \
  --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg l1_transaction_hash "$l1_transaction_hash" \
  --arg l2_transaction_hash "$l2_transaction_hash" \
  '.status = "COMPLETE" |
   .completed_at = $completed_at |
   .l1_transaction_hash = $l1_transaction_hash |
   .l2_transaction_hash = $l2_transaction_hash' \
  "$attempt" >"${attempt}.tmp"
mv "${attempt}.tmp" "$attempt"
chmod 0600 "$attempt"
cat "$submission"
