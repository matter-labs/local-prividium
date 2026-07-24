#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

source /usr/local/libexec/prividium/rpc-capabilities.sh

readonly zero_address="0x0000000000000000000000000000000000000000"
readonly chainlist_url="https://chainid.network/chains.json"

required=(
  BOOTSTRAP_MODE L2_CHAIN_ID SEPOLIA_RPC_URL
  PREPARED_IMAGE_ID
  L1_DEPLOYER_PRIVATE_KEY
  ECOSYSTEM_GOVERNOR_PRIVATE_KEY
  CHAIN_OWNER_PRIVATE_KEY FEE_ACCOUNT_PRIVATE_KEY
  OPERATOR_COMMIT_PRIVATE_KEY OPERATOR_PROVE_PRIVATE_KEY OPERATOR_EXECUTE_PRIVATE_KEY
)

for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required bootstrap setting: ${name}" >&2
    exit 1
  fi
done
if [[ ! "$PREPARED_IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "PREPARED_IMAGE_ID must be an immutable Docker image identity" >&2
  exit 1
fi

if [[ ! "$L2_CHAIN_ID" =~ ^[0-9]+$ ]] || (( L2_CHAIN_ID < 1073741824 || L2_CHAIN_ID > 2147483647 )); then
  echo "L2_CHAIN_ID must be in the high 31-bit range 1073741824..2147483647" >&2
  exit 1
fi
if [[ -e /public/manifest.json || -L /public/manifest.json ]]; then
  echo "Refusing to replace an existing public protocol manifest" >&2
  exit 1
fi

actual_l1_chain_id=$(cast chain-id --rpc-url "$SEPOLIA_RPC_URL")
if [[ "$actual_l1_chain_id" != "11155111" ]]; then
  echo "The configured L1 endpoint returned chain ID ${actual_l1_chain_id}, expected Sepolia (11155111)" >&2
  exit 1
fi
probe_sepolia_rpc_capabilities "$SEPOLIA_RPC_URL"

# Protocol v31 requires a nonzero field named zkTokenAssetId even when the
# chain does not deploy or use a ZK token. This ETH-only sandbox supplies the
# canonical Sepolia ETH NTV asset ID, derived from (L1 chain, L2 NTV, ETH).
readonly l2_native_token_vault="0x0000000000000000000000000000000000010004"
readonly eth_token_address="0x0000000000000000000000000000000000000001"
ZK_TOKEN_ASSET_ID=$(
  cast abi-encode "f(uint256,address,address)" \
    11155111 "$l2_native_token_vault" "$eth_token_address" |
    cast keccak
)
export ZK_TOKEN_ASSET_ID

check_deployment_balance() {
  local role="$1"
  local private_key="$2"
  local address
  local balance
  address=$(cast wallet address --private-key "$private_key")
  balance=$(cast balance "$address" --rpc-url "$SEPOLIA_RPC_URL")
  if (( balance < ${DEPLOYMENT_SIGNER_MIN_L1_BALANCE_WEI:-10000000000000000} )); then
    echo "${role} ${address} has only ${balance} wei on Sepolia" >&2
    exit 1
  fi
}

check_deployment_balance "ecosystem deployer" "$L1_DEPLOYER_PRIVATE_KEY"
check_deployment_balance "ecosystem governor" "$ECOSYSTEM_GOVERNOR_PRIVATE_KEY"
check_deployment_balance "chain owner" "$CHAIN_OWNER_PRIVATE_KEY"
check_deployment_balance "commit operator" "$OPERATOR_COMMIT_PRIVATE_KEY"
check_deployment_balance "prove operator" "$OPERATOR_PROVE_PRIVATE_KEY"
check_deployment_balance "execute operator" "$OPERATOR_EXECUTE_PRIVATE_KEY"

chainlist_file=$(mktemp)
trap 'rm -f "$chainlist_file"' EXIT
curl --fail --silent --show-error --location "$chainlist_url" --output "$chainlist_file"
if jq -e --argjson id "$L2_CHAIN_ID" 'any(.[]; .chainId == $id)' "$chainlist_file" >/dev/null; then
  echo "L2 chain ID ${L2_CHAIN_ID} is already registered in Chainlist" >&2
  exit 1
fi

wallet_address() {
  cast wallet address --private-key "$1"
}

write_wallet() {
  local indent="$1"
  local role="$2"
  local private_key="$3"
  local address
  address=$(wallet_address "$private_key")
  printf "%s%s:\n%s  address: '%s'\n%s  private_key: '%s'\n" \
    "$indent" "$role" "$indent" "$address" "$indent" "$private_key"
}

wallets_candidate=$(mktemp)
{
  echo "ecosystem:"
  write_wallet "  " "governor" "$ECOSYSTEM_GOVERNOR_PRIVATE_KEY"
  echo "${L2_CHAIN_ID}:"
  write_wallet "  " "owner" "$CHAIN_OWNER_PRIVATE_KEY"
  write_wallet "  " "fee_account" "$FEE_ACCOUNT_PRIVATE_KEY"
  write_wallet "  " "operator_commit_sk" "$OPERATOR_COMMIT_PRIVATE_KEY"
  write_wallet "  " "operator_prove_sk" "$OPERATOR_PROVE_PRIVATE_KEY"
  write_wallet "  " "operator_execute_sk" "$OPERATOR_EXECUTE_PRIVATE_KEY"
} >"$wallets_candidate"

mapfile -t role_addresses < <(
  for private_key in \
    "$L1_DEPLOYER_PRIVATE_KEY" \
    "$ECOSYSTEM_GOVERNOR_PRIVATE_KEY" \
    "$CHAIN_OWNER_PRIVATE_KEY" "$FEE_ACCOUNT_PRIVATE_KEY" \
    "$OPERATOR_COMMIT_PRIVATE_KEY" "$OPERATOR_PROVE_PRIVATE_KEY" "$OPERATOR_EXECUTE_PRIVATE_KEY"; do
    wallet_address "$private_key" | tr '[:upper:]' '[:lower:]'
  done
)
if [[ "$(printf "%s\n" "${role_addresses[@]}" | sort -u | wc -l | tr -d ' ')" != "${#role_addresses[@]}" ]]; then
  echo "Every deployer, governance, fee, and operator role must use a distinct private key" >&2
  exit 1
fi

mkdir -p /runtime/chain /public
if [[ -s /runtime/chain/wallets.yaml ]] && ! cmp -s "$wallets_candidate" /runtime/chain/wallets.yaml; then
  echo "Refusing to replace the role wallet set in an existing runtime directory" >&2
  exit 1
fi
install -m 0600 "$wallets_candidate" /runtime/chain/wallets.yaml
rm -f "$wallets_candidate"

cat >/runtime/chain/intent.yaml <<EOF
schema_version: 1
l1_rpc_url: "${SEPOLIA_RPC_URL}"
wallets:
  path: /runtime/chain/wallets.yaml
chains:
  - chain_id: ${L2_CHAIN_ID}
    da_mode: rollup
EOF
chmod 0600 /runtime/chain/intent.yaml

common_bootstrap=(
  --intent /runtime/chain/intent.yaml
  --state /runtime/chain/state.json
  --out /runtime/chain/out
  --private-key "$L1_DEPLOYER_PRIVATE_KEY"
  --wallets-out /runtime/chain/wallets.yaml
  --genesis-out /runtime/chain/genesis.json
  --subdir "sandbox-${L2_CHAIN_ID}"
)
common_apply=(
  --intent /runtime/chain/intent.yaml
  --state /runtime/chain/state.json
  --wallets /runtime/chain/wallets.yaml
  --out /runtime/chain/out
  --private-key "$L1_DEPLOYER_PRIVATE_KEY"
  --subdir "sandbox-${L2_CHAIN_ID}"
  --no-fund-l2
)

# The patched deployer reads this address in both simulation and broadcast
# modes, so the dry run exercises the exact ecosystem ownership configuration.
export ZK_DEPLOYER_ECOSYSTEM_GOVERNOR_ADDRESS
ZK_DEPLOYER_ECOSYSTEM_GOVERNOR_ADDRESS=$(wallet_address "$ECOSYSTEM_GOVERNOR_PRIVATE_KEY")

case "$BOOTSTRAP_MODE" in
  prepare)
    zk-deployer bootstrap "${common_bootstrap[@]}"
    if [[ ! -s /runtime/chain/state.json ||
          ! -s /runtime/chain/out/manifest.json ]]; then
      echo "Bootstrap simulation did not produce state and manifest artifacts" >&2
      exit 1
    fi
    prepared_state_sha256=$(sha256sum /runtime/chain/state.json | cut -d' ' -f1)
    prepared_manifest_sha256=$(sha256sum /runtime/chain/out/manifest.json | cut -d' ' -f1)
    jq -n \
      --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson l2_chain_id "$L2_CHAIN_ID" \
      --arg zk_deployer_commit "$ZK_DEPLOYER_COMMIT" \
      --arg protocol_commit "$PROTOCOL_COMMIT" \
      --arg state_sha256 "$prepared_state_sha256" \
      --arg manifest_sha256 "$prepared_manifest_sha256" \
      --arg image_id "$PREPARED_IMAGE_ID" \
      '{
        schema_version: 1,
        generated_at: $generated_at,
        l1_chain_id: 11155111,
        l2_chain_id: $l2_chain_id,
        sources: {
          zk_deployer: $zk_deployer_commit,
          protocol: $protocol_commit
        },
        chain_state_sha256: $state_sha256,
        prepared_manifest_sha256: $manifest_sha256,
        chain_bootstrap_image_id: $image_id
      }' >/runtime/chain/out/preparation.json
    chmod 0600 /runtime/chain/out/preparation.json
    echo
    echo "Bootstrap simulation complete. Review /runtime/chain/out/manifest.json."
    echo "Preparation provenance: /runtime/chain/out/preparation.json."
    echo "Broadcast requires CONFIRM_BROADCAST=BROADCAST_SEPOLIA_${L2_CHAIN_ID}."
    exit 0
    ;;
  broadcast)
    expected_confirmation="BROADCAST_SEPOLIA_${L2_CHAIN_ID}"
    if [[ "${CONFIRM_BROADCAST:-}" != "$expected_confirmation" ]]; then
      echo "Set CONFIRM_BROADCAST=${expected_confirmation} to authorize Sepolia writes" >&2
      exit 1
    fi
    for prepared_artifact in \
      /runtime/chain/state.json \
      /runtime/chain/out/manifest.json \
      /runtime/chain/out/preparation.json; do
      if [[ ! -s "$prepared_artifact" ]]; then
        echo "Prepared protocol artifact is missing: ${prepared_artifact}" >&2
        exit 1
      fi
    done
    prepared_state_sha256=$(sha256sum /runtime/chain/state.json | cut -d' ' -f1)
    prepared_manifest_sha256=$(sha256sum /runtime/chain/out/manifest.json | cut -d' ' -f1)
    if ! jq -e \
      --argjson chain_id "$L2_CHAIN_ID" \
      --arg zk_deployer_commit "$ZK_DEPLOYER_COMMIT" \
      --arg protocol_commit "$PROTOCOL_COMMIT" \
      --arg state_sha256 "$prepared_state_sha256" \
      --arg manifest_sha256 "$prepared_manifest_sha256" \
      --arg image_id "$PREPARED_IMAGE_ID" \
      '
        .schema_version == 1 and
        .l1_chain_id == 11155111 and
        .l2_chain_id == $chain_id and
        (.generated_at |
          type == "string" and
          test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
        .sources.zk_deployer == $zk_deployer_commit and
        .sources.protocol == $protocol_commit and
        .chain_state_sha256 == $state_sha256 and
        .prepared_manifest_sha256 == $manifest_sha256 and
        .chain_bootstrap_image_id == $image_id
      ' /runtime/chain/out/preparation.json >/dev/null; then
      echo "Prepared execution inputs changed after simulation; rerun ./cli/prividium prepare" >&2
      exit 1
    fi
    ;;
  *)
    echo "BOOTSTRAP_MODE must be prepare or broadcast" >&2
    exit 1
    ;;
