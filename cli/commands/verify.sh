#!/usr/bin/env bash

prividium_verify_usage() {
  cat <<'EOF'
Run the final Prividium product smoke.

Usage:
  ./cli/prividium verify [--profile sandbox]

The command first performs a non-admin OIDC authorization-code/PKCE login and
an authenticated eth_chainId call. It then requires explicit authorization for
a minimal Sepolia-to-L2 self-deposit from the generated funding wallet. READY
is written after the authenticated L2 receipt and Explorer indexing succeed.

Non-interactive execution requires the exact
CONFIRM_CANARY=CANARY_SEPOLIA_<L2_CHAIN_ID> environment value.
EOF
}

prividium_verify() {
  local canary_address
  local deadline
  local evidence="${PRIVIDIUM_REPO_ROOT}/deployment/public/happy-path.json"
  local expected_confirmation
  local explorer_result
  local l1_transaction_hash
  local l2_transaction_hash
  local manifest="${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json"
  local profile="sandbox"
  local protected_evidence="${PRIVIDIUM_RUNTIME_DIR}/reports/happy-path.json"
  local canary_attempt="${PRIVIDIUM_RUNTIME_DIR}/chain/canary-attempt.json"
  local canary_submission="${PRIVIDIUM_RUNTIME_DIR}/chain/canary-submission.json"
  local receipt_result
  local smoke_result
  local started_at
  local started_seconds=$SECONDS
  local typed

  while (( $# )); do
    case "$1" in
      -h|--help)
        prividium_verify_usage
        return
        ;;
      --profile)
        (( $# >= 2 )) || prividium_fail "--profile requires a value"
        profile="$2"
        shift 2
        ;;
      --profile=*)
        profile="${1#--profile=}"
        shift
        ;;
      *)
        prividium_fail "unexpected verify argument: $1"
        ;;
    esac
  done
  prividium_validate_profile "$profile"

  prividium_require_commands "happy-path verification" cast docker jq python3
  prividium_load_runtime_environment
  if [[ ! -s "$manifest" ]] || ! jq -e --argjson chain_id "$L2_CHAIN_ID" '
    .l2_chain_id == $chain_id and
    .data_availability.mode == "no_da" and
    .data_availability.type == "validium" and
    .transaction_filterer.deposits_allowed == true
  ' "$manifest" >/dev/null; then
    prividium_fail "matching Validium/filterer manifest is missing; complete broadcast first"
  fi
  if [[ ! -s "${PRIVIDIUM_REPO_ROOT}/deployment/public/deployment-summary.md" ]] ||
     ! grep -Fq -- '- Status: **HEALTHY**' \
       "${PRIVIDIUM_REPO_ROOT}/deployment/public/deployment-summary.md"; then
    prividium_fail "healthy core deployment summary is missing; run ./cli/prividium deploy"
  fi
  if [[ -s "$evidence" ]] && jq -e --argjson chain_id "$L2_CHAIN_ID" '
    .status == "READY" and
    .l2_chain_id == $chain_id and
    .authenticated_rpc == true and
    .non_admin_oidc == true and
    .canary_receipt == true and
    .explorer_indexed == true
  ' "$evidence" >/dev/null; then
    printf 'Prividium happy path is already READY.\n\n'
    jq '{status, generated_at, l2_chain_id, canary_address, l1_transaction_hash, l2_transaction_hash}' \
      "$evidence"
    return
  fi

  started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  printf 'Prividium happy-path verification\n'
  printf 'Profile: sandbox (core only)\n'
  printf 'Network: Ethereum Sepolia (11155111)\n'
  printf 'L2 chain ID: %s\n\n' "$L2_CHAIN_ID"
  printf '[1/4] Authenticating a non-admin OIDC user and checking protected RPC\n'
  smoke_result=$("${PRIVIDIUM_REPO_ROOT}/tools/product-smoke")
  jq -e --argjson chain_id "$L2_CHAIN_ID" '
    .authenticated_rpc == true and
    .non_admin == true and
    .l2_chain_id == $chain_id
  ' <<<"$smoke_result" >/dev/null || prividium_fail "authenticated product smoke returned invalid evidence"
  printf '✓ Non-admin OIDC login and authenticated eth_chainId succeeded\n'

  source "${PRIVIDIUM_REPO_ROOT}/tools/lib/sandbox-roles.sh"
  canary_address=$(sandbox_private_key_address "$BRIDGE_SPONSOR_PRIVATE_KEY")
  expected_confirmation="CANARY_SEPOLIA_${L2_CHAIN_ID}"
  if [[ -s "$canary_submission" ]] && jq -e \
    --argjson chain_id "$L2_CHAIN_ID" \
    --arg address "${canary_address,,}" '
      .l1_chain_id == 11155111 and
      .l2_chain_id == $chain_id and
      (.canary_address | ascii_downcase) == $address and
      (.l1_transaction_hash | test("^0x[0-9a-fA-F]{64}$")) and
      (.l2_transaction_hash | test("^0x[0-9a-fA-F]{64}$"))
    ' "$canary_submission" >/dev/null 2>&1; then
    export CONFIRM_CANARY="$expected_confirmation"
    printf '\nResuming the existing acceptance canary; no new approval or submission is required.\n'
  else
    if [[ -e "$canary_attempt" || -L "$canary_attempt" ]]; then
      prividium_fail "an approved canary was interrupted without durable submission evidence; inspect Sepolia state before retrying"
    fi
    printf '\nCanary authorization\n\n'
    printf '%-20s %s\n' "Sender / recipient" "$canary_address"
    printf '%-20s %s\n' "L2 value" "0.000001 ETH"
    printf '%-20s %s\n' "Purpose" "deposit, authenticated receipt, Explorer indexing"
    printf '\nThis submits an irreversible Sepolia testnet transaction.\n'
    if [[ "${CONFIRM_CANARY:-}" != "$expected_confirmation" ]]; then
      if [[ ! -t 0 ]]; then
        printf 'CANARY BLOCKED\n' >&2
        printf 'Non-interactive execution requires:\n' >&2
        printf '  CONFIRM_CANARY=%s ./cli/prividium verify\n' "$expected_confirmation" >&2
        exit 1
      fi
      read -r -p "Type the L2 chain ID to submit the canary: " typed
      if [[ "$typed" != "$L2_CHAIN_ID" ]]; then
        printf 'Canary cancelled; no acceptance transaction was submitted.\n'
        return 2
      fi
      export CONFIRM_CANARY="$expected_confirmation"
    fi
  fi

  printf '\n[2/4] Submitting or resuming the minimal Sepolia-to-L2 canary\n'
  SANDBOX_ENV_FILE="$PRIVIDIUM_RUNTIME_ENVIRONMENT" \
    CONFIRM_CANARY="$expected_confirmation" \
    "${PRIVIDIUM_REPO_ROOT}/tools/canary"
  l1_transaction_hash=$(jq -er '.l1_transaction_hash' "${PRIVIDIUM_RUNTIME_DIR}/chain/canary-submission.json")
  l2_transaction_hash=$(jq -er '.l2_transaction_hash' "${PRIVIDIUM_RUNTIME_DIR}/chain/canary-submission.json")
  printf '✓ Sepolia transaction: %s\n' "$l1_transaction_hash"
  printf '✓ L2 transaction:      %s\n' "$l2_transaction_hash"

  printf '\n[3/4] Waiting for the authenticated L2 receipt\n'
  receipt_result=$("${PRIVIDIUM_REPO_ROOT}/tools/product-smoke" \
    --wait-receipt "$l2_transaction_hash" --timeout 600)
  jq -e '.l2_receipt_status == "success"' <<<"$receipt_result" >/dev/null ||
    prividium_fail "authenticated canary receipt evidence is invalid"
  printf '✓ Canary L2 receipt succeeded\n'

  printf '\n[4/4] Waiting for Block Explorer indexing\n'
  deadline=$((SECONDS + 600))
  while (( SECONDS < deadline )); do
    explorer_result=$(
      docker compose -f "${PRIVIDIUM_REPO_ROOT}/compose/compose.yaml" \
        --env-file "$PRIVIDIUM_RUNTIME_ENVIRONMENT" exec -T postgres \
        /bin/sh -ec \
        'PGPASSWORD="$POSTGRES_PASSWORD" exec psql -U "$POSTGRES_USER" -d "$EXPLORER_DB_NAME" -Atc "$1"' \
        sh "SELECT EXISTS (SELECT 1 FROM \"transactions\" WHERE lower(\"hash\") = lower('${l2_transaction_hash}'));" \
        2>/dev/null || true
    )
    if [[ "$explorer_result" == "t" ]]; then
      break
    fi
    printf 'Waiting for Explorer to index %s...\n' "$l2_transaction_hash"
    sleep 15
  done
  [[ "$explorer_result" == "t" ]] || prividium_fail "Explorer did not index the canary within 10 minutes"
  printf '✓ Explorer indexed the canary transaction\n'

  mkdir -p "$(dirname "$protected_evidence")" "$(dirname "$evidence")"
  jq -n \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg started_at "$started_at" \
    --argjson elapsed_seconds "$((SECONDS - started_seconds))" \
    --argjson l2_chain_id "$L2_CHAIN_ID" \
    --arg canary_address "$canary_address" \
    --arg l1_transaction_hash "$l1_transaction_hash" \
    --arg l2_transaction_hash "$l2_transaction_hash" \
    '{
      schema_version: 1,
      status: "READY",
      generated_at: $generated_at,
      qualification_started_at: $started_at,
      elapsed_seconds: $elapsed_seconds,
      l1_chain_id: 11155111,
      l2_chain_id: $l2_chain_id,
      authenticated_rpc: true,
      non_admin_oidc: true,
      canary_receipt: true,
      canary_address: $canary_address,
      l1_transaction_hash: $l1_transaction_hash,
      l2_transaction_hash: $l2_transaction_hash,
      explorer_indexed: true
    }' >"${protected_evidence}.tmp"
  install -m 0600 "${protected_evidence}.tmp" "$protected_evidence"
  install -m 0644 "${protected_evidence}.tmp" "$evidence"
  rm -f -- "${protected_evidence}.tmp"

  printf '\nREADY\n\n'
  printf 'Authenticated product flow, canary receipt, and Explorer indexing succeeded.\n'
  printf 'Evidence: deployment/public/happy-path.json\n'
}
