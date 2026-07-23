#!/usr/bin/env bash

sandbox_validate_funding_policy() {
  local policy_file="$1"
  local validation_mode="${2:-release}"
  local customer_funding
  local maximum_allocated
  local minimum_buffer
  local role_total
  local sponsor_reserve
  local allocated_total

  command -v jq >/dev/null || {
    echo "jq is required to read the sandbox funding policy" >&2
    return 1
  }
  if [[ ! -s "$policy_file" ]]; then
    echo "Funding policy not found: ${policy_file}" >&2
    return 1
  fi
  if ! jq -e '
    .schema_version == 1 and
    (.policy_version | type == "string" and length > 0) and
    .scope == "core" and
    .release.protocol == "v0.31.0" and
    .release.protocol_commit == "e091691063c99a1d0281d6fe42fb0ec4430f3673" and
    .release.zksync_os_server == "0.20.8" and
    .release.zksync_os_server_commit == "dbb5c03d4a94ceb1acea9f79242590f354660239" and
    .release.zk_deployer_commit == "16c6a83b4f634609958f347c56549ba19bf9df9b" and
    .release.prividium == "v1.276.0" and
    .release.prividium_commit == "fff5b1ad35812c749101960c72f45d70ead731a4" and
    .release.watchdog == "v1.0.17" and
    .release.watchdog_commit == "1edb60407b4b05eaba12f03337ef9f91e7388f27" and
    .customer_funding_wei == "1000000000000000000" and
    .maximum_allocated_wei == "900000000000000000" and
    .minimum_unallocated_buffer_wei == "100000000000000000" and
    .operator_runway_days == 14 and
    .batch_interval_seconds == 600 and
    .operator_runway_batches == 2016 and
    .sponsor.watchdog_l2_target_wei == "50000000000000000" and
    .optional_profiles.included_in_customer_funding == false and
    (.optional_profiles.sso_incremental_sponsor_minimum_wei | test("^[0-9]+$")) and
    (.optional_profiles.institutional_demo_incremental_sponsor_minimum_wei | test("^[0-9]+$")) and
    ([.roles[].id] | sort) == [
      "chain_owner",
      "ecosystem_governor",
      "l1_deployer",
      "operator_commit",
      "operator_execute",
      "operator_prove"
    ] and
    (.roles | all(
      (.id | type == "string" and length > 0) and
      (.target_wei | test("^[0-9]+$")) and
      (.purpose | type == "string" and length > 0)
    ))
  ' "$policy_file" >/dev/null; then
    echo "Funding policy schema or required 1 ETH sandbox invariants are invalid" >&2
    return 1
  fi

  if [[ "$validation_mode" != "release" && "$validation_mode" != "structure" ]]; then
    echo "Unknown funding policy validation mode: ${validation_mode}" >&2
    return 1
  fi
  if [[ "$(jq -r '.benchmark.status' "$policy_file")" != "complete" &&
        "$validation_mode" == "release" ]]; then
    echo "Funding policy benchmark is pending." >&2
    echo "Complete one clean Sepolia release rehearsal and record its evidence before customer use." >&2
    return 1
  fi
  if [[ "$(jq -r '.benchmark.status' "$policy_file")" == "complete" ]]; then
    if ! jq -e '
      (.benchmark.measured_at | type == "string" and length > 0) and
      (.benchmark.evidence | type == "string" and length > 0) and
      (.benchmark.observations.distribution_and_bridge_fees_wei | test("^[0-9]+$")) and
      (.benchmark.observations.role_spend_wei | length) == 3 and
      (.benchmark.observations.operator_per_batch_spend_wei | length) == 3
    ' "$policy_file" >/dev/null; then
      echo "Completed funding benchmark is missing its release rehearsal observations or evidence" >&2
      return 1
    fi
    local role
    local observed
    local expected
    local target
    local operator_product
    for role in l1_deployer ecosystem_governor chain_owner; do
      observed=$(jq -er --arg role "$role" \
        '.benchmark.observations.role_spend_wei[$role] | select(test("^[0-9]+$"))' \
        "$policy_file")
      if (( observed > 900000000000000000 )); then
        echo "Observed spend for ${role} exceeds the core allocation boundary" >&2
        return 1
      fi
      target=$(sandbox_policy_role_target "$policy_file" "$role")
      expected=$(((observed * 3 + 1) / 2 + 10000000000000000))
      if (( target != expected )); then
        echo "Funding target for ${role} does not match the benchmark formula" >&2
        return 1
      fi
    done
    for role in operator_commit operator_prove operator_execute; do
      observed=$(jq -er --arg role "$role" \
        '.benchmark.observations.operator_per_batch_spend_wei[$role] | select(test("^[0-9]+$"))' \
        "$policy_file")
      if (( observed > 297619047619047 )); then
        echo "Observed per-batch spend for ${role} cannot fit the core allocation boundary" >&2
        return 1
      fi
      target=$(sandbox_policy_role_target "$policy_file" "$role")
      operator_product=$((observed * 2016))
      expected=$(((operator_product * 3 + 1) / 2))
      if (( expected < 10000000000000000 )); then
        expected=10000000000000000
      fi
      if (( target != expected )); then
        echo "Funding target for ${role} does not match the 2,016-batch benchmark formula" >&2
        return 1
      fi
    done
    observed=$(jq -er \
      '.benchmark.observations.distribution_and_bridge_fees_wei | select(test("^[0-9]+$"))' \
      "$policy_file")
    if (( observed > 533333333333333333 )); then
      echo "Observed distribution/bridge fees cannot fit the sponsor reserve boundary" >&2
      return 1
    fi
    expected=$((100000000000000000 + (observed * 3 + 1) / 2))
    if (( $(jq -r '.sponsor.retained_reserve_wei' "$policy_file") != expected )); then
      echo "Sponsor reserve does not match the benchmark formula" >&2
      return 1
    fi
  fi

  customer_funding=$(jq -r '.customer_funding_wei' "$policy_file")
  maximum_allocated=$(jq -r '.maximum_allocated_wei' "$policy_file")
  minimum_buffer=$(jq -r '.minimum_unallocated_buffer_wei' "$policy_file")
  role_total=0
  while IFS= read -r role_target; do
    role_total=$((role_total + role_target))
  done < <(jq -r '.roles[].target_wei' "$policy_file")
  sponsor_reserve=$(jq -r '.sponsor.retained_reserve_wei' "$policy_file")
  allocated_total=$((role_total + sponsor_reserve))

  if (( allocated_total > maximum_allocated )); then
    echo "Funding policy allocates ${allocated_total} wei; maximum is ${maximum_allocated}" >&2
    return 1
  fi
  if (( customer_funding - allocated_total < minimum_buffer )); then
    echo "Funding policy leaves less than the required 0.10 ETH customer buffer" >&2
    return 1
  fi
}

sandbox_policy_optional_minimum() {
  local policy_file="$1"
  local profile="$2"
  case "$profile" in
    sso)
      jq -er '.optional_profiles.sso_incremental_sponsor_minimum_wei' "$policy_file"
      ;;
    institutional-demo)
      jq -er '.optional_profiles.institutional_demo_incremental_sponsor_minimum_wei' "$policy_file"
      ;;
    *)
      echo "Unknown optional funding profile: ${profile}" >&2
      return 1
      ;;
  esac
}

sandbox_policy_role_target() {
  local policy_file="$1"
  local role="$2"
  jq -er --arg role "$role" '.roles[] | select(.id == $role) | .target_wei' "$policy_file"
}

sandbox_policy_role_purpose() {
  local policy_file="$1"
  local role="$2"
  jq -er --arg role "$role" '.roles[] | select(.id == $role) | .purpose' "$policy_file"
}
