#!/usr/bin/env bash

sandbox_role_ids=(
  l1_deployer
  ecosystem_governor
  chain_owner
  operator_commit
  operator_prove
  operator_execute
  bridge_sponsor
  fee_account
  bundler
  entrypoint_deployer
  sso_deployer
  auth_server
  auth_server_admin
  institutional_demo_deployer
)

sandbox_deployment_role_ids=(
  l1_deployer
  ecosystem_governor
  chain_owner
)

sandbox_operator_role_ids=(
  operator_commit
  operator_prove
  operator_execute
)

sandbox_funded_role_ids=(
  "${sandbox_deployment_role_ids[@]}"
  "${sandbox_operator_role_ids[@]}"
)

sandbox_funding_role_group() {
  case "$1" in
    l1_deployer|ecosystem_governor|chain_owner)
      echo "deployment"
      ;;
    operator_commit|operator_prove|operator_execute)
      echo "operators"
      ;;
    *)
      echo "Role is not part of a funding group: $1" >&2
      return 1
      ;;
  esac
}

sandbox_role_key_name() {
  case "$1" in
    l1_deployer) echo L1_DEPLOYER_PRIVATE_KEY ;;
    ecosystem_governor) echo ECOSYSTEM_GOVERNOR_PRIVATE_KEY ;;
    chain_owner) echo CHAIN_OWNER_PRIVATE_KEY ;;
    operator_commit) echo OPERATOR_COMMIT_PRIVATE_KEY ;;
    operator_prove) echo OPERATOR_PROVE_PRIVATE_KEY ;;
    operator_execute) echo OPERATOR_EXECUTE_PRIVATE_KEY ;;
    bridge_sponsor) echo BRIDGE_SPONSOR_PRIVATE_KEY ;;
    fee_account) echo FEE_ACCOUNT_PRIVATE_KEY ;;
    bundler) echo BUNDLER_PRIVATE_KEY ;;
    entrypoint_deployer) echo ENTRYPOINT_DEPLOYER_PRIVATE_KEY ;;
    sso_deployer) echo SSO_DEPLOYER_PRIVATE_KEY ;;
    auth_server) echo AUTH_SERVER_PRIVATE_KEY ;;
    auth_server_admin) echo AUTH_SERVER_ADMIN_PRIVATE_KEY ;;
    institutional_demo_deployer) echo INSTITUTIONAL_DEMO_DEPLOYER_PRIVATE_KEY ;;
    *)
      echo "Unknown sandbox role: $1" >&2
      return 1
      ;;
  esac
}

sandbox_role_label() {
  case "$1" in
    l1_deployer) echo "Ecosystem deployer" ;;
    ecosystem_governor) echo "Ecosystem governor" ;;
    chain_owner) echo "Chain owner" ;;
    operator_commit) echo "Commit operator" ;;
    operator_prove) echo "Prove operator" ;;
    operator_execute) echo "Execute operator" ;;
    bridge_sponsor) echo "Sandbox funding wallet" ;;
    fee_account) echo "Fee account" ;;
    bundler) echo "Bundler" ;;
    entrypoint_deployer) echo "EntryPoint deployer" ;;
    sso_deployer) echo "SSO contract deployer" ;;
    auth_server) echo "SSO auth server" ;;
    auth_server_admin) echo "SSO administrative wallet" ;;
    institutional_demo_deployer) echo "Institutional demo deployer" ;;
    *)
      echo "Unknown sandbox role: $1" >&2
      return 1
      ;;
  esac
}

sandbox_role_purpose() {
  case "$1" in
    l1_deployer) echo "Deploys the dedicated Sepolia ecosystem and chain contracts." ;;
    ecosystem_governor) echo "Approves ecosystem governance actions during bootstrap." ;;
    chain_owner) echo "Approves chain administration actions during bootstrap." ;;
    operator_commit) echo "Submits L1 batch commitments." ;;
    operator_prove) echo "Submits L1 proof transactions." ;;
    operator_execute) echo "Executes settled L1 batches." ;;
    bridge_sponsor) echo "The only address the customer funds; distributes L1 ETH and submits the acceptance self-deposit." ;;
    fee_account) echo "Receives protocol fees and does not submit L1 transactions." ;;
    bundler) echo "Optional SSO transaction bundler." ;;
    entrypoint_deployer) echo "Optional one-time EntryPoint deployment wallet." ;;
    sso_deployer) echo "Optional SSO contract deployment wallet." ;;
    auth_server) echo "Optional SSO auth-server transaction wallet." ;;
    auth_server_admin) echo "Optional SSO administrative permission wallet." ;;
    institutional_demo_deployer) echo "Optional institutional-demo deployment wallet." ;;
    *)
      echo "Unknown sandbox role: $1" >&2
      return 1
      ;;
  esac
}

sandbox_role_scope() {
  case "$1" in
    bundler|entrypoint_deployer|sso_deployer|auth_server|auth_server_admin|institutional_demo_deployer)
      echo "Optional"
      ;;
    *)
      echo "Core"
      ;;
  esac
}

