#!/usr/bin/env bash

: "${PRIVIDIUM_REPO_ROOT:?PRIVIDIUM_REPO_ROOT must be set by the CLI entrypoint}"

PRIVIDIUM_ENCRYPTED_ENVIRONMENT="${PRIVIDIUM_REPO_ROOT}/deployment/secrets/sandbox.enc.env"
PRIVIDIUM_DEFAULT_AGE_KEY_FILE="${PRIVIDIUM_REPO_ROOT}/deployment/secrets/age.key"
PRIVIDIUM_RUNTIME_DIR="/etc/prividium/runtime"
PRIVIDIUM_RUNTIME_ENVIRONMENT="${PRIVIDIUM_RUNTIME_DIR}/sandbox.env"

prividium_fail() {
  echo "Error: $1" >&2
  exit 1
}

prividium_validate_profile() {
  local profile="$1"
  if [[ "$profile" != "sandbox" ]]; then
    prividium_fail "unsupported profile '${profile}'; supported profile: sandbox"
  fi
}

prividium_domain_is_valid() {
  local domain="$1"
  local label
  local label_count=0
  local remaining="$1"

  if (( ${#domain} > 253 )) ||
     [[ "$domain" != *.* || "$domain" == *..* ]]; then
    return 1
  fi

  while :; do
    if [[ "$remaining" == *.* ]]; then
      label="${remaining%%.*}"
      remaining="${remaining#*.}"
    else
      label="$remaining"
      remaining=""
    fi
    if (( ${#label} < 1 || ${#label} > 63 )) ||
       [[ ! "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
      return 1
    fi
    label_count=$((label_count + 1))
    [[ -n "$remaining" ]] || break
  done

  (( label_count >= 2 ))
}

prividium_require_commands() {
  local context="$1"
  local command
  local missing=()
  shift
  for command in "$@"; do
    if ! command -v "$command" >/dev/null; then
      missing+=("$command")
    fi
  done
  if (( ${#missing[@]} )); then
    prividium_fail \
      "missing commands required for ${context}: ${missing[*]}"
  fi
}

prividium_runtime_action_required() {
  local reason="$1"

  printf "ACTION REQUIRED\n\n" >&2
  printf "%s\n\n" "$reason" >&2
  printf "Prepare the protected runtime directory:\n\n" >&2
  printf '%s\n\n' \
    '  sudo install -d -m 0700 -o "$USER" /etc/prividium/runtime' >&2
  printf "Then rerun the original ./cli/prividium command.\n" >&2
  exit 2
}

prividium_require_runtime_directory() {
  local runtime_mode

  if [[ -L "$PRIVIDIUM_RUNTIME_DIR" ]]; then
    prividium_runtime_action_required \
      "The protected runtime directory must not be a symbolic link."
  fi
  if [[ ! -d "$PRIVIDIUM_RUNTIME_DIR" ]]; then
    prividium_runtime_action_required \
      "The protected runtime directory does not exist."
  fi
  if [[ ! -O "$PRIVIDIUM_RUNTIME_DIR" ]]; then
    prividium_runtime_action_required \
      "The protected runtime directory is not owned by the current user."
  fi
  runtime_mode=$(prividium_file_mode "$PRIVIDIUM_RUNTIME_DIR")
  if [[ "$runtime_mode" != "700" ]]; then
    prividium_runtime_action_required \
      "The protected runtime directory must have mode 0700; found ${runtime_mode}."
  fi
  if [[ ! -r "$PRIVIDIUM_RUNTIME_DIR" ||
        ! -w "$PRIVIDIUM_RUNTIME_DIR" ||
        ! -x "$PRIVIDIUM_RUNTIME_DIR" ]]; then
    prividium_runtime_action_required \
      "The protected runtime directory is not accessible to the current user."
  fi
}

prividium_require_runtime_environment() {
  local environment_mode

  prividium_require_runtime_directory
  if [[ -L "$PRIVIDIUM_RUNTIME_ENVIRONMENT" ]]; then
    prividium_fail \
      "protected runtime environment must not be a symbolic link: ${PRIVIDIUM_RUNTIME_ENVIRONMENT}"
  fi
  if [[ ! -f "$PRIVIDIUM_RUNTIME_ENVIRONMENT" ||
        ! -s "$PRIVIDIUM_RUNTIME_ENVIRONMENT" ||
        ! -r "$PRIVIDIUM_RUNTIME_ENVIRONMENT" ]]; then
    echo "Protected runtime environment not found:" >&2
    echo "  ${PRIVIDIUM_RUNTIME_ENVIRONMENT}" >&2
    echo "Run: ./cli/prividium prepare" >&2
    exit 1
  fi
  environment_mode=$(prividium_file_mode "$PRIVIDIUM_RUNTIME_ENVIRONMENT")
  if [[ "$environment_mode" != "600" ]]; then
    prividium_fail \
      "protected runtime environment must have mode 0600; found ${environment_mode}"
  fi
}

prividium_clear_runtime_values() {
  unset \
    ACME_EMAIL \
    AUTH_SERVER_ADMIN_ADDRESS \
    AUTH_SERVER_ADMIN_PRIVATE_KEY \
    AUTH_SERVER_PRIVATE_KEY \
    BRIDGE_SPONSOR_KEYSTORE_B64 \
    BRIDGE_SPONSOR_KEYSTORE_PASSWORD \
    BRIDGE_SPONSOR_PRIVATE_KEY \
    BUNDLER_ENABLED \
    BUNDLER_PRIVATE_KEY \
    CHAIN_NAME \
    CHAIN_OWNER_PRIVATE_KEY \
    DEMO_USER_1_EMAIL \
    DEMO_USER_1_PASSWORD \
    DEMO_USER_2_EMAIL \
    DEMO_USER_2_PASSWORD \
    DEPLOYMENT_SIGNER_MIN_L1_BALANCE_WEI \
    ECOSYSTEM_GOVERNOR_PRIVATE_KEY \
    ENTRYPOINT_DEPLOYER_PRIVATE_KEY \
    ETH_PRICE_USD \
    EXPLORER_DB_NAME \
    EXPLORER_DB_PASSWORD \
    EXPLORER_DB_USER \
    EXPLORER_SESSION_SECRET \
    FACTORY_DEPLOYER_FUNDING_ETH \
    FEE_ACCOUNT_PRIVATE_KEY \
    GRAFANA_ADMIN_PASSWORD \
    GRAFANA_ADMIN_USER \
    INSTITUTIONAL_DEMO_DEPLOYER_PRIVATE_KEY \
    KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD \
    KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME \
    KEYCLOAK_DB_NAME \
    KEYCLOAK_DB_PASSWORD \
    KEYCLOAK_DB_USER \
    L1_CHAIN_ID \
    L1_DEPLOYER_PRIVATE_KEY \
    L2_CHAIN_ID \
    OPERATOR_COMMIT_PRIVATE_KEY \
    OPERATOR_EXECUTE_PRIVATE_KEY \
    OPERATOR_MIN_L1_BALANCE_WEI \
    OPERATOR_PROVE_PRIVATE_KEY \
    POSTGRES_SUPERUSER_PASSWORD \
    PRIVIDIUM_DB_NAME \
    PRIVIDIUM_DB_PASSWORD \
    PRIVIDIUM_DB_USER \
    REOWN_PROJECT_ID \
    RUNTIME_DIR \
    SANDBOX_ADMIN_EMAIL \
    SANDBOX_ADMIN_PASSWORD \
    SANDBOX_DOMAIN \
    SANDBOX_USER_1_EMAIL \
    SANDBOX_USER_1_PASSWORD \
    SANDBOX_USER_2_EMAIL \
    SANDBOX_USER_2_PASSWORD \
    SEPOLIA_BROWSER_RPC_URL \
    SEPOLIA_RPC_URL \
    SERVICE_WALLET_TARGET_L2_ETH \
    SIWE_HMAC_SECRET \
    SSO_DEPLOYER_PRIVATE_KEY \
    WEBHOOK_DB_NAME \
    WEBHOOK_DB_PASSWORD \
    WEBHOOK_DB_USER \
    WEBHOOK_ENABLED \
    WEBHOOK_ENCRYPTION_KDF_SALT \
    WEBHOOK_ENCRYPTION_KEY \
    WEBHOOK_PRIVIDIUM_API_KEY
}

prividium_load_runtime_environment() {
  local caller_confirmation="${CONFIRM_BROADCAST-}"
  local caller_confirmation_supplied="${CONFIRM_BROADCAST+x}"

  prividium_require_runtime_environment
  prividium_clear_runtime_values
  unset CONFIRM_BROADCAST
  set -a
  # Generated by tools/init-secrets and restricted to shell-safe dotenv values.
  source "$PRIVIDIUM_RUNTIME_ENVIRONMENT"
  set +a
  if [[ "$caller_confirmation_supplied" == "x" ]]; then
    export CONFIRM_BROADCAST="$caller_confirmation"
  else
    unset CONFIRM_BROADCAST
  fi
  unset \
    CHAIN_BOOTSTRAP_MODE \
    PRIVIDIUM_CHAIN_BOOTSTRAP_IMAGE \
    PRIVIDIUM_HOST_GID \
    PRIVIDIUM_HOST_UID
  if [[ "${RUNTIME_DIR:-}" != "$PRIVIDIUM_RUNTIME_DIR" ]]; then
    prividium_fail \
      "sandbox RUNTIME_DIR must be ${PRIVIDIUM_RUNTIME_DIR}; found ${RUNTIME_DIR:-missing}"
  fi
  if [[ -z "${SANDBOX_DOMAIN:-}" || -z "${L2_CHAIN_ID:-}" ]]; then
    prividium_fail \
      "protected runtime is missing SANDBOX_DOMAIN or L2_CHAIN_ID; repair the encrypted configuration and rerun ./cli/prividium prepare"
  fi
  if ! prividium_domain_is_valid "$SANDBOX_DOMAIN"; then
    prividium_fail \
      "protected runtime contains an invalid SANDBOX_DOMAIN; repair the encrypted configuration and rerun ./cli/prividium prepare"
  fi
  if [[ ! "$L2_CHAIN_ID" =~ ^[0-9]+$ ]] ||
     (( L2_CHAIN_ID < 1073741824 || L2_CHAIN_ID > 2147483647 )); then
    prividium_fail \
      "protected runtime L2_CHAIN_ID must be in 1073741824..2147483647; repair the encrypted configuration and rerun ./cli/prividium prepare"
  fi
}

prividium_sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

prividium_dns_resolves() {
  local hostname="$1"

  if command -v getent >/dev/null 2>&1 &&
     RES_OPTIONS="attempts:1 timeout:2" \
       getent ahosts "$hostname" >/dev/null 2>&1; then
    return 0
  fi
  if command -v dscacheutil >/dev/null 2>&1 &&
     dscacheutil -q host -a name "$hostname" |
       grep -q ip_address; then
    return 0
  fi
  if command -v host >/dev/null 2>&1 &&
     host -W 3 "$hostname" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

prividium_require_encrypted_environment() {
  local encrypted_mode

  if [[ -L "$PRIVIDIUM_ENCRYPTED_ENVIRONMENT" ]]; then
    prividium_fail \
      "encrypted sandbox configuration must not be a symbolic link: ${PRIVIDIUM_ENCRYPTED_ENVIRONMENT}"
  fi
  if [[ ! -f "$PRIVIDIUM_ENCRYPTED_ENVIRONMENT" ||
        ! -s "$PRIVIDIUM_ENCRYPTED_ENVIRONMENT" ]]; then
    echo "Encrypted sandbox configuration not found:" >&2
    echo "  ${PRIVIDIUM_ENCRYPTED_ENVIRONMENT}" >&2
    echo "Run: ./cli/prividium init" >&2
    exit 1
  fi
  encrypted_mode=$(prividium_file_mode "$PRIVIDIUM_ENCRYPTED_ENVIRONMENT")
  if (( (8#$encrypted_mode & 0022) != 0 )); then
    prividium_fail \
      "encrypted sandbox configuration must not be group/world writable: ${PRIVIDIUM_ENCRYPTED_ENVIRONMENT}"
  fi
}

prividium_file_mode() {
  local file="$1"
  if stat -f '%Lp' "$file" >/dev/null 2>&1; then
    stat -f '%Lp' "$file"
  else
    stat -c '%a' "$file"
  fi
}

prividium_resolve_age_identity() {
  local age_key_file="${SOPS_AGE_KEY_FILE:-}"
  local age_key_mode

  if [[ -z "$age_key_file" ]]; then
    age_key_file="$PRIVIDIUM_DEFAULT_AGE_KEY_FILE"
  fi

  if [[ -L "$age_key_file" ]]; then
    prividium_fail "age identity must not be a symbolic link: ${age_key_file}"
  fi
  if [[ ! -f "$age_key_file" || ! -s "$age_key_file" || ! -r "$age_key_file" ]]; then
    prividium_fail "age identity is not a readable, nonempty regular file: ${age_key_file}"
  fi

  age_key_mode=$(prividium_file_mode "$age_key_file")
  if [[ "$age_key_file" == "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE" &&
        "$age_key_mode" != "600" ]]; then
    prividium_fail \
      "local age identity must have mode 0600: ${PRIVIDIUM_DEFAULT_AGE_KEY_FILE}"
  fi
  if [[ "$age_key_file" != "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE" ]] &&
     (( (8#$age_key_mode & 0077) != 0 )); then
    prividium_fail \
      "age identity must not grant group/world permissions: ${age_key_file}"
  fi

  export SOPS_AGE_KEY_FILE="$age_key_file"
}
