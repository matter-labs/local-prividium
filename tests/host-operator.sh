#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_SANDBOX=$(mktemp -d)
trap 'rm -rf "$TEST_SANDBOX"' EXIT

export PRIVIDIUM_REPO_ROOT="$TEST_REPO_ROOT"
source "${TEST_REPO_ROOT}/cli/commands/common.sh"
source "${TEST_REPO_ROOT}/cli/commands/host-operator.sh"

expect_rejected() {
  if "$@" >/dev/null 2>&1; then
    printf 'Expected command to reject its input: %s\n' "$*" >&2
    return 1
  fi
}

prividium_host_operator_username_is_valid prividium
prividium_host_operator_username_is_valid evaluation-admin
expect_rejected prividium_host_operator_username_is_valid root
expect_rejected prividium_host_operator_username_is_valid Prividium
expect_rejected prividium_host_operator_username_is_valid 'operator;id'
expect_rejected prividium_host_operator_username_is_valid "$(printf 'a%.0s' {1..33})"

test_public_key=$(python3 -c '
import base64

def ssh_string(value):
    return len(value).to_bytes(4, "big") + value

key_type = b"ssh-ed25519"
payload = ssh_string(key_type) + ssh_string(bytes(range(32)))
print(f"ssh-ed25519 {base64.b64encode(payload).decode()} operator@example")
')

normalized=$(prividium_host_operator_normalize_keys text "$test_public_key")
[[ "$normalized" == "$test_public_key" ]]

plain_key_file="${TEST_SANDBOX}/operator.pub"
printf '# operator key\n\n%s\n' "$test_public_key" > "$plain_key_file"
normalized=$(prividium_host_operator_normalize_keys file "$plain_key_file")
[[ "$normalized" == "$test_public_key" ]]

authorized_keys_file="${TEST_SANDBOX}/authorized_keys"
restricted_key="restrict,from=\"192.0.2.0/24\" ${test_public_key}"
printf '# provider-managed root keys\n%s\n%s\n' \
  "$restricted_key" \
  "$test_public_key" > "$authorized_keys_file"
normalized=$(prividium_host_operator_normalize_keys \
  authorized_keys \
  "$authorized_keys_file")
[[ "$normalized" == "${restricted_key}"$'\n'"${test_public_key}" ]]

multi_key_file="${TEST_SANDBOX}/multiple.pub"
printf '%s\n%s\n' "$test_public_key" "$test_public_key" > "$multi_key_file"
expect_rejected prividium_host_operator_normalize_keys file "$multi_key_file"
expect_rejected prividium_host_operator_normalize_keys text \
  'ssh-ed25519 not-base64 operator@example'
expect_rejected prividium_host_operator_normalize_keys text \
  "command=restricted ${test_public_key}"

printf 'Host operator input validation passed\n'
