#!/usr/bin/env bash

prividium_credentials_usage() {
  cat <<'EOF'
Reveal generated evaluation login credentials.

Usage:
  ./cli/prividium credentials show

The show command requires an interactive terminal and explicit confirmation.
It decrypts only the evaluation URLs and login credentials and refuses
redirected output. Never run it in an agent transcript or shared terminal log.
EOF
}

prividium_credentials() {
  local subcommand="${1:-help}"
  local confirmation

  shift || true
  case "$subcommand" in
    help|-h|--help)
      (( $# == 0 )) || prividium_fail "unexpected credentials argument: $1"
      prividium_credentials_usage
      ;;
    show)
      (( $# == 0 )) || prividium_fail "unexpected credentials show argument: $1"
      [[ -t 0 && -t 1 ]] ||
        prividium_fail "credentials show requires an interactive terminal and refuses redirected output"
      prividium_require_encrypted_environment
      prividium_resolve_age_identity
      prividium_require_commands "credential reveal" sops
      printf 'This prints evaluation passwords in the current terminal.\n'
      read -r -p 'Type SHOW to continue: ' confirmation
      [[ "$confirmation" == "SHOW" ]] || {
        printf 'Credential reveal cancelled.\n'
        return
      }
      "${PRIVIDIUM_REPO_ROOT}/tools/show-credentials" \
        "$PRIVIDIUM_ENCRYPTED_ENVIRONMENT"
      ;;
    *)
      prividium_fail "unknown credentials command: ${subcommand}"
      ;;
  esac
}
