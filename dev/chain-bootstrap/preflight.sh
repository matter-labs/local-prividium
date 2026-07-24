#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/libexec/prividium/rpc-capabilities.sh

required=(L2_CHAIN_ID SEPOLIA_RPC_URL OPERATOR_COMMIT_PRIVATE_KEY OPERATOR_PROVE_PRIVATE_KEY OPERATOR_EXECUTE_PRIVATE_KEY)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required preflight setting: ${name}" >&2
    exit 1
  fi
done

for file in /public/manifest.json /runtime/chain/server.yaml /runtime/chain/sandbox-overrides.yaml /runtime/chain/genesis.json; do
  if [[ ! -s "$file" ]]; then
    echo "Required deployment artifact is missing: ${file}" >&2
    exit 1
  fi
done

if [[ "$(cast chain-id --rpc-url "$SEPOLIA_RPC_URL")" != "11155111" ]]; then
  echo "Configured L1 provider is not Sepolia" >&2
  exit 1
fi
probe_sepolia_rpc_capabilities "$SEPOLIA_RPC_URL"
if [[ "$(jq -r '.l2_chain_id' /public/manifest.json)" != "$L2_CHAIN_ID" ]]; then
  echo "Manifest and runtime L2 chain IDs differ" >&2
  exit 1
fi
if [[ "$(jq -r '.protocol_version' /public/manifest.json)" != "0.31.0" ]]; then
  echo "Manifest protocol version is not 0.31.0" >&2
  exit 1
fi

bridgehub=$(jq -r '.l1_contracts.bridgehub' /public/manifest.json)
ctm=$(jq -r '.l1_contracts.chain_type_manager' /public/manifest.json)
supplier=$(jq -r '.l1_contracts.bytecode_supplier' /public/manifest.json)
diamond=$(jq -r '.chain_contracts.diamond' /public/manifest.json)
verifier=$(jq -r '.l1_contracts.testnet_verifier' /public/manifest.json)
validator_timelock=$(jq -r '.l1_contracts.validator_timelock' /public/manifest.json)

for address in "$bridgehub" "$ctm" "$supplier" "$diamond" "$verifier" "$validator_timelock"; do
  code=$(cast code "$address" --rpc-url "$SEPOLIA_RPC_URL")
  if [[ -z "$code" || "$code" == "0x" ]]; then
    echo "No Sepolia bytecode found at required address ${address}" >&2
    exit 1
  fi
done

registered=$(cast call "$bridgehub" "getZKChain(uint256)(address)" "$L2_CHAIN_ID" --rpc-url "$SEPOLIA_RPC_URL")
if [[ "${registered,,}" != "${diamond,,}" ]]; then
  echo "Bridgehub chain mapping does not match the deployed diamond" >&2
  exit 1
fi

protocol_version_raw=$(cast call "$ctm" "protocolVersion()(uint256)" --rpc-url "$SEPOLIA_RPC_URL")
if [[ "$protocol_version_raw" != "133143986176" ]]; then
  echo "On-chain protocol version is not packed v0.31.0" >&2
  exit 1
fi
onchain_verifier=$(cast call "$ctm" "protocolVersionVerifier(uint256)(address)" "$protocol_version_raw" --rpc-url "$SEPOLIA_RPC_URL")
if [[ "${onchain_verifier,,}" != "${verifier,,}" ]]; then
  echo "CTM verifier differs from the deployment manifest" >&2
  exit 1
fi
if [[ "$(cast call "$verifier" "IS_TESTNET_VERIFIER()(bool)" --rpc-url "$SEPOLIA_RPC_URL")" != "true" ]]; then
  echo "The deployed verifier is not the expected testnet verifier" >&2
  exit 1
fi
onchain_validator_timelock=$(cast call "$ctm" "validatorTimelockPostV29()(address)" --rpc-url "$SEPOLIA_RPC_URL")
if [[ "${onchain_validator_timelock,,}" != "${validator_timelock,,}" ]]; then
  echo "CTM validator timelock differs from the deployment manifest" >&2
  exit 1