esac

zk-deployer bootstrap "${common_bootstrap[@]}" --broadcast

bridgehub=$(jq -r '.steps["ecosystem.init"].bridgehub_proxy' /runtime/chain/state.json)
ctm=$(jq -r '.steps["ecosystem.init"].ctm_proxy' /runtime/chain/state.json)
registered_chain=$(cast call "$bridgehub" "getZKChain(uint256)(address)" "$L2_CHAIN_ID" --rpc-url "$SEPOLIA_RPC_URL")
prepared_diamond=$(jq -r --arg key "chain.init.${L2_CHAIN_ID}.prepared" '.steps[$key].diamond_proxy // empty' /runtime/chain/state.json)
if [[ "$registered_chain" != "$zero_address" && "${registered_chain,,}" != "${prepared_diamond,,}" ]]; then
  echo "Bridgehub already maps chain ID ${L2_CHAIN_ID} to ${registered_chain}" >&2
  exit 1
fi

zk-deployer apply "${common_apply[@]}"
zk-deployer apply "${common_apply[@]}" --broadcast
zk-deployer server-config \
  --intent /runtime/chain/intent.yaml \
  --state /runtime/chain/state.json \
  --wallets /runtime/chain/wallets.yaml \
  --chain "$L2_CHAIN_ID" \
  --output /runtime/chain/server.yaml

