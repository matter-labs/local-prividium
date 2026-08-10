#!/usr/bin/env bash
set -Eeuo pipefail

TEST_REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${TEST_REPO_ROOT}/tools/host/common.sh"

expect_rejected() {
  if ("$@") >/dev/null 2>&1; then
    printf 'Expected command to reject its input: %s\n' "$*" >&2
    return 1
  fi
}

prividium_host_assert_platform ubuntu 24.04 Linux x86_64 true
expect_rejected \
  prividium_host_assert_platform ubuntu 22.04 Linux x86_64 true
expect_rejected \
  prividium_host_assert_platform ubuntu 24.04 Linux aarch64 true

prividium_host_assert_capacity 4 7864320 190000000000
expect_rejected prividium_host_assert_capacity 3 7864320 190000000000
expect_rejected prividium_host_assert_capacity 4 7864319 190000000000
expect_rejected prividium_host_assert_capacity 4 7864320 189999999999

prividium_host_marker_values_are_valid 644 root:root host-contract-v1
expect_rejected \
  prividium_host_marker_values_are_valid 644 root:root managed-by-ansible
expect_rejected \
  prividium_host_marker_values_are_valid 600 root:root host-contract-v1

plan=$(prividium_host_print_install_plan)
grep -Fq 'Apply safe Ubuntu package upgrades.' <<< "$plan"
grep -Fq 'Explicitly excluded' <<< "$plan"
grep -Fq 'host/provider firewall rules' <<< "$plan"

"${TEST_REPO_ROOT}/cli/prividium" host bootstrap --help >/dev/null
"${TEST_REPO_ROOT}/cli/prividium" host preflight --help >/dev/null
"${TEST_REPO_ROOT}/cli/prividium" host install --help >/dev/null
"${TEST_REPO_ROOT}/cli/prividium" host verify --help >/dev/null

printf 'Host backend smoke validation passed\n'
