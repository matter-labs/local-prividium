#!/usr/bin/env bash

prividium_init_usage() {
  cat <<'EOF'
Initialize a Prividium evaluation sandbox.

Usage:
  ./cli/prividium init [--profile sandbox]

Options:
  --profile sandbox  Sandbox profile to initialize (default: sandbox)
  -h, --help         Show this help

Interactive inputs can also be provided through:
  SANDBOX_DOMAIN
  ACME_EMAIL
  SEPOLIA_RPC_URL
  SEPOLIA_BROWSER_RPC_URL

Evaluation credentials can be overridden through:
  SANDBOX_ADMIN_EMAIL
  SANDBOX_ADMIN_PASSWORD
  SANDBOX_USER_1_EMAIL
  SANDBOX_USER_1_PASSWORD
  SANDBOX_USER_2_EMAIL
  SANDBOX_USER_2_PASSWORD

Password overrides may use letters, numbers, and ._%+@,/:=!?^-.

Age encryption uses SOPS_AGE_KEY_FILE when supplied; SOPS_AGE_RECIPIENT may
also be set when it matches that identity. Otherwise, a local identity is
generated at deployment/secrets/age.key.
EOF
}

prividium_prompt_value() {
  local name="$1"
  local label="$2"
  local secret="${3:-false}"
  local value="${!name:-}"

  if [[ -n "$value" ]]; then
    return
  fi
  if [[ ! -t 0 ]]; then
    prividium_fail "${name} is required in non-interactive mode"
  fi
  if [[ "$secret" == "true" ]]; then
    read -r -s -p "${label}: " value
    printf "\n"
  else
    read -r -p "${label}: " value
  fi
  if [[ -z "$value" ]]; then
    prividium_fail "${name} cannot be empty"
  fi
  printf -v "$name" "%s" "$value"
  export "$name"
}

prividium_display_credential() {
  local value="$1"
  local configured="$2"
  if [[ "$configured" == "true" ]]; then
    printf "%s" "[configured override]"
  else
    printf "%s" "$value"
  fi
}

