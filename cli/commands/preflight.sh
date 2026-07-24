#!/usr/bin/env bash

prividium_preflight_usage() {
  cat <<'EOF'
Check whether the initialized and funded sandbox can advance to preparation.

Usage:
  ./cli/prividium preflight [--profile sandbox]

Options:
  --profile sandbox  Sandbox profile to check (default: sandbox)
  -h, --help         Show this help

Preflight is non-interactive and read-only. It does not create the decrypted
runtime, build or pull images, prepare protocol artifacts, submit transactions,
or authorize a protocol broadcast.
EOF
}

prividium_preflight() {
  local profile="sandbox"
  local show_help="false"

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
        prividium_fail "unknown preflight option: $1"
        ;;
      *)
        prividium_fail "unexpected preflight argument: $1"
        ;;
    esac
  done

  prividium_validate_profile "$profile"
  if [[ "$show_help" == "true" ]]; then
    prividium_preflight_usage
    return
  fi

  prividium_require_encrypted_environment
  prividium_resolve_age_identity
  if ! command -v sops >/dev/null; then
    printf "Prividium sandbox preflight\n"
    printf "Profile: sandbox\n\n"
    printf "ACTION REQUIRED\n\n"
    printf "1. Install the missing host tool: sops.\n\n"
    printf "Then rerun: ./cli/prividium preflight\n"
    return 2
  fi

  SANDBOX_SECRETS_FILE="$PRIVIDIUM_ENCRYPTED_ENVIRONMENT" \
    FUNDING_TARGETS_FILE="${PRIVIDIUM_REPO_ROOT}/deployment/funding-targets.json" \
    PUBLIC_MANIFEST_PATH="${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json" \
    ROLE_REPORT_PATH="${PRIVIDIUM_REPO_ROOT}/deployment/public/roles.md" \
    CHAINLIST_URL="https://chainid.network/chains.json" \
    "${PRIVIDIUM_REPO_ROOT}/tools/preflight"
}
