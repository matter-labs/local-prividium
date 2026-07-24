#!/usr/bin/env bash

prividium_host_usage() {
  cat <<'EOF'
Assess a dedicated Prividium evaluation VPS with Ansible.

Usage:
  ./cli/prividium host preflight --inventory <path>
  ./cli/prividium host --help

Options:
  --inventory <path>  One-host Ansible inventory (required)
  -h, --help          Show this help

The preflight is non-interactive and read-only. The wrapper accepts no Ansible
pass-through options and always enables check mode. It does not install
packages, change SSH or firewall rules, create directories, authenticate to
Quay, or invoke the application deployment workflow.
EOF
}

prividium_host_inventory_summary() {
  local inventory="$1"

  ANSIBLE_CONFIG="${PRIVIDIUM_REPO_ROOT}/ansible/ansible.cfg" \
    ansible-inventory \
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
values = (name, address, user, port)
if not user:
    print("Error: target ansible_user must be explicit", file=sys.stderr)
    raise SystemExit(2)
if any(any(character in value for character in "\t\r\n") for value in values):
    print("Error: target inventory values contain control characters", file=sys.stderr)
    raise SystemExit(2)
print("\t".join(values))
'
}

prividium_host_preflight() {
  local inventory=""
  local inventory_dir
  local inventory_example
  local inventory_host
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
        shift 2
        ;;
      --inventory=*)
        inventory="${1#--inventory=}"
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
    prividium_host_usage
    return
  fi
  if [[ -z "$inventory" ]]; then
    prividium_fail "host preflight requires --inventory <path>"
  fi
  if [[ ! -f "$inventory" || ! -r "$inventory" ]]; then
    prividium_fail "host inventory is not a readable regular file: ${inventory}"
  fi

  inventory_dir=$(cd "$(dirname "$inventory")" && pwd -P)
  inventory="${inventory_dir}/$(basename "$inventory")"
  inventory_example="${PRIVIDIUM_REPO_ROOT}/ansible/inventory/example.ini"
  if [[ "$inventory" == "$inventory_example" ]]; then
    prividium_fail \
      "the documentation-only example inventory cannot be executed; copy and edit it first"
  fi

  prividium_require_commands \
    "read-only host preflight" \
    ansible-inventory \
    ansible-playbook \
    python3

  inventory_summary=$(prividium_host_inventory_summary "$inventory")
  IFS=$'\t' read -r \
    inventory_host \
    target_address \
    target_user \
    target_port <<< "$inventory_summary"

  printf "Prividium read-only host preflight\n\n"
  printf "Inventory: %s\n" "$inventory"
  printf "Target:    %s (%s)\n" "$inventory_host" "$target_address"
  printf "SSH:       %s@%s:%s\n" \
    "$target_user" \
    "$target_address" \
    "$target_port"
  printf "Mode:      Ansible check mode; no remediation\n\n"

  (
    cd "${PRIVIDIUM_REPO_ROOT}/ansible"
    ANSIBLE_CONFIG="${PRIVIDIUM_REPO_ROOT}/ansible/ansible.cfg" \
      ansible-playbook \
        --inventory "$inventory" \
        --check \
        playbooks/preflight.yml
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
    preflight)
      prividium_host_preflight "$@"
      ;;
    *)
      prividium_fail "unknown host command: ${subcommand}"
      ;;
  esac
}
