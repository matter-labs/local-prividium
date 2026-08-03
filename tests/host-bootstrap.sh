#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_SANDBOX=$(mktemp -d)
trap 'rm -rf "$TEST_SANDBOX"' EXIT

test_python="${PRIVIDIUM_TEST_PYTHON:-$(command -v python3)}"
test_ansible_inventory=$(command -v ansible-inventory)

mkdir -p \
  "${TEST_SANDBOX}/ansible/inventory/group_vars" \
  "${TEST_SANDBOX}/.ansible/tmp"
cp "${TEST_REPO_ROOT}/ansible/requirements.txt" "${TEST_SANDBOX}/ansible/"

export PRIVIDIUM_REPO_ROOT="$TEST_SANDBOX"
export ANSIBLE_HOME="${TEST_SANDBOX}/.ansible"
export ANSIBLE_LOCAL_TEMP="${TEST_SANDBOX}/.ansible/tmp"
source "${TEST_REPO_ROOT}/cli/commands/common.sh"
source "${TEST_REPO_ROOT}/cli/commands/host-bootstrap.sh"

prividium_host_bootstrap_requirements_satisfied \
  "$test_python" \
  "${TEST_REPO_ROOT}/ansible/requirements.txt"

# The pinned-package check above covers the real controller environment. The
# integration path below replaces only installation so the test remains
# network-free while exercising local inventory generation and idempotence.
prividium_host_bootstrap_install_controller() {
  :
}
prividium_host_bootstrap >/dev/null

"$test_python" -c '
from pathlib import Path
import json
import stat
import subprocess
import sys
import yaml

root = Path(sys.argv[1])
inventory = root / "ansible/inventory/hosts.ini"
variables = root / "ansible/inventory/group_vars/all.yml"
assert stat.S_IMODE(inventory.stat().st_mode) == 0o600
assert stat.S_IMODE(variables.stat().st_mode) == 0o600

intent = yaml.safe_load(variables.read_text())
assert intent == {
    "prividium_operator_user": sys.argv[2],
    "prividium_runtime_dir": "/etc/prividium/runtime",
}

document = json.loads(
    subprocess.check_output(
        [sys.argv[3], "--inventory", str(inventory), "--list"],
        text=True,
    )
)
hostvars = document["_meta"]["hostvars"]["sandbox-vps"]
assert hostvars["ansible_connection"] == "local"
assert hostvars["ansible_host"] == "127.0.0.1"
assert hostvars["ansible_user"] == sys.argv[2]
assert "ansible_port" not in hostvars
' \
  "$TEST_SANDBOX" \
  "$(id -un)" \
  "$test_ansible_inventory"

inventory_digest_before=$(
  "$test_python" -c \
    'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' \
    "${TEST_SANDBOX}/ansible/inventory/hosts.ini"
)
prividium_host_bootstrap >/dev/null
inventory_digest_after=$(
  "$test_python" -c \
    'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' \
    "${TEST_SANDBOX}/ansible/inventory/hosts.ini"
)
[[ "$inventory_digest_before" == "$inventory_digest_after" ]]

printf "Host bootstrap configuration validation passed\n"
