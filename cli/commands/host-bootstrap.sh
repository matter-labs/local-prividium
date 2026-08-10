#!/usr/bin/env bash

prividium_host_bootstrap_usage() {
  cat <<'EOF'
Validate the local operator before preparing the evaluation VPS.

Usage:
  ./cli/prividium host bootstrap

Options:
  -h, --help  Show this help

Bootstrap is read-only. It confirms that this command is running locally on
Ubuntu 24.04 amd64 as a normal operator with passwordless sudo and the tools
needed to run host preflight. It does not install packages, configure SSH or
firewalls, create inventory, or deploy the Prividium stack.
EOF
}

prividium_host_bootstrap() {
  local current_user
  local show_help="false"

  while (( $# )); do
    case "$1" in
      -h|--help)
        show_help="true"
        shift
        ;;
      -*)
        prividium_fail "unknown host bootstrap option: $1"
        ;;
      *)
        prividium_fail "unexpected host bootstrap argument: $1"
        ;;
    esac
  done

  if [[ "$show_help" == "true" ]]; then
    prividium_host_bootstrap_usage
    return
  fi

  current_user=$(id -un)
  if [[ "$current_user" == "root" ]]; then
    prividium_fail \
      "host bootstrap must run as a normal passwordless-sudo operator, not root; run './cli/prividium host operator create', verify a second SSH login, then continue from an operator-owned clone"
  fi
  if [[ ! "$current_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    prividium_fail "current user is not a supported Linux username"
  fi

  prividium_require_commands \
    "host bootstrap" apt-get awk df dpkg-query getconf grep id python3 ss \
    stat sudo systemctl uname

  if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]] ||
     [[ ! -r /etc/os-release ]] ||
     ! grep -Eq '^ID="?ubuntu"?$' /etc/os-release ||
     ! grep -Eq '^VERSION_ID="?24\.04"?$' /etc/os-release; then
    prividium_fail "host bootstrap supports only Ubuntu 24.04 amd64"
  fi
  if ! sudo -n true; then
    prividium_fail "current operator must have validated passwordless sudo"
  fi
  if [[ ! -d /run/systemd/system ]]; then
    prividium_fail "host bootstrap requires a conventional systemd VPS"
  fi

  printf "Prividium host bootstrap passed.\n\n"
  printf "Operator: %s\n" "$current_user"
  printf "Platform: Ubuntu 24.04 amd64\n"
  printf "Mode:     read-only local guard\n\n"
  printf "Next: ./cli/prividium host preflight\n"
}
