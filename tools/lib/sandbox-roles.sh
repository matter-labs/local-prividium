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
  watchdog
  bundler
  entrypoint_deployer
  sso_deployer
  auth_server
  auth_server_admin
  institutional_demo_deployer
)

sandbox_funded_role_ids=(
  l1_deployer
  ecosystem_governor
  chain_owner
  operator_commit
  operator_prove
  operator_execute
)

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
    watchdog) echo WATCHDOG_PRIVATE_KEY ;;
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
    watchdog) echo "Watchdog" ;;
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
    bridge_sponsor) echo "The only address the customer funds; distributes L1 ETH and funds L2 services." ;;
    fee_account) echo "Receives protocol fees and does not submit L1 transactions." ;;
    watchdog) echo "Runs the core active health transactions on L2." ;;
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

sandbox_role_address() {
  local role="$1"
  local key_name
  local private_key
  key_name=$(sandbox_role_key_name "$role")
  private_key="${!key_name:-}"
  if [[ -z "$private_key" ]]; then
    echo "Missing ${key_name} for role ${role}" >&2
    return 1
  fi
  cast wallet address --private-key "$private_key"
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
