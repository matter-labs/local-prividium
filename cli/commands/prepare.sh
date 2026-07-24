#!/usr/bin/env bash

prividium_prepare_usage() {
  cat <<'EOF'
Prepare a Prividium evaluation sandbox without broadcasting transactions.

Usage:
  ./cli/prividium prepare [--profile sandbox]

Options:
  --profile sandbox  Sandbox profile to prepare (default: sandbox)
  -h, --help         Show this help

Prepare creates the protected runtime, simulates protocol deployment, pulls
and builds the default stack, and runs focused pre-broadcast readiness. It
writes local protected artifacts but submits no Sepolia transactions.
EOF
}

prividium_prepare() {
  local elapsed
  local profile="sandbox"
  local show_help="false"
  local started_at=$SECONDS

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
        prividium_fail "unknown prepare option: $1"
        ;;
      *)
        prividium_fail "unexpected prepare argument: $1"
        ;;
    esac
  done

  prividium_validate_profile "$profile"
  if [[ "$show_help" == "true" ]]; then
    prividium_prepare_usage
    return
  fi

  if [[ -e "${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json" ||
        -L "${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json" ]]; then
    prividium_fail \
      "a public protocol manifest already exists; use ./cli/prividium deploy for this sandbox"
  fi

  prividium_require_encrypted_environment
  prividium_resolve_age_identity
  prividium_require_runtime_directory
  prividium_require_commands \
    "sandbox preparation" sops docker cast jq curl openssl

  mkdir -p "${PRIVIDIUM_RUNTIME_DIR}/chain"
  chmod 0700 "${PRIVIDIUM_RUNTIME_DIR}/chain"

  printf "Prividium sandbox preparation\n"
  printf "Profile: %s\n" "$profile"
  printf "Network: Ethereum Sepolia (11155111)\n\n"

  printf "[1/5] Creating the protected runtime\n"
  RUNTIME_DIR="$PRIVIDIUM_RUNTIME_DIR" \
    "${PRIVIDIUM_REPO_ROOT}/tools/decrypt-secrets" \
      "$PRIVIDIUM_ENCRYPTED_ENVIRONMENT"
  prividium_load_runtime_environment

  printf "\n[2/5] Building and simulating the protocol deployment\n"
  PRIVIDIUM_HOST_UID="$(id -u)" \
    PRIVIDIUM_HOST_GID="$(id -g)" \
    SANDBOX_ENV_FILE="$PRIVIDIUM_RUNTIME_ENVIRONMENT" \
    "${PRIVIDIUM_REPO_ROOT}/tools/chain-bootstrap" prepare

  for artifact in \
    "${PRIVIDIUM_RUNTIME_DIR}/chain/out/manifest.json" \
    "${PRIVIDIUM_RUNTIME_DIR}/chain/out/preparation.json"; do
    if [[ ! -f "$artifact" || ! -s "$artifact" || ! -r "$artifact" ]]; then
      prividium_fail \
        "protocol preparation did not produce a readable artifact: ${artifact}"
    fi
  done

  printf "\n[3/5] Pulling locked default images\n"
  (
    cd "$PRIVIDIUM_REPO_ROOT"
    docker compose -f "${PRIVIDIUM_REPO_ROOT}/compose/compose.yaml" \
      --env-file "$PRIVIDIUM_RUNTIME_ENVIRONMENT" \
      pull --ignore-buildable
  )

  printf "\n[4/5] Building the default stack\n"
  (
    cd "$PRIVIDIUM_REPO_ROOT"
    # chain-preflight reuses the immutable chain-bootstrap image built in step 2.
    docker compose -f "${PRIVIDIUM_REPO_ROOT}/compose/compose.yaml" \
      --env-file "$PRIVIDIUM_RUNTIME_ENVIRONMENT" \
      build operator-balance-exporter
  )

  printf "\n[5/5] Checking pre-broadcast readiness\n"
  SANDBOX_ENV_FILE="$PRIVIDIUM_RUNTIME_ENVIRONMENT" \
    SANDBOX_SECRETS_FILE="$PRIVIDIUM_ENCRYPTED_ENVIRONMENT" \
    "${PRIVIDIUM_REPO_ROOT}/tools/deployment-readiness"

  elapsed=$((SECONDS - started_at))
  printf "\nPREPARATION COMPLETE\n\n"
  printf "Protected artifacts\n\n"
  printf "%-24s %s\n" \
    "Runtime environment" \
    "/etc/prividium/runtime/sandbox.env"
  printf "%-24s %s\n" \
    "Prepared manifest" \
    "/etc/prividium/runtime/chain/out/manifest.json"
  printf "%-24s %s\n" \
    "Preparation provenance" \
    "/etc/prividium/runtime/chain/out/preparation.json"
  printf "\nElapsed: %dm %02ds\n" "$((elapsed / 60))" "$((elapsed % 60))"
  printf "No Sepolia transactions were submitted.\n"
  printf "Next: ./cli/prividium broadcast\n"
}
