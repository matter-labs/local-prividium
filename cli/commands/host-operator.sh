#!/usr/bin/env bash

prividium_host_operator_usage() {
  cat <<'EOF'
Create the non-root operator required by the evaluation workflow.

Usage:
  ./cli/prividium host operator create [options]

Options:
  --user <name>                    Operator username (default: prividium)
  --public-key <key>               One OpenSSH public key
  --public-key-file <path>         File containing one OpenSSH public key
  --copy-current-authorized-keys   Reuse /root/.ssh/authorized_keys
  --yes                            Skip the interactive CREATE confirmation
  -h, --help                       Show this help

Run this command only from an initial root session on a supported Ubuntu VPS.
Interactive use automatically offers the current root authorized-keys file.
Non-interactive use requires an explicit key-source option and --yes.

The command creates or verifies a locked-password operator, its authorized
keys, sudo-group membership, and a validated passwordless-sudo policy. It does
not alter sshd, root access, firewall rules, or Docker groups. A second SSH
connection as the new operator must be verified before continuing.
EOF
}

prividium_host_operator_username_is_valid() {
  local username="$1"

  [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$username" != "root" ]]
}

prividium_host_operator_normalize_keys() {
  local source_kind="$1"
  local source_value="$2"

  python3 -c '
import base64
import binascii
from pathlib import Path
import sys

kind, value = sys.argv[1:]
supported = {
    "ssh-ed25519",
    "ssh-rsa",
    "ecdsa-sha2-nistp256",
    "ecdsa-sha2-nistp384",
    "ecdsa-sha2-nistp521",
    "sk-ssh-ed25519@openssh.com",
    "sk-ecdsa-sha2-nistp256@openssh.com",
}

if kind == "text":
    if "\n" in value or "\r" in value:
        raise SystemExit("public key must be one line")
    lines = [value]
    allow_options = False
elif kind == "file":
    lines = Path(value).read_text().splitlines()
    allow_options = False
elif kind == "authorized_keys":
    lines = Path(value).read_text().splitlines()
    allow_options = True
else:
    raise SystemExit("unsupported public-key source")

normalized = []
for raw_line in lines:
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    fields = line.split()
    try:
        index = next(index for index, field in enumerate(fields) if field in supported)
    except StopIteration:
        raise SystemExit(
            "each authorized-key line must contain one supported key"
        ) from None
    if not allow_options and index != 0:
        raise SystemExit("public-key files must contain a plain OpenSSH public key")
    if index + 1 >= len(fields):
        raise SystemExit("public-key payload is missing")
    try:
        payload = base64.b64decode(fields[index + 1], validate=True)
    except (binascii.Error, ValueError):
        raise SystemExit("public-key payload is not valid base64") from None
    if len(payload) < 4:
        raise SystemExit("public-key payload is truncated")
    key_type_length = int.from_bytes(payload[:4], "big")
    encoded_key_type = payload[4:4 + key_type_length]
    if encoded_key_type.decode("ascii", errors="replace") != fields[index]:
        raise SystemExit("public-key type does not match its payload")
    normalized.append(line)

if not normalized:
    raise SystemExit("at least one supported public key is required")
if kind in {"text", "file"} and len(normalized) != 1:
    raise SystemExit("public-key input must contain exactly one key")
print("\n".join(normalized))
' "$source_kind" "$source_value"
}

prividium_host_operator_validate_source_file() {
  local source_file="$1"

  if [[ -L "$source_file" || ! -f "$source_file" || ! -r "$source_file" ]]; then
    prividium_fail "public-key source must be a readable regular file: ${source_file}"
  fi
}

prividium_host_operator_require_platform() {
  if [[ "$(id -u)" != "0" ]]; then
    prividium_fail "host operator creation must run as root"
  fi
  if [[ ! -r /etc/os-release ]] ||
    ! grep -Eq '^ID="?ubuntu"?$' /etc/os-release ||
    ! grep -Eq '^VERSION_ID="?24\.04"?$' /etc/os-release ||
    [[ "$(uname -m)" != "x86_64" ]]; then
    prividium_fail "host operator creation supports only Ubuntu 24.04 amd64"
  fi
}

prividium_host_operator_install_sudo() {
  if command -v sudo >/dev/null && command -v visudo >/dev/null; then
    return
  fi

  printf "Installing the sudo package required by the operator...\n"
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install --yes sudo
}

prividium_host_operator_create() {
  local apply_confirmed="false"
  local authorized_keys_tmp
  local confirmation
  local current_authorized_keys=/root/.ssh/authorized_keys
  local existing_authorized_keys
  local existing_sudoers
  local key_source_description=""
  local key_source_kind=""
  local key_source_value=""
  local normalized_keys
  local operator_group
  local operator_home
  local operator_shell
  local operator_user="prividium"
  local operator_user_created="false"
  local password_status
  local public_key=""
  local public_key_file=""
  local reuse_current_keys="false"
  local show_help="false"
  local sudoers_entry
  local sudoers_file
  local sudoers_tmp

  while (( $# )); do
    case "$1" in
      -h|--help)
        show_help="true"
        shift
        ;;
      --user)
        (( $# >= 2 )) || prividium_fail "--user requires a value"
        operator_user="$2"
        shift 2
        ;;
      --public-key)
        (( $# >= 2 )) || prividium_fail "--public-key requires a value"
        public_key="$2"
        shift 2
        ;;
      --public-key-file)
        (( $# >= 2 )) || prividium_fail "--public-key-file requires a value"
        public_key_file="$2"
        shift 2
        ;;
      --copy-current-authorized-keys)
        reuse_current_keys="true"
        shift
        ;;
      --yes)
        apply_confirmed="true"
        shift
        ;;
      -*)
        prividium_fail "unknown host operator create option: $1"
        ;;
      *)
        prividium_fail "unexpected host operator create argument: $1"
        ;;
    esac
  done

  if [[ "$show_help" == "true" ]]; then
    prividium_host_operator_usage
    return
  fi
  if ! prividium_host_operator_username_is_valid "$operator_user"; then
    prividium_fail "operator username is invalid or unsafe"
  fi

  local key_source_count=0
  [[ -n "$public_key" ]] && key_source_count=$((key_source_count + 1))
  [[ -n "$public_key_file" ]] && key_source_count=$((key_source_count + 1))
  [[ "$reuse_current_keys" == "true" ]] && key_source_count=$((key_source_count + 1))
  if (( key_source_count > 1 )); then
    prividium_fail "provide exactly one operator public-key source"
  fi

  prividium_require_commands \
    "host operator creation" \
    apt-get awk cat chmod chown getent grep id install mktemp mv passwd \
    python3 rm runuser uname useradd usermod
  prividium_host_operator_require_platform

  if [[ -n "$public_key" ]]; then
    key_source_kind="text"
    key_source_value="$public_key"
    key_source_description="explicit public key"
  elif [[ -n "$public_key_file" ]]; then
    prividium_host_operator_validate_source_file "$public_key_file"
    key_source_kind="file"
    key_source_value="$public_key_file"
    key_source_description="$public_key_file"
  elif [[ "$reuse_current_keys" == "true" ]]; then
    prividium_host_operator_validate_source_file "$current_authorized_keys"
    key_source_kind="authorized_keys"
    key_source_value="$current_authorized_keys"
    key_source_description="$current_authorized_keys"
  elif [[ -t 0 && "$apply_confirmed" != "true" ]]; then
    if [[ -f "$current_authorized_keys" && ! -L "$current_authorized_keys" ]]; then
      key_source_kind="authorized_keys"
      key_source_value="$current_authorized_keys"
      key_source_description="$current_authorized_keys"
    else
      read -r -p "Operator SSH public key: " public_key
      key_source_kind="text"
      key_source_value="$public_key"
      key_source_description="explicit public key"
    fi
  else
    prividium_fail \
      "non-interactive operator creation requires --public-key, --public-key-file, or --copy-current-authorized-keys"
  fi

  if [[ "$key_source_kind" != "text" ]]; then
    prividium_host_operator_validate_source_file "$key_source_value"
  fi
  if ! normalized_keys=$(prividium_host_operator_normalize_keys \
    "$key_source_kind" \
    "$key_source_value"); then
    prividium_fail "operator public-key source is invalid"
  fi

  printf "Prividium operator creation\n\n"
  printf "User:       %s\n" "$operator_user"
  printf "SSH keys:   %s\n" "$key_source_description"
  printf "Privileges: locked password; passwordless sudo\n"
  printf "Excluded:   sshd, root access, firewall, and Docker changes\n\n"

  if [[ "$apply_confirmed" != "true" ]]; then
    if [[ ! -t 0 ]]; then
      prividium_fail "non-interactive operator creation requires --yes"
    fi
    read -r -p "Type CREATE to create or verify this operator: " confirmation
    if [[ "$confirmation" != "CREATE" ]]; then
      printf "Operator creation cancelled; no host changes were made.\n"
      return
    fi
  fi

  prividium_host_operator_install_sudo
  prividium_require_commands "host operator creation" sudo visudo
  if ! getent group sudo >/dev/null; then
    prividium_fail "the Ubuntu sudo group is unavailable after package installation"
  fi

  if getent passwd "$operator_user" >/dev/null; then
    IFS=: read -r _ _ _ _ _ operator_home operator_shell < <(
      getent passwd "$operator_user"
    )
    if [[ "$operator_home" != "/home/${operator_user}" ||
          "$operator_shell" != "/bin/bash" ]]; then
      prividium_fail \
        "existing operator must use /home/${operator_user} and /bin/bash"
    fi
    if [[ "$(id -u "$operator_user")" == "0" ]]; then
      prividium_fail "existing operator must not have UID 0"
    fi
  else
    useradd --create-home --shell /bin/bash --user-group "$operator_user"
    operator_user_created="true"
    operator_home="/home/${operator_user}"
  fi

  if [[ -L "$operator_home" || ! -d "$operator_home" ]]; then
    prividium_fail "operator home must be a real directory: ${operator_home}"
  fi
  operator_group=$(id -gn "$operator_user")

  password_status=$(passwd --status "$operator_user" | awk '{print $2}')
  if [[ "$operator_user_created" == "true" && "$password_status" != "L" ]]; then
    passwd --lock "$operator_user" >/dev/null
  elif [[ "$operator_user_created" != "true" && "$password_status" != "L" ]]; then
    prividium_fail "existing operator must already have a locked password"
  fi
  if [[ " $(id -nG "$operator_user") " != *" sudo "* ]]; then
    usermod --append --groups sudo "$operator_user"
  fi

  if [[ -L "${operator_home}/.ssh" ]]; then
    prividium_fail "operator .ssh directory must not be a symbolic link"
  fi
  if [[ -e "${operator_home}/.ssh" && ! -d "${operator_home}/.ssh" ]]; then
    prividium_fail "operator .ssh path must be a directory"
  fi
  install -d \
    -m 0700 \
    -o "$operator_user" \
    -g "$operator_group" \
    "${operator_home}/.ssh"
  if [[ -L "${operator_home}/.ssh/authorized_keys" ]]; then
    prividium_fail "operator authorized_keys must not be a symbolic link"
  fi
  if [[ -e "${operator_home}/.ssh/authorized_keys" &&
        ! -f "${operator_home}/.ssh/authorized_keys" ]]; then
    prividium_fail "operator authorized_keys must be a regular file"
  fi
  existing_authorized_keys=""
  if [[ -f "${operator_home}/.ssh/authorized_keys" ]]; then
    existing_authorized_keys=$(cat "${operator_home}/.ssh/authorized_keys")
    if [[ "$existing_authorized_keys" != "$normalized_keys" ]]; then
      prividium_fail \
        "existing operator authorized_keys differs from the requested key source"
    fi
  fi
  authorized_keys_tmp=$(mktemp \
    "${operator_home}/.ssh/.authorized_keys.XXXXXX")
  printf '%s\n' "$normalized_keys" > "$authorized_keys_tmp"
  chown "$operator_user:$operator_group" "$authorized_keys_tmp"
  chmod 0600 "$authorized_keys_tmp"
  mv "$authorized_keys_tmp" "${operator_home}/.ssh/authorized_keys"

  sudoers_file="/etc/sudoers.d/90-prividium-${operator_user}"
  sudoers_entry="${operator_user} ALL=(ALL:ALL) NOPASSWD: ALL"
  if [[ -L "$sudoers_file" ]]; then
    prividium_fail "operator sudoers policy must not be a symbolic link"
  fi
  if [[ -e "$sudoers_file" && ! -f "$sudoers_file" ]]; then
    prividium_fail "operator sudoers policy must be a regular file"
  fi
  if [[ -f "$sudoers_file" ]]; then
    existing_sudoers=$(cat "$sudoers_file")
    if [[ "$existing_sudoers" != "$sudoers_entry" ]]; then
      prividium_fail "existing operator sudoers policy differs from the expected policy"
    fi
  fi
  sudoers_tmp=$(mktemp "/etc/sudoers.d/.90-prividium-${operator_user}.XXXXXX")
  printf '%s\n' "$sudoers_entry" > "$sudoers_tmp"
  chown root:root "$sudoers_tmp"
  chmod 0440 "$sudoers_tmp"
  if ! visudo -cf "$sudoers_tmp"; then
    rm -f -- "$sudoers_tmp"
    prividium_fail "generated operator sudoers policy did not validate"
  fi
  mv "$sudoers_tmp" "$sudoers_file"
  visudo -cf "$sudoers_file" >/dev/null

  if ! runuser --user "$operator_user" -- sudo -n true; then
    prividium_fail "operator passwordless sudo verification failed"
  fi

  printf "\nPrividium operator %s successfully.\n" \
    "$([[ "$operator_user_created" == "true" ]] && printf 'created' || printf 'verified')"
  printf "Keep this root session open. From a second terminal run:\n\n"
  printf "  ssh %s@<vps-address>\n" "$operator_user"
  printf "  sudo -n true\n\n"
  printf "After both succeed, clone the repository again under /home/%s.\n" \
    "$operator_user"
}

prividium_host_operator() {
  local subcommand="${1:-help}"

  shift || true
  case "$subcommand" in
    help|-h|--help)
      if (( $# )); then
        prividium_fail "unexpected host operator argument: $1"
      fi
      prividium_host_operator_usage
      ;;
    create)
      prividium_host_operator_create "$@"
      ;;
    *)
      prividium_fail "unknown host operator command: ${subcommand}"
      ;;
  esac
}
