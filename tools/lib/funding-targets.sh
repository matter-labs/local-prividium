#!/usr/bin/env bash

sandbox_validate_funding_targets() {
  local targets_file="$1"

  command -v jq >/dev/null || {
    echo "jq is required to read the sandbox funding targets" >&2
    return 1
  }
  if [[ ! -s "$targets_file" ]]; then
    echo "Funding targets not found: ${targets_file}" >&2
    return 1
  fi
  if ! jq -e '
    type == "object" and
    (keys | sort) == ["l1_chain_id", "schema_version", "targets_wei"] and
    .schema_version == 1 and
    .l1_chain_id == 11155111 and
    (.targets_wei | type == "object") and
    (.targets_wei | keys | sort) == [
      "chain_owner",
      "ecosystem_governor",
      "l1_deployer",
      "operator_commit",
      "operator_execute",
      "operator_prove"
    ] and
    (.targets_wei | all(
      type == "string" and
      test("^[1-9][0-9]*$")
    ))
  ' "$targets_file" >/dev/null; then
    echo "Funding targets must use the exact six-role Sepolia schema" >&2
    return 1
  fi
}

sandbox_funding_target() {
  local targets_file="$1"
  local role="$2"

  jq -er --arg role "$role" '
    .targets_wei[$role] |
    select(type == "string" and test("^[1-9][0-9]*$"))
  ' "$targets_file"
}