cat >/runtime/chain/sandbox-overrides.yaml <<EOF
batcher:
  batch_timeout: 600s
l1_sender:
  poll_interval: 1s
l1_watcher:
  confirmations: 12
  poll_interval: 1s
  finalized_poll_interval: 60s
prover_api:
  fake_fri_provers:
    enabled: true
  fake_snark_provers:
    enabled: true
observability:
  log:
    format: json
    use_color: false
external_price_api_client:
  source: Forced
  forced_prices:
    "0x0000000000000000000000000000000000000001": ${ETH_PRICE_USD:-3000}
general:
  rocks_db_path: /db/node1
rpc:
  address: 0.0.0.0:3050
mempool:
  minimal_protocol_basefee: 7
sequencer:
  revm_consistency_checker_revert_on_divergence: true
name: prividium-sandbox
EOF
chmod 0600 /runtime/chain/server.yaml /runtime/chain/sandbox-overrides.yaml /runtime/chain/genesis.json

diamond=$(jq -r --arg key "chain.init.${L2_CHAIN_ID}.prepared" '.steps[$key].diamond_proxy' /runtime/chain/state.json)
chain_admin=$(jq -r --arg key "chain.init.${L2_CHAIN_ID}.prepared" '.steps[$key].chain_admin' /runtime/chain/state.json)
supplier=$(jq -r '.steps["ecosystem.init"].bytecodes_supplier' /runtime/chain/state.json)
governance=$(jq -r '.steps["ecosystem.init"].governance' /runtime/chain/state.json)
rollup_validator=$(jq -r '.steps["ecosystem.init"].rollup_l1_da_validator' /runtime/chain/state.json)
blob_validator=$(jq -r '.steps["ecosystem.init"].blobs_zksync_os_l1_da_validator' /runtime/chain/state.json)
protocol_version_raw=$(cast call "$ctm" "protocolVersion()(uint256)" --rpc-url "$SEPOLIA_RPC_URL")
if [[ "$protocol_version_raw" != "133143986176" ]]; then
  echo "CTM protocol version is ${protocol_version_raw}, expected packed v0.31.0 (133143986176)" >&2
  exit 1
