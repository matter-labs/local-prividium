#!/usr/bin/env bash

prividium_host_usage() {
  cat <<'EOF'
Bootstrap, assess, provision, and verify a dedicated Prividium evaluation VPS.

Usage:
  ./cli/prividium host operator create [options]
  ./cli/prividium host bootstrap
  ./cli/prividium host preflight [--inventory <path>]
  ./cli/prividium host install [--check] [--yes] [--inventory <path>]
  ./cli/prividium host verify [--inventory <path>]
  ./cli/prividium host --help

Commands:
  operator   Create the non-root operator on a root-only VPS
  bootstrap  Create the pinned Ansible environment and local inventory
  preflight  Run the read-only one-host compatibility assessment
  install    Provision packages, tools, Docker, and protected directories
  verify     Verify the Ansible-managed host installation

First use:
  ./cli/prividium host bootstrap
  ./cli/prividium host preflight
  ./cli/prividium host install --check
  ./cli/prividium host install
  # Reconnect so Docker group membership applies.
  ./cli/prividium host verify

Run ./cli/prividium host <command> --help for command-specific help.
EOF
}

prividium_host_preflight_usage() {
  cat <<'EOF'
Run the read-only Ansible compatibility assessment.

Usage:
  ./cli/prividium host preflight [--inventory <path>]

Options:
  --inventory <path>  Override the bootstrapped one-host inventory
  -h, --help          Show this help

The default inventory is ansible/inventory/hosts.ini. The command automatically
uses the pinned ansible/.venv created by host bootstrap. It accepts no Ansible
pass-through options and always enables check mode.
EOF
}

prividium_host_install_usage() {
  cat <<'EOF'
Provision the supported Prividium evaluation host.

Usage:
  ./cli/prividium host install [--check] [--yes] [--inventory <path>]

Options:
  --check             Review the installation plan without changing the host
  --yes               Skip the interactive INSTALL confirmation during apply
  --inventory <path>  Override the bootstrapped one-host inventory
  -h, --help          Show this help

Apply installs safe Ubuntu upgrades and baseline packages, pinned SOPS and
Foundry tools, Docker Engine and Compose, bounded Docker logs, time and
unattended-upgrade services, and protected Prividium directories.

It reruns the read-only host preflight immediately before installation. It
does not change SSH, activate firewall rules, authenticate to Quay, or deploy
the application stack. Non-interactive apply requires --yes.
EOF
}

prividium_host_verify_usage() {
  cat <<'EOF'
Verify the Ansible-managed Prividium host installation.

Usage:
  ./cli/prividium host verify [--inventory <path>]

Options:
  --inventory <path>  Override the bootstrapped one-host inventory
  -h, --help          Show this help

Verification is read-only. It checks installed packages and pinned tools,
Docker and Compose readiness, enabled services, Docker group membership,
bounded log configuration, and protected directory ownership.

Provider firewall configuration, Quay authentication, and application
deployment remain separate customer-controlled actions. Host firewall
automation is deferred.
EOF
}

prividium_host_inventory_summary() {
  local ansible_inventory_bin="$1"
  local inventory="$2"

  ANSIBLE_CONFIG="${PRIVIDIUM_REPO_ROOT}/ansible/ansible.cfg" \
    "$ansible_inventory_bin" \
      --inventory "$inventory" \
      --list |
    python3 -c '
import json
import sys

document = json.load(sys.stdin)
hosts = document.get("prividium", {}).get("hosts", [])
if len(hosts) != 1:
    print(
        "Error: inventory must contain exactly one host in the prividium group",
        file=sys.stderr,
    )
    raise SystemExit(2)

name = hosts[0]
variables = document.get("_meta", {}).get("hostvars", {}).get(name, {})
address = str(variables.get("ansible_host", name))
user = str(variables.get("ansible_user", ""))
port = str(variables.get("ansible_port", "22"))
connection = str(variables.get("ansible_connection", "ssh"))
values = (name, address, user, port, connection)
if not user:
    print("Error: target ansible_user must be explicit", file=sys.stderr)
    raise SystemExit(2)
if any(any(character in value for character in "\t\r\n") for value in values):
    print("Error: target inventory values contain control characters", file=sys.stderr)
    raise SystemExit(2)
print("\t".join(values))
'
}

