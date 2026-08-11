#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_SANDBOX=$(mktemp -d)
trap 'rm -rf -- "$TEST_SANDBOX"' EXIT

expect_rejected() {
  if "$@" >/dev/null 2>&1; then
    printf 'Expected command to reject its input: %s\n' "$*" >&2
    return 1
  fi
}

valid="${TEST_SANDBOX}/input.env"
cp "${TEST_REPO_ROOT}/deployment/input.env.example" "$valid"
chmod 0600 "$valid"
"${TEST_REPO_ROOT}/tools/parse-input-env" "$valid" |
  python3 -c '
import sys
parts = sys.stdin.buffer.read().split(b"\0")
assert parts[-1] == b""
values = dict(zip(parts[0:-1:2], parts[1:-1:2], strict=True))
assert set(values) == {
    b"SANDBOX_DOMAIN",
    b"ACME_EMAIL",
    b"SEPOLIA_RPC_URL",
    b"SEPOLIA_BROWSER_RPC_URL",
}
'

export PRIVIDIUM_REPO_ROOT="$TEST_REPO_ROOT"
source "${TEST_REPO_ROOT}/cli/commands/common.sh"
source "${TEST_REPO_ROOT}/cli/commands/init.sh"
prividium_init_load_input "$valid"
[[ "$SANDBOX_DOMAIN" == "sandbox.example.com" ]]
[[ "$ACME_EMAIL" == "platform@example.com" ]]
[[ "$SEPOLIA_RPC_URL" == "https://private-archive-sepolia-rpc.example.com" ]]
[[ "$SEPOLIA_BROWSER_RPC_URL" == "https://public-browser-sepolia-rpc.example.com" ]]

with_chain_id="${TEST_SANDBOX}/input-with-chain-id.env"
cp "$valid" "$with_chain_id"
printf 'L2_CHAIN_ID=1900000001\n' >>"$with_chain_id"
chmod 0600 "$with_chain_id"
"${TEST_REPO_ROOT}/tools/parse-input-env" "$with_chain_id" |
  python3 -c '
import sys
parts = sys.stdin.buffer.read().split(b"\0")
values = dict(zip(parts[0:-1:2], parts[1:-1:2], strict=True))
assert values[b"L2_CHAIN_ID"] == b"1900000001"
'

missing="${TEST_SANDBOX}/missing.env"
grep -v '^ACME_EMAIL=' "$valid" > "$missing"
chmod 0600 "$missing"
expect_rejected "${TEST_REPO_ROOT}/tools/parse-input-env" "$missing"

chmod 0644 "$valid"
expect_rejected "${TEST_REPO_ROOT}/tools/parse-input-env" "$valid"

printf 'Input environment smoke validation passed\n'
