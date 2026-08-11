#!/usr/bin/env bash

PRIVIDIUM_HOST_MARKER=/etc/prividium/.host-contract-version
PRIVIDIUM_HOST_MARKER_VALUE=host-contract-v1
PRIVIDIUM_HOST_RUNTIME=/etc/prividium/runtime
PRIVIDIUM_HOST_TARGET_VCPUS=8
PRIVIDIUM_HOST_TARGET_MEMORY_KIB=15728640
PRIVIDIUM_HOST_TARGET_ROOT_BYTES=190000000000
PRIVIDIUM_HOST_SOPS_VERSION=3.13.3
PRIVIDIUM_HOST_SOPS_SHA256=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b
PRIVIDIUM_HOST_FOUNDRY_VERSION=1.5.1
PRIVIDIUM_HOST_FOUNDRY_SHA256=73640b01bd9ed29fdb4965085099371f8cf0dbbec3e2086cf54564efc4dcfe88
PRIVIDIUM_HOST_DOCKER_KEY_SHA256=1500c1f56fa9e26b9b8f42452a553675796ade0807cdce11975eb98170b3a570

prividium_host_fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

prividium_host_require_commands() {
  local command
  local missing=()

  for command in "$@"; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
  done
  if (( ${#missing[@]} )); then
    prividium_host_fail "missing commands: ${missing[*]}"
  fi
}

prividium_host_mode() {
  stat -c '%a' "$1"
}

prividium_host_owner_group() {
  stat -c '%U:%G' "$1"
}

prividium_host_marker_is_valid() {
  [[ -f "$PRIVIDIUM_HOST_MARKER" && ! -L "$PRIVIDIUM_HOST_MARKER" ]] || return 1
  prividium_host_marker_values_are_valid \
    "$(prividium_host_mode "$PRIVIDIUM_HOST_MARKER")" \
    "$(prividium_host_owner_group "$PRIVIDIUM_HOST_MARKER")" \
    "$(tr -d '\r\n' < "$PRIVIDIUM_HOST_MARKER")"
}

prividium_host_marker_values_are_valid() {
  [[ "$1" == "644" && "$2" == "root:root" &&
     "$3" == "$PRIVIDIUM_HOST_MARKER_VALUE" ]]
}

prividium_host_require_operator() {
  local current_user

  current_user=$(id -un)
  [[ "$current_user" != "root" ]] ||
    prividium_host_fail "run as the normal passwordless-sudo operator, not root"
  [[ "$current_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] ||
    prividium_host_fail "current operator username is unsupported"
  sudo -n true ||
    prividium_host_fail "current operator must have passwordless sudo"
}

prividium_host_assert_platform() {
  local os_id="$1"
  local os_version="$2"
  local kernel="$3"
  local architecture="$4"
  local systemd_present="$5"

  [[ "$os_id" == "ubuntu" && "$os_version" == "24.04" ]] ||
    prividium_host_fail "supported operating system is exactly Ubuntu 24.04"
  [[ "$kernel" == "Linux" && "$architecture" == "x86_64" ]] ||
    prividium_host_fail "supported platform is Linux amd64"
  [[ "$systemd_present" == "true" ]] ||
    prividium_host_fail "a conventional systemd VPS is required"
}

prividium_host_print_install_plan() {
  cat <<EOF
Planned host changes

  1. Apply safe Ubuntu package upgrades.
  2. Install age, Chrony, curl, Git, GnuPG, jq, OpenSSL, Python apt support,
     unattended upgrades, and supporting packages.
  3. Install checksum-pinned SOPS ${PRIVIDIUM_HOST_SOPS_VERSION} and Foundry
     ${PRIVIDIUM_HOST_FOUNDRY_VERSION} under system-owned paths.
  4. Configure Docker's official Ubuntu 24.04 repository and install Docker
     Engine, containerd, Buildx, and Compose v2.
  5. Merge bounded json-file logging (10 MB x 3) into daemon.json and enable
     Docker, Chrony, unattended upgrades, and apt maintenance timers.
  6. Add the current operator to the root-equivalent docker group.
  7. Create root-owned /etc/prividium, record host-contract-v1, and create an
     operator-owned /etc/prividium/runtime with mode 0700.

Explicitly excluded

  SSH configuration, host/provider firewall rules, DNS, Quay authentication,
  RPC credentials, protocol keys, and application deployment.
EOF
}

prividium_host_file_has_line() {
  local file="$1"
  local expected="$2"

  [[ -f "$file" ]] && grep -Fqx "$expected" "$file"
}
