#!/usr/bin/env bash
# Starts the local L1 from the zksync-os fixture inside the foundry image.
# Usage: start-anvil.sh <port> [anvil flags...] | start-anvil.sh healthcheck <port>
set -o errexit
set -o nounset
set -o pipefail

readonly FIXTURE_GZ=/l1-state.json.gz
readonly STATE_FILE=/home/foundry/l1state/state.json
# The l1 healthcheck gates on this, so zksync-os-server never commits against a stale L1 clock.
readonly CLOCK_SYNCED_MARKER=/tmp/l1-clock-synced

main() {
    if [[ $1 == healthcheck ]]; then
        healthcheck "$2"
        return
    fi
    local -r port=$1
    shift

    rm -f "${CLOCK_SYNCED_MARKER}"
    if [[ ! -f ${STATE_FILE} ]]; then
        gzip -dc "${FIXTURE_GZ}" > "${STATE_FILE}"
    fi

    # Anvil >= 1.7 resumes its clock from the loaded head block. Batches carry wall-clock
    # timestamps, so once the head is over 1h old every commit reverts with L2TimestampTooBig.
    sync_clock "http://127.0.0.1:${port}" "$$" &

    exec anvil --port "${port}" --host 0.0.0.0 "$@"
}

healthcheck() {
    local -r port=$1

    [[ -f ${CLOCK_SYNCED_MARKER} ]] && cast chain-id --rpc-url "http://localhost:${port}" > /dev/null
}

sync_clock() {
    local -r rpc_url=$1
    local -r anvil_pid=$2

    until cast block-number --rpc-url "${rpc_url}" > /dev/null 2>&1; do
        kill -0 "${anvil_pid}" 2> /dev/null || return 0
        sleep 0.2
    done
    cast rpc --rpc-url "${rpc_url}" evm_setTime "$(date +%s)" > /dev/null
    touch "${CLOCK_SYNCED_MARKER}"
}

main "$@"