prividium_host_resolve_ansible_binaries() {
  local allow_path_fallback="$1"
  local ansible_inventory_bin
  local ansible_playbook_bin

  ansible_inventory_bin="${PRIVIDIUM_REPO_ROOT}/ansible/.venv/bin/ansible-inventory"
  ansible_playbook_bin="${PRIVIDIUM_REPO_ROOT}/ansible/.venv/bin/ansible-playbook"
  if [[ ! -x "$ansible_inventory_bin" || ! -x "$ansible_playbook_bin" ]]; then
    if [[ "$allow_path_fallback" != "true" ]]; then
      prividium_fail \
        "pinned Ansible environment is missing; run ./cli/prividium host bootstrap"
    fi
    if ! ansible_inventory_bin=$(command -v ansible-inventory) ||
      ! ansible_playbook_bin=$(command -v ansible-playbook); then
      prividium_fail \
        "pinned Ansible environment is missing; run ./cli/prividium host bootstrap"
    fi
  fi

  printf "%s\t%s\n" "$ansible_inventory_bin" "$ansible_playbook_bin"
}

prividium_host_resolve_inventory() {
  local inventory="$1"
  local inventory_dir
  local inventory_example

  if [[ ! -f "$inventory" || ! -r "$inventory" ]]; then
    if [[ "$inventory" == "${PRIVIDIUM_REPO_ROOT}/ansible/inventory/hosts.ini" ]]; then
      prividium_fail \
        "host bootstrap is incomplete; run ./cli/prividium host bootstrap"
    fi
    prividium_fail "host inventory is not a readable regular file: ${inventory}"
  fi

  inventory_dir=$(cd "$(dirname "$inventory")" && pwd -P)
  inventory="${inventory_dir}/$(basename "$inventory")"
  inventory_example="${PRIVIDIUM_REPO_ROOT}/ansible/inventory/example.ini"
  if [[ "$inventory" == "$inventory_example" ]]; then
    prividium_fail \
      "the documentation-only example inventory cannot be executed; run ./cli/prividium host bootstrap"
  fi

  printf "%s\n" "$inventory"
}

prividium_host_preflight() {
  local ansible_binaries
  local ansible_inventory_bin
  local ansible_playbook_bin
  local connection
  local inventory="${PRIVIDIUM_REPO_ROOT}/ansible/inventory/hosts.ini"
  local inventory_host
  local inventory_overridden="false"
  local inventory_summary
  local show_help="false"
  local target_address
  local target_port
  local target_user

  while (( $# )); do
    case "$1" in
      -h|--help)
        show_help="true"
        shift
        ;;
      --inventory)
        if (( $# < 2 )); then
          prividium_fail "--inventory requires a value"
        fi
        inventory="$2"
        inventory_overridden="true"
        shift 2
        ;;
      --inventory=*)
        inventory="${1#--inventory=}"
        inventory_overridden="true"
        shift
        ;;
      -*)
        prividium_fail "unknown host preflight option: $1"
        ;;
      *)
        prividium_fail "unexpected host preflight argument: $1"
        ;;
    esac
  done

  if [[ "$show_help" == "true" ]]; then
    prividium_host_preflight_usage
    return
  fi

  inventory=$(prividium_host_resolve_inventory "$inventory")
  prividium_require_commands "read-only host preflight" python3
  ansible_binaries=$(
    prividium_host_resolve_ansible_binaries "$inventory_overridden"
  )
  IFS=$'\t' read -r \
    ansible_inventory_bin \
    ansible_playbook_bin <<< "$ansible_binaries"

  inventory_summary=$(
    prividium_host_inventory_summary "$ansible_inventory_bin" "$inventory"
  )
  IFS=$'\t' read -r \
    inventory_host \
    target_address \
    target_user \
    target_port \
    connection <<< "$inventory_summary"

  printf "Prividium read-only host preflight\n\n"
  printf "Inventory: %s\n" "$inventory"
  printf "Target:    %s (%s)\n" "$inventory_host" "$target_address"
  if [[ "$connection" == "local" ]]; then
    printf "Connection: local as %s\n" "$target_user"
  else
    printf "SSH:       %s@%s:%s\n" \
      "$target_user" \
      "$target_address" \
      "$target_port"
  fi
  printf "Mode:      Ansible check mode; no remediation\n\n"

  (
    cd "${PRIVIDIUM_REPO_ROOT}/ansible"
    ANSIBLE_CONFIG="${PRIVIDIUM_REPO_ROOT}/ansible/ansible.cfg" \
      "$ansible_playbook_bin" \
        --inventory "$inventory" \
        --check \
        playbooks/preflight.yml
  )
}

