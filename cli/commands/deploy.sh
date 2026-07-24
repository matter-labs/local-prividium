#!/usr/bin/env bash

prividium_deploy_usage() {
  cat <<'EOF'
Start and validate the prepared Prividium sandbox services.

Usage:
  ./cli/prividium deploy [--profile sandbox]

Options:
  --profile sandbox  Sandbox profile to deploy (default: sandbox)
  -h, --help         Show this help

Deploy requires a completed protocol broadcast and all six public sandbox DNS
names. It starts the prebuilt default stack and validates its public endpoints.
It performs no service-wallet bridge.
EOF
}

prividium_deploy() {
  local hostname
  local profile="sandbox"
  local show_help="false"
  local unresolved=()

  while (( $# )); do
    case "$1" in
      -h|--help)
        show_help="true"
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
      -*)
        prividium_fail "unknown deploy option: $1"
        ;;
      *)
        prividium_fail "unexpected deploy argument: $1"
        ;;
    esac
  done

  prividium_validate_profile "$profile"
  if [[ "$show_help" == "true" ]]; then
    prividium_deploy_usage
    return
  fi

  prividium_require_commands "sandbox deployment" docker jq curl
  prividium_load_runtime_environment

  printf "Prividium sandbox deployment\n"
  printf "Profile: %s\n" "$profile"
  printf "Network: Ethereum Sepolia (11155111)\n"
  printf "L2 chain ID: %s\n\n" "$L2_CHAIN_ID"

  printf "Checking public DNS...\n"
  for hostname in \
    "app.${SANDBOX_DOMAIN}" \
    "admin.${SANDBOX_DOMAIN}" \
    "api.${SANDBOX_DOMAIN}" \
    "explorer.${SANDBOX_DOMAIN}" \
    "explorer-api.${SANDBOX_DOMAIN}" \
    "idp.${SANDBOX_DOMAIN}"; do
    if prividium_dns_resolves "$hostname"; then
      printf "✓ %s\n" "$hostname"
    else
      printf "✗ %s\n" "$hostname"
      unresolved+=("$hostname")
    fi
  done

  if (( ${#unresolved[@]} )); then
    printf "\nACTION REQUIRED\n\n"
    printf "Configure and verify all public sandbox DNS names before deployment:\n"
    printf "  %s\n" "${unresolved[@]}"
    printf "\nThen rerun: ./cli/prividium deploy\n"
    exit 2
  fi

  printf "\nStarting the focused core stack.\n"
  printf "Settlement operators may submit normal Sepolia transactions after startup.\n"
  SANDBOX_ENV_FILE="$PRIVIDIUM_RUNTIME_ENVIRONMENT" \
    "${PRIVIDIUM_REPO_ROOT}/tools/deploy"
}