sandbox_private_key_address() {
  local private_key="${1:-}"
  local private_key_hex
  local curve_order="fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"
  local der_hex
  local der_bytes=""
  local public_key_hex
  local public_key_bytes=""
  local public_key_hash
  local address
  local LC_ALL=C

  if [[ ! "$private_key" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "Private key must be a 32-byte hexadecimal value" >&2
    return 1
  fi

  private_key_hex=$(
    printf "%s" "${private_key#0x}" | tr '[:upper:]' '[:lower:]'
  )
  if [[ "$private_key_hex" =~ ^0+$ ||
        "$private_key_hex" == "$curve_order" ||
        "$private_key_hex" > "$curve_order" ]]; then
    echo "Private key is not a valid secp256k1 scalar" >&2
    return 1
  fi

  der_hex="302e0201010420${private_key_hex}a00706052b8104000a"
  while [[ -n "$der_hex" ]]; do
    der_bytes="${der_bytes}\\x${der_hex:0:2}"
    der_hex="${der_hex:2}"
  done

  if ! public_key_hex=$(
    set -o pipefail
    printf "%b" "$der_bytes" |
      openssl ec -inform DER -pubout -outform DER \
        -conv_form uncompressed 2>/dev/null |
      tail -c 65 |
      od -An -v -tx1 |
      tr -d '[:space:]'
  ); then
    echo "Private key is not a valid secp256k1 scalar" >&2
    return 1
  fi
  if [[ ! "$public_key_hex" =~ ^04[0-9a-fA-F]{128}$ ]]; then
    echo "Could not derive an uncompressed secp256k1 public key" >&2
    return 1
  fi

  public_key_hex="${public_key_hex:2}"
  while [[ -n "$public_key_hex" ]]; do
    public_key_bytes="${public_key_bytes}\\x${public_key_hex:0:2}"
    public_key_hex="${public_key_hex:2}"
  done
  if ! public_key_hash=$(
    printf "%b" "$public_key_bytes" | cast keccak 2>/dev/null
  ); then
    echo "Could not hash the secp256k1 public key" >&2
    return 1
  fi
  if [[ ! "$public_key_hash" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "Could not derive an Ethereum address from the private key" >&2
    return 1
  fi

  address="0x${public_key_hash: -40}"
  cast to-check-sum-address "$address"
}

sandbox_load_role_addresses() {
  local addresses=()
  local address
  local cache_name
  local index
  local key_name
  local private_key
  local role

  for role in "${sandbox_role_ids[@]}"; do
    key_name=$(sandbox_role_key_name "$role")
    private_key="${!key_name:-}"
    if [[ -z "$private_key" ]]; then
      echo "Missing ${key_name} for role ${role}" >&2
      return 1
    fi
    address=$(sandbox_private_key_address "$private_key") || return 1
    addresses+=("$address")
  done

  for ((index = 0; index < ${#sandbox_role_ids[@]}; index++)); do
    cache_name="sandbox_cached_address_${sandbox_role_ids[index]}"
    printf -v "$cache_name" "%s" "${addresses[index]}"
  done
}

sandbox_role_address() {
  local role="$1"
  local key_name
  local private_key
  local cache_name="sandbox_cached_address_${role}"
  local cached_address="${!cache_name:-}"

  if [[ -n "$cached_address" ]]; then
    printf "%s\n" "$cached_address"
    return
  fi

  key_name=$(sandbox_role_key_name "$role")
  private_key="${!key_name:-}"
  if [[ -z "$private_key" ]]; then
    echo "Missing ${key_name} for role ${role}" >&2
    return 1
  fi
  sandbox_private_key_address "$private_key"
}

sandbox_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

sandbox_lowercase() {
  tr '[:upper:]' '[:lower:]'
}

sandbox_role_fingerprint() {
  local role
  local address
  for role in "${sandbox_role_ids[@]}"; do
    address=$(sandbox_role_address "$role")
    printf "%s=%s\n" "$role" "$(printf "%s" "$address" | sandbox_lowercase)"
  done | sandbox_sha256
}

sandbox_validate_distinct_roles() {
  local addresses
  local role
  local address
  addresses=$(mktemp)
  for role in "${sandbox_role_ids[@]}"; do
    address=$(sandbox_role_address "$role")
    if [[ ! "$address" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
      echo "Role ${role} produced an invalid address: ${address}" >&2
      rm -f "$addresses"
      return 1
    fi
    printf "%s\n" "$(printf "%s" "$address" | sandbox_lowercase)" >>"$addresses"
  done
  if [[ "$(sort -u "$addresses" | wc -l | tr -d ' ')" != "${#sandbox_role_ids[@]}" ]]; then
    echo "Every generated sandbox role must use a distinct private key" >&2
    rm -f "$addresses"
    return 1
  fi
  rm -f "$addresses"
}