prividium_host_install() {
  local ansible_binaries
  local ansible_inventory_bin
  local ansible_playbook_bin
  local apply_confirmed="false"
  local check_mode="false"
  local confirmation
  local connection
  local inventory="${PRIVIDIUM_REPO_ROOT}/ansible/inventory/hosts.ini"
  local inventory_host
  local inventory_overridden="false"
  local inventory_summary
  local playbook_arguments=()
  local show_help="false"
  local target_address
  local target_port
  local target_user

  while (( $# )); do
    case "$1" in
      -h|--help)
        show_help="true"
        shift
        ;;
      --check)
        check_mode="true"
        shift
        ;;
      --yes)
        apply_confirmed="true"
        shift
        ;;
      --inventory)
        (( $# >= 2 )) || prividium_fail "--inventory requires a value"
        inventory="$2"
        inventory_overridden="true"
        shift 2
        ;;
      --inventory=*)
        inventory="${1#--inventory=}"
        inventory_overridden="true"
        shift
        ;;
      -*)
        prividium_fail "unknown host install option: $1"
        ;;
      *)
        prividium_fail "unexpected host install argument: $1"
        ;;
    esac
  done

  if [[ "$show_help" == "true" ]]; then
    prividium_host_install_usage
    return
  fi
  if [[ "$check_mode" == "true" && "$apply_confirmed" == "true" ]]; then
    prividium_fail "--yes cannot be combined with --check"
  fi

  inventory=$(prividium_host_resolve_inventory "$inventory")
  prividium_require_commands "host installation" python3
  ansible_binaries=$(
    prividium_host_resolve_ansible_binaries "$inventory_overridden"
  )
  IFS=$'\t' read -r \
    ansible_inventory_bin \
    ansible_playbook_bin <<< "$ansible_binaries"

  inventory_summary=$(
    prividium_host_inventory_summary "$ansible_inventory_bin" "$inventory"
  )
  IFS=$'\t' read -r \
    inventory_host \
    target_address \
    target_user \
    target_port \
    connection <<< "$inventory_summary"

  printf "Prividium host installation\n\n"
  printf "Inventory: %s\n" "$inventory"
  printf "Target:    %s (%s)\n" "$inventory_host" "$target_address"
  printf "Operator:  %s\n" "$target_user"
  if [[ "$connection" == "local" ]]; then
    printf "Connection: local\n"
  else
    printf "Connection: SSH %s@%s:%s\n" \
      "$target_user" \
      "$target_address" \
      "$target_port"
  fi
  printf "Mode:      %s\n\n" \
    "$([[ "$check_mode" == "true" ]] && printf "check; no host changes" || printf "apply")"
  printf "Managed: Ubuntu packages, security services, pinned tools, Docker,\n"
  printf "         bounded logs, operator group, and protected directories.\n"
  printf "Excluded: SSH, firewall activation, provider rules, Quay credentials,\n"
  printf "          and application deployment.\n\n"

  if [[ "$check_mode" != "true" && "$apply_confirmed" != "true" ]]; then
    if [[ ! -t 0 ]]; then
      prividium_fail \
        "non-interactive host installation requires --yes after reviewing --check"
    fi
    read -r -p "Type INSTALL to apply these host changes: " confirmation
    if [[ "$confirmation" != "INSTALL" ]]; then
      printf "Host installation cancelled; no playbook was run.\n"
      return
    fi
  fi

  playbook_arguments=(
    --inventory "$inventory"
    --diff
  )
  if [[ "$check_mode" == "true" ]]; then
    playbook_arguments+=(--check)
  fi
  playbook_arguments+=(playbooks/install.yml)

  (
    cd "${PRIVIDIUM_REPO_ROOT}/ansible"
    ANSIBLE_CONFIG="${PRIVIDIUM_REPO_ROOT}/ansible/ansible.cfg" \
      "$ansible_playbook_bin" "${playbook_arguments[@]}"
  )

  if [[ "$check_mode" == "true" ]]; then
    printf "\nNext: ./cli/prividium host install\n"
  else
    printf "\nReconnect the operator SSH session, then run:\n"
    printf "  ./cli/prividium host verify\n"
  fi
}

