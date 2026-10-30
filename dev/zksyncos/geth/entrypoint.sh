#!/bin/sh
# First boot seals a block per tx so the replay is quick, then restarts on 12 s blocks.
set -eu

DATA=/data
READY="$DATA/l1-ready"
REPLAY_DONE=/geth-config/replay-done

# gcmode=archive with the hash scheme keeps every historical state; the server's bisection reads old blocks.
set -- --dev --datadir "$DATA" --gcmode archive --state.scheme hash \
    --http --http.addr 0.0.0.0 --http.port 5010 --http.api eth,net,web3,debug,txpool \
    --http.vhosts '*' --http.corsdomain '*' --nodiscover --maxpeers 0

# An interrupted first boot leaves a half-replayed chain; start it over so no manual reset is needed.
if [ ! -f "$READY" ] && [ ! -f "$REPLAY_DONE" ]; then
    rm -rf "$DATA/geth"
fi

[ -d "$DATA/geth/chaindata" ] || geth init --datadir "$DATA" --state.scheme hash /geth-config/genesis.json

if [ ! -f "$READY" ]; then
    geth "$@" --dev.period 0 &
    pid=$!
    # sh is PID 1 here; without forwarding, a stop during first boot SIGKILLs geth mid-write.
    trap 'kill -INT "$pid"; wait "$pid"; exit 143' INT TERM
    while [ ! -f "$REPLAY_DONE" ]; do
        kill -0 "$pid"
        sleep 1
    done
    kill -INT "$pid"
    wait "$pid" || true
    trap - INT TERM
    touch "$READY"
fi

exec geth "$@" --dev.period 12
