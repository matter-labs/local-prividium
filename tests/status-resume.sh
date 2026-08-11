#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_SANDBOX=$(mktemp -d)
trap 'rm -rf -- "$TEST_SANDBOX"' EXIT

export PRIVIDIUM_REPO_ROOT="${TEST_SANDBOX}/repo"
export PRIVIDIUM_RUNTIME_DIR="${TEST_SANDBOX}/runtime"
export PRIVIDIUM_ENCRYPTED_ENVIRONMENT="${PRIVIDIUM_REPO_ROOT}/deployment/secrets/sandbox.enc.env"
export PRIVIDIUM_STATUS_HOST_MARKER="${TEST_SANDBOX}/host-contract-version"
export PRIVIDIUM_STATUS_INCOMPLETE_SUMMARY="${PRIVIDIUM_RUNTIME_DIR}/reports/deployment-summary.incomplete.md"

mkdir -p \
  "${PRIVIDIUM_REPO_ROOT}/deployment/public" \
  "${PRIVIDIUM_REPO_ROOT}/deployment/secrets" \
  "${PRIVIDIUM_RUNTIME_DIR}/chain/out" \
  "${PRIVIDIUM_RUNTIME_DIR}/reports"
printf 'host-contract-v1\n' >"$PRIVIDIUM_STATUS_HOST_MARKER"
printf 'encrypted\n' >"$PRIVIDIUM_ENCRYPTED_ENVIRONMENT"

id() {
  [[ "${1:-}" == "-u" ]] && printf '1000\n' || command id "$@"
}
docker() {
  return 0
}

source "${TEST_REPO_ROOT}/cli/commands/status.sh"

stage() {
  prividium_status --json | jq -r '.stage'
}

fingerprint=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
printf -- '- Role-set fingerprint: `%s`.\n' "$fingerprint" \
  >"${PRIVIDIUM_REPO_ROOT}/deployment/public/roles.md"
[[ "$(stage)" == "FUNDING_REQUIRED" ]]

jq -n \
  --arg fingerprint "$fingerprint" \
  '{
    schema_version: 1,
    status: "FUNDED",
    l1_chain_id: 11155111,
    l2_chain_id: 1900000001,
    role_set_fingerprint: $fingerprint,
    canary_reserve_wei: "50000000000000000",
    funding_targets_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }' >"${PRIVIDIUM_RUNTIME_DIR}/reports/funding-ready.json"
[[ "$(stage)" == "FUNDED" ]]

printf '{"l2_chain_id":1900000001}\n' \
  >"${PRIVIDIUM_RUNTIME_DIR}/chain/out/preparation.json"
[[ "$(stage)" == "READY_TO_BROADCAST" ]]

printf '{"status":"STARTED"}\n' \
  >"${PRIVIDIUM_RUNTIME_DIR}/reports/broadcast-attempt.json"
[[ "$(stage)" == "BROADCAST_REVIEW_REQUIRED" ]]
rm -f -- "${PRIVIDIUM_RUNTIME_DIR}/reports/broadcast-attempt.json"

printf '{"l2_chain_id":1900000001}\n' \
  >"${PRIVIDIUM_REPO_ROOT}/deployment/public/manifest.json"
[[ "$(stage)" == "READY_TO_DEPLOY" ]]

printf '%s\n' '- Status: **HEALTHY**' \
  >"${PRIVIDIUM_REPO_ROOT}/deployment/public/deployment-summary.md"
[[ "$(stage)" == "READY_TO_VERIFY" ]]

printf '{"status":"STARTED","l2_chain_id":1900000001}\n' \
  >"${PRIVIDIUM_RUNTIME_DIR}/chain/canary-attempt.json"
[[ "$(stage)" == "CANARY_REVIEW_REQUIRED" ]]
printf '%s\n' \
  '{"l1_chain_id":11155111,"l2_chain_id":1900000001,"canary_address":"0x1111111111111111111111111111111111111111","l1_transaction_hash":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","l2_transaction_hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}' \
  >"${PRIVIDIUM_RUNTIME_DIR}/chain/canary-submission.json"
[[ "$(stage)" == "READY_TO_VERIFY" ]]

jq -n '{
  status: "READY",
  l2_chain_id: 1900000001,
  authenticated_rpc: true,
  non_admin_oidc: true,
  canary_receipt: true,
  explorer_indexed: true
}' >"${PRIVIDIUM_REPO_ROOT}/deployment/public/happy-path.json"
[[ "$(stage)" == "READY" ]]

printf 'Status/resume smoke validation passed\n'