prividium_host_verify() {
  local ansible_binaries
  local ansible_inventory_bin
  local ansible_playbook_bin
  local connection
  local inventory="${PRIVIDIUM_REPO_ROOT}/ansible/inventory/hosts.ini"
  local inventory_host
  local inventory_overridden="false"
  local inventory_summary
  local show_help="false"
  local target_address
  local target_port
  local target_user

  while (( $# )); do
    case "$1" in
      -h|--help)
        show_help="true"
        shift
        ;;
      --inventory)
        (( $# >= 2 )) || prividium_fail "--inventory requires a value"
        inventory="$2"
        inventory_overridden="true"
        shift 2
        ;;
      --inventory=*)
        inventory="${1#--inventory=}"
        inventory_overridden="true"
        shift
        ;;
      -*)
        prividium_fail "unknown host verify option: $1"
        ;;
      *)
        prividium_fail "unexpected host verify argument: $1"
        ;;
    esac
  done

  if [[ "$show_help" == "true" ]]; then
    prividium_host_verify_usage
    return
  fi

  inventory=$(prividium_host_resolve_inventory "$inventory")
  prividium_require_commands "host installation verification" python3
  ansible_binaries=$(
    prividium_host_resolve_ansible_binaries "$inventory_overridden"
  )
  IFS=$'\t' read -r \
    ansible_inventory_bin \
    ansible_playbook_bin <<< "$ansible_binaries"

  inventory_summary=$(
    prividium_host_inventory_summary "$ansible_inventory_bin" "$inventory"
  )
  IFS=$'\t' read -r \
    inventory_host \
    target_address \
    target_user \
    target_port \
    connection <<< "$inventory_summary"

  printf "Prividium host installation verification\n\n"
  printf "Inventory: %s\n" "$inventory"
  printf "Target:    %s (%s)\n" "$inventory_host" "$target_address"
  printf "Operator:  %s\n" "$target_user"
  if [[ "$connection" == "local" ]]; then
    printf "Connection: local\n"
  else
    printf "Connection: SSH %s@%s:%s\n" \
      "$target_user" \
      "$target_address" \
      "$target_port"
  fi
  printf "Mode:      read-only Ansible check mode\n\n"

  (
    cd "${PRIVIDIUM_REPO_ROOT}/ansible"
    ANSIBLE_CONFIG="${PRIVIDIUM_REPO_ROOT}/ansible/ansible.cfg" \
      "$ansible_playbook_bin" \
        --inventory "$inventory" \
        --check \
        playbooks/verify.yml
  )
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
      prividium_host_preflight "$@"
      ;;
    install)
      prividium_host_install "$@"
      ;;
    verify)
      prividium_host_verify "$@"
      ;;
    *)
      prividium_fail "unknown host command: ${subcommand}"
      ;;
  esac
}