fi
testnet_verifier=$(cast call "$ctm" "protocolVersionVerifier(uint256)(address)" "$protocol_version_raw" --rpc-url "$SEPOLIA_RPC_URL")
is_testnet_verifier=$(cast call "$testnet_verifier" "IS_TESTNET_VERIFIER()(bool)" --rpc-url "$SEPOLIA_RPC_URL")
validator_timelock=$(cast call "$ctm" "validatorTimelockPostV29()(address)" --rpc-url "$SEPOLIA_RPC_URL")
genesis_sha256=$(sha256sum /runtime/chain/genesis.json | cut -d' ' -f1)
genesis_root=$(jq -r '.genesis_root // .genesisRoot // .root // empty' /runtime/chain/genesis.json)

if ! jq -e '
  .protocol_semantic_version.major == 0 and
  .protocol_semantic_version.minor == 31 and
  .protocol_semantic_version.patch == 0 and
  (.genesis_root | type == "string" and length == 66)
' /runtime/chain/genesis.json >/dev/null; then
  echo "Generated genesis is not protocol v0.31.0 or has no genesis root" >&2
  exit 1
fi

stored_batch_zero=$(cast call "$ctm" "storedBatchZero()(bytes32)" --rpc-url "$SEPOLIA_RPC_URL")
diamond_stored_batch_zero=$(cast call "$diamond" "storedBatchHash(uint256)(bytes32)" 0 --rpc-url "$SEPOLIA_RPC_URL")
expected_stored_batch_zero=$(
  cast abi-encode \
    "f((uint64,bytes32,uint64,uint256,bytes32,bytes32,bytes32,uint256,bytes32))" \
    "(0,${genesis_root},0,0,0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0,0x0000000000000000000000000000000000000000000000000000000000000001)" |
    cast keccak
)
if [[ "$stored_batch_zero" != "$diamond_stored_batch_zero" ||
      "$stored_batch_zero" != "$expected_stored_batch_zero" ]]; then
  echo "The CTM/diamond genesis batch does not commit to the generated v31 genesis root" >&2
  exit 1