prividium_init() {
  local profile="sandbox"
  local age_identity_label
  local age_identity_display
  local age_identity_message
  local age_key_file
  local admin_email_configured="false"
  local admin_password_configured="false"
  local browser_rpc_comparison
  local derived_recipient
  local private_rpc_comparison
  local rpc_url_pattern='^https://[A-Za-z0-9:/?&=._%+-]+$'
  local show_help="false"
  local user_1_email_configured="false"
  local user_1_password_configured="false"
  local user_2_email_configured="false"
  local user_2_password_configured="false"

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
        prividium_fail "unknown init option: $1"
        ;;
      *)
        prividium_fail "unexpected init argument: $1"
        ;;
    esac
  done

  prividium_validate_profile "$profile"
  if [[ "$show_help" == "true" ]]; then
    prividium_init_usage
    return
  fi
  if [[ -e "$PRIVIDIUM_ENCRYPTED_ENVIRONMENT" ||
        -L "$PRIVIDIUM_ENCRYPTED_ENVIRONMENT" ]]; then
    prividium_fail \
      "${PRIVIDIUM_ENCRYPTED_ENVIRONMENT} already exists; initialization will not replace it"
  fi

  prividium_require_commands \
    "sandbox initialization" age age-keygen sops cast openssl curl jq

  [[ -z "${SANDBOX_ADMIN_EMAIL:-}" ]] || admin_email_configured="true"
  [[ -z "${SANDBOX_ADMIN_PASSWORD:-}" ]] || admin_password_configured="true"
  [[ -z "${SANDBOX_USER_1_EMAIL:-}" ]] || user_1_email_configured="true"
  [[ -z "${SANDBOX_USER_1_PASSWORD:-}" ]] || user_1_password_configured="true"
  [[ -z "${SANDBOX_USER_2_EMAIL:-}" ]] || user_2_email_configured="true"
  [[ -z "${SANDBOX_USER_2_PASSWORD:-}" ]] || user_2_password_configured="true"

  export SANDBOX_ADMIN_EMAIL="${SANDBOX_ADMIN_EMAIL:-admin@local.dev}"
  export SANDBOX_ADMIN_PASSWORD="${SANDBOX_ADMIN_PASSWORD:-password}"
  export SANDBOX_USER_1_EMAIL="${SANDBOX_USER_1_EMAIL:-user1@local.dev}"
  export SANDBOX_USER_1_PASSWORD="${SANDBOX_USER_1_PASSWORD:-password}"
  export SANDBOX_USER_2_EMAIL="${SANDBOX_USER_2_EMAIL:-user2@local.dev}"
  export SANDBOX_USER_2_PASSWORD="${SANDBOX_USER_2_PASSWORD:-password}"

  printf "Prividium sandbox initialization\n"
  printf "Profile: %s\n\n" "$profile"

  prividium_prompt_value SANDBOX_DOMAIN "Sandbox DNS domain"
  prividium_prompt_value ACME_EMAIL "ACME notification email"
  prividium_prompt_value SEPOLIA_RPC_URL "Private Sepolia RPC URL" true
  prividium_prompt_value SEPOLIA_BROWSER_RPC_URL "Public browser Sepolia RPC URL"

  if ! prividium_domain_is_valid "$SANDBOX_DOMAIN"; then
    prividium_fail \
      "SANDBOX_DOMAIN must be a valid lower-case DNS name with labels no longer than 63 characters"
  fi
  if [[ ! "$SEPOLIA_RPC_URL" =~ $rpc_url_pattern ||
        ! "$SEPOLIA_BROWSER_RPC_URL" =~ $rpc_url_pattern ]]; then
    prividium_fail \
      "Sepolia RPC URLs must use HTTPS and contain only URL-safe characters"
  fi
  private_rpc_comparison="${SEPOLIA_RPC_URL%/}"
  browser_rpc_comparison="${SEPOLIA_BROWSER_RPC_URL%/}"
  if [[ "$private_rpc_comparison" == "$browser_rpc_comparison" ]]; then
    prividium_fail \
      "private and browser RPC URLs must be separate so provider credentials cannot enter browser configuration"
  fi

  if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
    age_key_file="$SOPS_AGE_KEY_FILE"
    age_identity_label="Age identity"
    age_identity_display="$age_key_file"
    age_identity_message="Using supplied age identity"
  elif [[ -e "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE" ||
          -L "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE" ]]; then
    if [[ -L "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE" ]]; then
      prividium_fail \
        "local age identity must not be a symbolic link: ${PRIVIDIUM_DEFAULT_AGE_KEY_FILE}"
    fi
    age_key_file="$PRIVIDIUM_DEFAULT_AGE_KEY_FILE"
    age_identity_label="Local age identity"
    age_identity_display="deployment/secrets/age.key"
    age_identity_message="Reusing local age identity"
  elif [[ -n "${SOPS_AGE_RECIPIENT:-}" ]]; then
    prividium_fail "SOPS_AGE_RECIPIENT requires a matching SOPS_AGE_KEY_FILE"
  else
    mkdir -p "$(dirname "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE")"
    if ! age-keygen -o "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE" >/dev/null 2>&1; then
      prividium_fail \
        "could not create local age identity: ${PRIVIDIUM_DEFAULT_AGE_KEY_FILE}"
    fi
    age_key_file="$PRIVIDIUM_DEFAULT_AGE_KEY_FILE"
    age_identity_label="Local age identity"
    age_identity_display="deployment/secrets/age.key"
    age_identity_message="Created local age identity"
  fi

  if [[ ! -f "$age_key_file" || ! -s "$age_key_file" || ! -r "$age_key_file" ]]; then
    prividium_fail "age identity is not a readable, nonempty regular file: ${age_key_file}"
  fi
  if [[ "$age_key_file" == "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE" ]]; then
    chmod 0600 "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE"
  fi
  export SOPS_AGE_KEY_FILE="$age_key_file"
  prividium_resolve_age_identity
  age_key_file="$SOPS_AGE_KEY_FILE"

  if ! derived_recipient=$(age-keygen -y "$age_key_file"); then
    prividium_fail "could not derive an age recipient from ${age_key_file}"
  fi
  if [[ -z "$derived_recipient" || "$derived_recipient" == *$'\n'* ]]; then
    prividium_fail "age identity must contain exactly one identity"
  fi
  if [[ -n "${SOPS_AGE_RECIPIENT:-}" &&
        "$SOPS_AGE_RECIPIENT" != "$derived_recipient" ]]; then
    prividium_fail "SOPS_AGE_RECIPIENT does not match SOPS_AGE_KEY_FILE"
  fi

  export SOPS_AGE_RECIPIENT="$derived_recipient"

  printf "✓ %s\n" "$age_identity_message"
  OVERWRITE_SECRETS=false \
    SECRETS_OUTPUT="$PRIVIDIUM_ENCRYPTED_ENVIRONMENT" \
    "${PRIVIDIUM_REPO_ROOT}/tools/init-secrets"

  printf "\nEvaluation users — available after deployment\n\n"
  printf "%-28s %-24s %s\n" "EMAIL" "PASSWORD" "ROLE"
  printf "%-28s %-24s %s\n" \
    "$(prividium_display_credential "$SANDBOX_ADMIN_EMAIL" "$admin_email_configured")" \
    "$(prividium_display_credential "$SANDBOX_ADMIN_PASSWORD" "$admin_password_configured")" \
    "administrator; change password at first sign-in"
  printf "%-28s %-24s %s\n" \
    "$(prividium_display_credential "$SANDBOX_USER_1_EMAIL" "$user_1_email_configured")" \
    "$(prividium_display_credential "$SANDBOX_USER_1_PASSWORD" "$user_1_password_configured")" \
    "user"
  printf "%-28s %-24s %s\n" \
    "$(prividium_display_credential "$SANDBOX_USER_2_EMAIL" "$user_2_email_configured")" \
    "$(prividium_display_credential "$SANDBOX_USER_2_PASSWORD" "$user_2_password_configured")" \
    "user"

  if [[ "$age_key_file" == "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE" ]]; then
    printf "\nGenerated files\n\n"
  else
    printf "\nConfiguration files\n\n"
  fi
  printf "%-25s %s\n" "Encrypted configuration" "deployment/secrets/sandbox.enc.env"
  printf "%-25s %s\n" "$age_identity_label" "$age_identity_display"
  printf "%-25s %s\n" "Public role inventory" "deployment/public/roles.md"
  printf "\nInitialization complete.\n"
  printf "Next: ./cli/prividium fund\n"
}
