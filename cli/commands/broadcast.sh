#!/usr/bin/env bash

prividium_broadcast_usage() {
  cat <<'EOF'
Broadcast a prepared Prividium protocol deployment to Ethereum Sepolia.

Usage:
  ./cli/prividium broadcast [--profile sandbox]

Options:
  --profile sandbox  Sandbox profile to broadcast (default: sandbox)
  -h, --help         Show this help

This command submits irreversible Sepolia transactions. Interactive execution
requires the L2 chain ID. Non-interactive execution requires the exact
CONFIRM_BROADCAST=BROADCAST_SEPOLIA_<L2_CHAIN_ID> environment value.
EOF
}

prividium_broadcast() {
  local deployer_address
  local attempt
  local attempt_tmp
  local expected_confirmation
  local manifest_digest
  local preparation
  local preparation_timestamp
  local prepared_manifest
  local profile="sandbox"
  local show_help="false"
  local status
  local typed

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
        prividium_fail "unknown broadcast option: $1"
        ;;
      *)
        prividium_fail "unexpected broadcast argument: $1"
        ;;
    esac
  done

  prividium_validate_profile "$profile"
  if [[ "$show_help" == "true" ]]; then
    prividium_broadcast_usage
    return
  fi

  prividium_require_encrypted_environment
  prividium_resolve_age_identity
  prividium_require_commands \
    "protocol broadcast" sops docker cast jq curl openssl
  prividium_load_runtime_environment

  attempt="${PRIVIDIUM_RUNTIME_DIR}/reports/broadcast-attempt.json"
  prepared_manifest="${PRIVIDIUM_RUNTIME_DIR}/chain/out/manifest.json"
  preparation="${PRIVIDIUM_RUNTIME_DIR}/chain/out/preparation.json"
  if [[ ! -s "$prepared_manifest" || ! -r "$prepared_manifest" ||
        ! -s "$preparation" || ! -r "$preparation" ]]; then
    prividium_fail \
      "prepared protocol artifacts are missing; run ./cli/prividium prepare"
  fi
  if [[ -s "${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json" ]]; then
    if jq -e --argjson chain_id "$L2_CHAIN_ID" \
      '.l1_chain_id == 11155111 and .l2_chain_id == $chain_id' \
      "${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json" >/dev/null; then
      printf 'Protocol broadcast is already complete for L2 chain %s.\n' "$L2_CHAIN_ID"
      printf 'Next: ./cli/prividium deploy\n'
      return
    fi
    prividium_fail "the existing public manifest belongs to a different deployment"
  fi
  if [[ -e "$attempt" || -L "$attempt" ]]; then
    if [[ ! -f "$attempt" || ! -s "$attempt" ]] ||
       ! jq -e --argjson chain_id "$L2_CHAIN_ID" \
         '.schema_version == 1 and .l2_chain_id == $chain_id and .status == "STARTED"' \
         "$attempt" >/dev/null; then
      prividium_fail "broadcast attempt evidence is invalid; preserve runtime state for manual review"
    fi
    printf 'BROADCAST REVIEW REQUIRED\n\n' >&2
    printf 'An approved Sepolia broadcast previously started without producing the public manifest.\n' >&2
    printf 'Do not rerun broadcast or discard /etc/prividium/runtime/chain.\n' >&2
    printf 'Inspect protected transaction state and the prior terminal output.\n' >&2
    return 1
  fi

  printf "Prividium sandbox protocol broadcast\n"
  printf "Profile: %s\n\n" "$profile"
  printf "Running focused pre-broadcast readiness...\n\n"
  SANDBOX_ENV_FILE="$PRIVIDIUM_RUNTIME_ENVIRONMENT" \
    SANDBOX_SECRETS_FILE="$PRIVIDIUM_ENCRYPTED_ENVIRONMENT" \
    "${PRIVIDIUM_REPO_ROOT}/tools/deployment-readiness"

  source "${PRIVIDIUM_REPO_ROOT}/tools/lib/sandbox-roles.sh"
  deployer_address=$(sandbox_private_key_address "$L1_DEPLOYER_PRIVATE_KEY")
  manifest_digest=$(prividium_sha256_file "$prepared_manifest")
  preparation_timestamp=$(
    jq -er '
      .generated_at |
      select(
        type == "string" and
        test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
      )
    ' "$preparation"
  )
  expected_confirmation="BROADCAST_SEPOLIA_${L2_CHAIN_ID}"

  printf "\nBroadcast authorization\n\n"
  printf "%-22s %s\n" "Profile" "$profile"
  printf "%-22s %s\n" "Network" "Ethereum Sepolia (11155111)"
  printf "%-22s %s\n" "Sandbox domain" "$SANDBOX_DOMAIN"
  printf "%-22s %s\n" "L2 chain ID" "$L2_CHAIN_ID"
  printf "%-22s %s\n" "Ecosystem deployer" "$deployer_address"
  printf "%-22s %s\n" "Prepared at" "$preparation_timestamp"
  printf "%-22s %s\n" "Prepared manifest" "$manifest_digest"
  printf "\nThis creates irreversible protocol contracts on Ethereum Sepolia.\n"

  if [[ "${CONFIRM_BROADCAST:-}" != "$expected_confirmation" ]]; then
    if [[ ! -t 0 ]]; then
      echo "BROADCAST BLOCKED" >&2
      echo "Non-interactive execution requires:" >&2
      echo "  CONFIRM_BROADCAST=${expected_confirmation} ./cli/prividium broadcast" >&2
      exit 1
    fi
    read -r -p "Type the L2 chain ID to broadcast: " typed
    if [[ "$typed" != "$L2_CHAIN_ID" ]]; then
      printf "Broadcast cancelled; no protocol transactions were submitted.\n"
      exit 2
    fi
    export CONFIRM_BROADCAST="$expected_confirmation"
  fi

  mkdir -p "$(dirname "$attempt")"
  attempt_tmp=$(mktemp "${attempt}.tmp.XXXXXX")
  jq -n \
    --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson l2_chain_id "$L2_CHAIN_ID" \
    --arg prepared_manifest_sha256 "$manifest_digest" \
    '{
      schema_version: 1,
      status: "STARTED",
      started_at: $started_at,
      l1_chain_id: 11155111,
      l2_chain_id: $l2_chain_id,
      prepared_manifest_sha256: $prepared_manifest_sha256
    }' >"$attempt_tmp"
  install -m 0600 "$attempt_tmp" "$attempt"
  rm -f -- "$attempt_tmp"

  printf "\nBroadcasting the prepared protocol deployment...\n"
  set +e
  PRIVIDIUM_HOST_UID="$(id -u)" \
    PRIVIDIUM_HOST_GID="$(id -g)" \
    SANDBOX_ENV_FILE="$PRIVIDIUM_RUNTIME_ENVIRONMENT" \
    "${PRIVIDIUM_REPO_ROOT}/tools/chain-bootstrap" broadcast
  status=$?
  set -e
  if (( status != 0 )); then
    printf "\nBROADCAST INCOMPLETE — MANUAL REVIEW REQUIRED\n\n" >&2
    printf "A Sepolia transaction may have been submitted.\n" >&2
    printf "Do not rerun broadcast, regenerate identities, or discard:\n" >&2
    printf "  /etc/prividium/runtime/chain\n" >&2
    printf "Preserve the complete terminal output and inspect the recorded transaction state.\n" >&2
    return "$status"
  fi

  if [[ ! -s "${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json" ]] ||
     [[ "$(jq -r '.l2_chain_id // empty' \
       "${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json")" != "$L2_CHAIN_ID" ]]; then
    prividium_fail \
      "broadcast returned successfully without a matching public manifest"
  fi

  attempt_tmp=$(mktemp "${attempt}.tmp.XXXXXX")
  jq \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg public_manifest_sha256 "$(prividium_sha256_file "${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json")" \
    '.status = "COMPLETE" |
     .completed_at = $completed_at |
     .public_manifest_sha256 = $public_manifest_sha256' \
    "$attempt" >"$attempt_tmp"
  install -m 0600 "$attempt_tmp" "$attempt"
  rm -f -- "$attempt_tmp"

  printf "\nBROADCAST COMPLETE\n\n"
  printf "Public protocol manifest  deployment/public/manifest.json\n"
  printf "Next: ./cli/prividium deploy\n"
}
