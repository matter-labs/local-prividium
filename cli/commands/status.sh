#!/usr/bin/env bash

prividium_status_usage() {
  cat <<'EOF'
Show the resumable Prividium happy-path stage.

Usage:
  ./cli/prividium status [--json]

Status is read-only and does not decrypt secrets, fund wallets, submit
transactions, or start services. The JSON form is safe for agent control flow.
EOF
}

prividium_status() {
  local as_json="false"
  local broadcast_attempt="${PRIVIDIUM_RUNTIME_DIR}/reports/broadcast-attempt.json"
  local canary_attempt="${PRIVIDIUM_RUNTIME_DIR}/chain/canary-attempt.json"
  local canary_submission="${PRIVIDIUM_RUNTIME_DIR}/chain/canary-submission.json"
  local canary_submission_ready="false"
  local detail
  local evidence="${PRIVIDIUM_REPO_ROOT}/deployment/public/happy-path.json"
  local funding_evidence="${PRIVIDIUM_RUNTIME_DIR}/reports/funding-ready.json"
  local funding_ready="false"
  local host_marker="${PRIVIDIUM_STATUS_HOST_MARKER:-/etc/prividium/.host-contract-version}"
  local incomplete="${PRIVIDIUM_STATUS_INCOMPLETE_SUMMARY:-/etc/prividium/runtime/reports/deployment-summary.incomplete.md}"
  local l2_chain_id=""
  local next_command
  local public_manifest="${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json"
  local public_summary="${PRIVIDIUM_REPO_ROOT}/deployment/public/deployment-summary.md"
  local ready="false"
  local role_fingerprint=""
  local stage

  while (( $# )); do
    case "$1" in
      --json)
        as_json="true"
        shift
        ;;
      -h|--help)
        prividium_status_usage
        return
        ;;
      *)
        prividium_fail "unexpected status argument: $1"
        ;;
    esac
  done

  if [[ -s "${PRIVIDIUM_REPO_ROOT}/deployment/public/roles.md" ]]; then
    role_fingerprint=$(
      sed -n 's/.*Role-set fingerprint: `\([^`]*\)`.*/\1/p' \
        "${PRIVIDIUM_REPO_ROOT}/deployment/public/roles.md" | head -n 1
    )
  fi
  if [[ "$role_fingerprint" =~ ^[0-9a-fA-F]{64}$ &&
        -s "$funding_evidence" ]] &&
     command -v jq >/dev/null 2>&1 &&
     jq -e --arg fingerprint "$role_fingerprint" '
       .schema_version == 1 and
       .status == "FUNDED" and
       .l1_chain_id == 11155111 and
       (.l2_chain_id | type == "number" and . >= 1073741824 and . <= 2147483647) and
       .role_set_fingerprint == $fingerprint and
       (.canary_reserve_wei | type == "string" and test("^[1-9][0-9]*$")) and
       (.funding_targets_sha256 | test("^[0-9a-f]{64}$"))
     ' "$funding_evidence" >/dev/null 2>&1; then
    funding_ready="true"
  fi
  if [[ -s "$canary_attempt" && -s "$canary_submission" ]] &&
     command -v jq >/dev/null 2>&1 &&
     jq -e --slurpfile attempt "$canary_attempt" '
       .l1_chain_id == 11155111 and
       (.l2_chain_id | type == "number") and
       .l2_chain_id == $attempt[0].l2_chain_id and
       (.canary_address | type == "string" and test("^0x[0-9a-fA-F]{40}$")) and
       (.l1_transaction_hash | test("^0x[0-9a-fA-F]{64}$")) and
       (.l2_transaction_hash | test("^0x[0-9a-fA-F]{64}$"))
     ' "$canary_submission" >/dev/null 2>&1; then
    canary_submission_ready="true"
  fi

  if [[ "$(id -u)" == "0" ]]; then
    stage="OPERATOR_REQUIRED"
    next_command="./cli/prividium host operator create"
    detail="Create the passwordless-sudo operator, verify a second SSH session, and resume from its clone."
  elif [[ ! -f "$host_marker" ]]; then
    stage="HOST_PREFLIGHT_REQUIRED"
    next_command="./cli/prividium host preflight"
    detail="Assess the blank Ubuntu 24.04 amd64 VPS before approved host installation."
  elif ! command -v docker >/dev/null 2>&1 ||
       ! docker info >/dev/null 2>&1 ||
       ! docker compose version >/dev/null 2>&1; then
    stage="HOST_VERIFY_REQUIRED"
    next_command="./cli/prividium host verify"
    detail="Verify the installed host contract and reconnect if Docker group membership is not active."
  elif [[ ! -s "${PRIVIDIUM_ENCRYPTED_ENVIRONMENT}" ]]; then
    stage="CONFIGURATION_REQUIRED"
    next_command="./cli/prividium init"
    detail="Complete the protected input file and initialize the sandbox."
  elif [[ ! -s "${PRIVIDIUM_RUNTIME_DIR}/chain/out/preparation.json" &&
          ! -s "$public_manifest" ]]; then
    if [[ "$funding_ready" == "true" ]]; then
      stage="FUNDED"
      next_command="./cli/prividium preflight"
      detail="Funding was reconciled; pass preflight and prepare the protocol deployment."
    else
      stage="FUNDING_REQUIRED"
      next_command="./cli/prividium fund"
      detail="Reconcile the six Sepolia roles and retain the acceptance-canary reserve."
    fi
  elif [[ ! -s "$public_manifest" && ( -e "$broadcast_attempt" || -L "$broadcast_attempt" ) ]]; then
    stage="BROADCAST_REVIEW_REQUIRED"
    next_command=""
    detail="An approved protocol broadcast was interrupted; preserve runtime state and inspect it before any retry."
  elif [[ ! -s "$public_manifest" ]]; then
    stage="READY_TO_BROADCAST"
    next_command="./cli/prividium broadcast"
    detail="Review the prepared artifacts and explicitly authorize the Sepolia broadcast."
  elif [[ -s "$incomplete" ]]; then
    stage="DEPLOYMENT_INCOMPLETE"
    next_command="./cli/prividium deploy"
    detail="Resolve the protected deployment diagnostics and resume the core stack."
  elif [[ ! -s "$public_summary" ]]; then
    stage="READY_TO_DEPLOY"
    next_command="./cli/prividium deploy"
    detail="Start and validate the 14-service core stack."
  elif [[ -s "$evidence" ]] && command -v jq >/dev/null 2>&1 &&
       jq -e '
         .status == "READY" and
         .authenticated_rpc == true and
         .non_admin_oidc == true and
         .canary_receipt == true and
         .explorer_indexed == true
       ' "$evidence" >/dev/null 2>&1; then
    stage="READY"
    next_command=""
    detail="Authenticated RPC, the canary receipt, and Explorer indexing are complete."
    ready="true"
  elif [[ ( -e "$canary_attempt" || -L "$canary_attempt" ) &&
          "$canary_submission_ready" != "true" ]]; then
    stage="CANARY_REVIEW_REQUIRED"
    next_command=""
    detail="An approved canary was interrupted before durable submission evidence; inspect Sepolia state before any retry."
  else
    stage="READY_TO_VERIFY"
    next_command="./cli/prividium verify"
    detail="Run the confirmation-gated authenticated canary and Explorer smoke."
  fi

  for candidate in "$evidence" "$public_manifest" "${PRIVIDIUM_RUNTIME_DIR}/chain/out/preparation.json" "$funding_evidence"; do
    if [[ -s "$candidate" ]] && command -v jq >/dev/null 2>&1; then
      l2_chain_id=$(jq -r '.l2_chain_id // empty' "$candidate" 2>/dev/null || true)
      [[ "$l2_chain_id" =~ ^[0-9]+$ ]] && break
      l2_chain_id=""
    fi
  done

  if [[ "$as_json" == "true" ]]; then
    if [[ -n "$l2_chain_id" ]]; then
      printf '{"stage":"%s","ready":%s,"next_command":"%s","l2_chain_id":%s,"detail":"%s"}\n' \
        "$stage" "$ready" "$next_command" "$l2_chain_id" "$detail"
    else
      printf '{"stage":"%s","ready":%s,"next_command":"%s","l2_chain_id":null,"detail":"%s"}\n' \
        "$stage" "$ready" "$next_command" "$detail"
    fi
    return
  fi

  printf 'Prividium deployment status\n\n'
  printf '%-14s %s\n' "Stage" "$stage"
  printf '%-14s %s\n' "Ready" "$ready"
  [[ -z "$l2_chain_id" ]] || printf '%-14s %s\n' "L2 chain ID" "$l2_chain_id"
  printf '%-14s %s\n' "Profile" "sandbox (core only)"
  printf '\n%s\n' "$detail"
  [[ -z "$next_command" ]] || printf '\nNext: %s\n' "$next_command"
}