fi

transactions='[]'
if [[ -s /runtime/chain/out/executed/transactions.json ]]; then
  transactions=$(jq '[.transactions[].tx_hash]' /runtime/chain/out/executed/transactions.json)
fi

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson l1_chain_id 11155111 \
  --argjson l2_chain_id "$L2_CHAIN_ID" \
  --arg protocol_version "0.31.0" \
  --arg eth_asset_id "$ZK_TOKEN_ASSET_ID" \
  --argjson protocol_version_raw "$protocol_version_raw" \
  --arg zk_deployer_commit "$ZK_DEPLOYER_COMMIT" \
  --arg protocol_commit "$PROTOCOL_COMMIT" \
  --arg bridgehub "$bridgehub" \
  --arg ctm "$ctm" \
  --arg bytecode_supplier "$supplier" \
  --arg governance "$governance" \
  --arg rollup_validator "$rollup_validator" \
  --arg blob_validator "$blob_validator" \
  --arg diamond "$diamond" \
  --arg chain_admin "$chain_admin" \
  --arg testnet_verifier "$testnet_verifier" \
  --argjson is_testnet_verifier "$is_testnet_verifier" \
  --arg validator_timelock "$validator_timelock" \
  --arg stored_batch_zero "$stored_batch_zero" \
  --arg genesis_sha256 "$genesis_sha256" \
  --arg genesis_root "$genesis_root" \
  --arg operator_commit "$(wallet_address "$OPERATOR_COMMIT_PRIVATE_KEY")" \
  --arg operator_prove "$(wallet_address "$OPERATOR_PROVE_PRIVATE_KEY")" \
  --arg operator_execute "$(wallet_address "$OPERATOR_EXECUTE_PRIVATE_KEY")" \
  --argjson deployment_transactions "$transactions" \
  '{
    generated_at: $generated_at,
    environment: "sandbox",
    l1_chain_id: $l1_chain_id,
    l2_chain_id: $l2_chain_id,
    protocol_version: $protocol_version,
    protocol_version_raw: $protocol_version_raw,
    assets: {
      base_token: "ETH",
      protocol_fee_asset: "ETH",
      eth_ntv_asset_id: $eth_asset_id
    },
    sources: {
      zk_deployer: $zk_deployer_commit,
      protocol: $protocol_commit
    },
    l1_contracts: {
      bridgehub: $bridgehub,
      chain_type_manager: $ctm,
      bytecode_supplier: $bytecode_supplier,
      governance: $governance,
      rollup_da_validator: $rollup_validator,
      blob_da_validator: $blob_validator,
      testnet_verifier: $testnet_verifier,
      is_testnet_verifier: $is_testnet_verifier,
      validator_timelock: $validator_timelock
    },
    chain_contracts: {
      diamond: $diamond,
      chain_admin: $chain_admin
    },
    operator_addresses: {
      commit: $operator_commit,
      prove: $operator_prove,
      execute: $operator_execute
    },
    genesis: {
      sha256: $genesis_sha256,
      root: $genesis_root,
      stored_batch_zero: $stored_batch_zero
    },
    deployment_transactions: $deployment_transactions,
    security: {
      proofs: "fake",
      verifier: "testnet",
      production_safe: false
    }
  }' >/public/manifest.json.tmp
mv /public/manifest.json.tmp /public/manifest.json
chmod 0644 /public/manifest.json

echo "Sepolia ecosystem deployed and public manifest written to /public/manifest.json"