fi
ctm_stored_batch_zero=$(cast call "$ctm" "storedBatchZero()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
diamond_stored_batch_zero=$(
  cast call "$diamond" "storedBatchHash(uint256)(bytes32)" 0 --rpc-url "$SEPOLIA_RPC_URL"
)
manifest_stored_batch_zero=$(jq -r '.genesis.stored_batch_zero' /public/manifest.json)
manifest_genesis_root=$(jq -r '.genesis.root' /public/manifest.json)
expected_stored_batch_zero=$(
  cast abi-encode \
    "f((uint64,bytes32,uint64,uint256,bytes32,bytes32,bytes32,uint256,bytes32))" \
    "(0,${manifest_genesis_root},0,0,0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0,0x0000000000000000000000000000000000000000000000000000000000000001)" |
    cast keccak
)
if [[ "$ctm_stored_batch_zero" != "$diamond_stored_batch_zero" ||
      "$ctm_stored_batch_zero" != "$manifest_stored_batch_zero" ||
      "$ctm_stored_batch_zero" != "$expected_stored_batch_zero" ]]; then
  echo "CTM/diamond genesis data does not commit to the manifest genesis root" >&2
  exit 1
fi

minimum_balance="${OPERATOR_MIN_L1_BALANCE_WEI:-10000000000000000}"
check_operator() {
  local role="$1"
  local private_key="$2"
  local role_getter="$3"
  local expected
  local actual
  local balance
  local role_hash
  local has_role
  expected=$(jq -r --arg role "$role" '.operator_addresses[$role]' /public/manifest.json)
  actual=$(cast wallet address --private-key "$private_key")
  if [[ "${expected,,}" != "${actual,,}" ]]; then
    echo "The ${role} operator key does not match the public manifest" >&2
    exit 1
  fi
  balance=$(cast balance "$actual" --rpc-url "$SEPOLIA_RPC_URL")
  if (( balance < minimum_balance )); then
    echo "The ${role} operator has insufficient Sepolia ETH (${balance} wei)" >&2
    exit 1
  fi
  role_hash=$(cast call "$validator_timelock" "${role_getter}()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
  has_role=$(
    cast call "$validator_timelock" \
      "hasRoleForChainId(uint256,bytes32,address)(bool)" \
      "$L2_CHAIN_ID" "$role_hash" "$actual" \
      --rpc-url "$SEPOLIA_RPC_URL"
  )
  if [[ "$has_role" != "true" ]]; then
    echo "The ${role} operator does not hold ${role_getter} for chain ${L2_CHAIN_ID}" >&2
    exit 1
  fi
}

check_operator commit "$OPERATOR_COMMIT_PRIVATE_KEY" COMMITTER_ROLE
check_operator prove "$OPERATOR_PROVE_PRIVATE_KEY" PROVER_ROLE
check_operator execute "$OPERATOR_EXECUTE_PRIVATE_KEY" EXECUTOR_ROLE

expected_genesis_sha=$(jq -r '.genesis.sha256' /public/manifest.json)
actual_genesis_sha=$(sha256sum /runtime/chain/genesis.json | cut -d' ' -f1)
if [[ "$expected_genesis_sha" != "$actual_genesis_sha" ]]; then
  echo "Runtime genesis does not match the deployment manifest" >&2
  exit 1
fi
if ! jq -e '
  .protocol_semantic_version.major == 0 and
  .protocol_semantic_version.minor == 31 and
  .protocol_semantic_version.patch == 0 and
  .genesis_root == $root
' --arg root "$(jq -r '.genesis.root' /public/manifest.json)" /runtime/chain/genesis.json >/dev/null; then
  echo "Runtime genesis protocol/root does not match v0.31.0 deployment metadata" >&2
  exit 1
fi

if grep -Eq 'ac0974|59c699|5de411|8b3a350|7726827c' /runtime/chain/server.yaml; then
  echo "A known deterministic development key appears in the server configuration" >&2
  exit 1
fi

echo "Sepolia chain preflight passed for L2 chain ${L2_CHAIN_ID}"
