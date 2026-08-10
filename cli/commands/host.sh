#!/usr/bin/env bash

prividium_host_usage() {
  cat <<'EOF'
Assess, prepare, and verify this Prividium evaluation VPS.

Usage:
  ./cli/prividium host operator create [options]
  ./cli/prividium host bootstrap
  ./cli/prividium host preflight
  ./cli/prividium host install [--check] [--yes]
  ./cli/prividium host verify
  ./cli/prividium host --help

Commands:
  operator   Create the non-root operator on a root-only VPS
  bootstrap  Validate the local operator and bootstrap tools (read-only)
  preflight  Assess this local VPS against the supported host contract
  install    Install packages, tools, Docker, and protected directories
  verify     Verify the complete installed host contract

All host commands operate only on the current VPS. Remote inventories and
remote-host execution are not supported.
EOF
}

prividium_host() {
  local subcommand="${1:-help}"

  shift || true
  case "$subcommand" in
    help|-h|--help)
      if (( $# )); then
        prividium_fail "unexpected host argument: $1"
      fi
      prividium_host_usage
      ;;
    bootstrap)
      source "${PRIVIDIUM_REPO_ROOT}/cli/commands/host-bootstrap.sh"
      prividium_host_bootstrap "$@"
      ;;
    operator)
      source "${PRIVIDIUM_REPO_ROOT}/cli/commands/host-operator.sh"
      prividium_host_operator "$@"
      ;;
    preflight)
      "${PRIVIDIUM_REPO_ROOT}/tools/host/preflight" "$@"
      ;;
    install)
      "${PRIVIDIUM_REPO_ROOT}/tools/host/install" "$@"
      ;;
    verify)
      "${PRIVIDIUM_REPO_ROOT}/tools/host/verify" "$@"
      ;;
    *)
      prividium_fail "unknown host command: ${subcommand}"
      ;;
  esac
}
