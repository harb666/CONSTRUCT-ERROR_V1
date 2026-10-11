#!/usr/bin/env bash
# Online co-op end to end: a host and a client game talking over ENet on
# this machine (tests/net_pair_test.gd). Usage: tests/run_net_pair.sh [godot]
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --fixed-fps 60 --path . -s tests/net_pair_test.gd -- --role=host > /tmp/net_host.log 2>&1 &
H=$!
sleep 2
"$GODOT" --headless --fixed-fps 60 --path . -s tests/net_pair_test.gd -- --role=client > /tmp/net_client.log 2>&1 &
C=$!
RH=0; wait $H || RH=$?
RC=0; wait $C || RC=$?
grep -h -E "^(PASS|FAIL)  |NET FAILURES" /tmp/net_host.log /tmp/net_client.log
grep -q "^NET FAILURES: 0$" /tmp/net_host.log && grep -q "^NET FAILURES: 0$" /tmp/net_client.log && [ $RH -eq 0 ] && [ $RC -eq 0 ]
