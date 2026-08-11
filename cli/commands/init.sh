#!/usr/bin/env bash

prividium_init_usage() {
  cat <<'EOF'
Initialize a Prividium evaluation sandbox from a protected input file.

Usage:
  ./cli/prividium init [--profile sandbox] [--env-file <path>]

Options:
  --profile sandbox  Sandbox profile to initialize (default: sandbox)
  --env-file <path>  Human input file (default: deployment/input.env)
  -h, --help         Show this help

The input file must be owned by the current operator with mode 0600 and contain
SANDBOX_DOMAIN, ACME_EMAIL, SEPOLIA_RPC_URL, and SEPOLIA_BROWSER_RPC_URL.
L2_CHAIN_ID is optional; when omitted, a high-range ID is generated. The file
is parsed as data; shell expansion is never run.

Initialization generates strong random evaluation passwords and stores them
only in the SOPS-encrypted configuration. Reveal them later with the explicit
TTY-only command: ./cli/prividium credentials show

Age encryption uses SOPS_AGE_KEY_FILE when supplied; SOPS_AGE_RECIPIENT may
also be set when it matches that identity. Otherwise, a local identity is
generated at deployment/secrets/age.key.
EOF
}

prividium_init_load_input() {
  local input_file="$1"
  local parsed_file
  local name
  local value

  parsed_file=$(mktemp)
  if ! "${PRIVIDIUM_REPO_ROOT}/tools/parse-input-env" "$input_file" > "$parsed_file"; then
    rm -f -- "$parsed_file"
    return 1
  fi
  while IFS= read -r -d '' name && IFS= read -r -d '' value; do
    printf -v "$name" '%s' "$value"
    export "$name"
  done < "$parsed_file"
  rm -f -- "$parsed_file"
}

prividium_init() {
  local profile="sandbox"
  local input_file="${PRIVIDIUM_REPO_ROOT}/deployment/input.env"
  local age_identity_label
  local age_identity_display
  local age_identity_message
  local age_key_file
  local browser_rpc_comparison
  local derived_recipient
  local private_rpc_comparison
  local rpc_url_pattern='^https://[A-Za-z0-9:/?&=._%+-]+$'
  local email_pattern='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$'
  local show_help="false"

  while (( $# )); do
    case "$1" in
      -h|--help)
        show_help="true"
        shift
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
      --env-file)
        (( $# >= 2 )) || prividium_fail "--env-file requires a value"
        input_file="$2"
        shift 2
        ;;
      --env-file=*)
        input_file="${1#--env-file=}"
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
    "sandbox initialization" age age-keygen sops cast openssl curl jq python3
  if ! prividium_init_load_input "$input_file"; then
    prividium_fail "sandbox input validation failed"
  fi

  export SANDBOX_ADMIN_EMAIL=admin@local.dev
  export SANDBOX_ADMIN_PASSWORD
  SANDBOX_ADMIN_PASSWORD=$(openssl rand -hex 16)
  export SANDBOX_USER_1_EMAIL=user1@local.dev
  export SANDBOX_USER_1_PASSWORD
  SANDBOX_USER_1_PASSWORD=$(openssl rand -hex 16)
  export SANDBOX_USER_2_EMAIL=user2@local.dev
  export SANDBOX_USER_2_PASSWORD
  SANDBOX_USER_2_PASSWORD=$(openssl rand -hex 16)

  printf "Prividium sandbox initialization\n"
  printf "Profile: %s\n" "$profile"
  printf "Input:   %s (validated; values hidden)\n\n" "$input_file"

  if ! prividium_domain_is_valid "$SANDBOX_DOMAIN"; then
    prividium_fail \
      "SANDBOX_DOMAIN must be a valid lower-case DNS name with labels no longer than 63 characters"
  fi
  if [[ ! "$ACME_EMAIL" =~ $email_pattern ]]; then
    prividium_fail "ACME_EMAIL is invalid"
  fi
  if [[ -n "${L2_CHAIN_ID:-}" ]] &&
     { [[ ! "$L2_CHAIN_ID" =~ ^[0-9]+$ ]] ||
       (( L2_CHAIN_ID < 1073741824 || L2_CHAIN_ID > 2147483647 )); }; then
    prividium_fail "L2_CHAIN_ID must be in 1073741824..2147483647 when supplied"
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

  if [[ "$age_key_file" == "$PRIVIDIUM_DEFAULT_AGE_KEY_FILE" ]]; then
    printf "\nGenerated files\n\n"
  else
    printf "\nConfiguration files\n\n"
  fi
  printf "%-25s %s\n" "Encrypted configuration" "deployment/secrets/sandbox.enc.env"
  printf "%-25s %s\n" "$age_identity_label" "$age_identity_display"
  printf "%-25s %s\n" "Public role inventory" "deployment/public/roles.md"
  printf "\nEvaluation passwords were generated and not printed.\n"
  printf "Reveal them explicitly after deployment with: ./cli/prividium credentials show\n"
  printf "After verifying these outputs, remove the plaintext input file: %s\n" "$input_file"
  printf "\nInitialization complete.\n"
  printf "Next: ./cli/prividium fund\n"
}
