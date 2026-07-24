#!/usr/bin/env bash

source "${PRIVIDIUM_REPO_ROOT}/tools/lib/sandbox-roles.sh"

prividium_fund_usage() {
  cat <<'EOF'
Fund the identities required for protocol deployment.

Usage:
  ./cli/prividium fund [deployment|operators] [--profile sandbox]
  ./cli/prividium fund --list

Scopes:
  deployment  Ecosystem deployer, ecosystem governor, and chain owner
  operators   Commit, prove, and execute settlement operators
  default     All deployment and operator identities

Options:
  --list             Explain funding groups and roles without making RPC calls
  --profile sandbox  Sandbox profile to fund (default: sandbox)
  -h, --help         Show this help
EOF
}

prividium_fund_list() {
  local role
  local group

  printf "Prividium sandbox funding groups\n\n"
  printf "%-12s %-22s %-22s %s\n" "GROUP" "ROLE" "ID" "PURPOSE"
  for role in "${sandbox_funded_role_ids[@]}"; do
    group=$(sandbox_funding_role_group "$role")
    printf "%-12s %-22s %-22s %s\n" \
      "$group" \
      "$(sandbox_role_label "$role")" \
      "$role" \
      "$(sandbox_role_purpose "$role")"
  done
  printf "\nFunding source\n\n"
  printf "Customers fund one address: the Sandbox funding wallet.\n"
  printf "./cli/prividium fund distributes its confirmed Sepolia ETH to the selected roles.\n"
}

prividium_fund() {
  local profile="sandbox"
  local scope="all"
  local scope_set="false"
  local show_help="false"
  local show_list="false"

  while (( $# )); do
    case "$1" in
      -h|--help)
        show_help="true"
        shift
        ;;
      --list)
        show_list="true"
        shift
        ;;
      --profile)
        if (( $# < 2 )); then
          prividium_fail "--profile requires a value"
        fi
        profile="$2"
        shift 2
        ;;
      --profile=*)
        profile="${1#--profile=}"
        shift
        ;;
      deployment|operators)
        if [[ "$scope_set" == "true" ]]; then
          prividium_fail "fund accepts at most one scope"
        fi
        scope="$1"
        scope_set="true"
        shift
        ;;
      -*)
        prividium_fail "unknown fund option: $1"
        ;;
      *)
        prividium_fail "unexpected fund argument: $1"
        ;;
    esac
  done

  prividium_validate_profile "$profile"
  if [[ "$show_help" == "true" ]]; then
    prividium_fund_usage
    return
  fi
  if [[ "$show_list" == "true" && "$scope_set" == "true" ]]; then
    prividium_fail "--list cannot be combined with a funding scope"
  fi
  if [[ "$show_list" == "true" ]]; then
    prividium_fund_list
    return
  fi

  prividium_require_encrypted_environment
  prividium_resolve_age_identity
  prividium_require_commands "sandbox funding" sops cast jq openssl

  SANDBOX_SECRETS_FILE="$PRIVIDIUM_ENCRYPTED_ENVIRONMENT" \
    FUNDING_TARGETS_FILE="${PRIVIDIUM_REPO_ROOT}/deployment/funding-targets.json" \
    PUBLIC_MANIFEST_PATH="${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json" \
    "${PRIVIDIUM_REPO_ROOT}/tools/funding-reconcile" "$scope"
}
