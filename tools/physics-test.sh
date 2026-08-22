#!/usr/bin/env bash
# Check that the simulation still does exactly what it did.
#
# Runs a fixed set of jumps with a fixed seed and folds every simulated frame
# into one number, then compares it with tools/physics-hash.expected.
#
# This exists because tools/verify-codegen.sh cannot help here. That proves a
# mechanical change did not alter the program, but says nothing once a commit
# legitimately changes the emitted code - and that is exactly when one wants
# the physics to be held still. Stored replays cannot stand in either: they
# hold position deltas and sprite indices, so playing one back never re-runs
# the simulation.
#
#   tools/physics-test.sh            compare against the expected hash
#   tools/physics-test.sh --accept   record the current hash as expected
#
# Accept only when the physics was meant to change, and say why in the commit.
set -euo pipefail

cd "$(dirname "$0")/.."
EXPECTED_FILE=tools/physics-hash.expected

[ -x ./SJ3 ] || { echo "build first: ./build.sh"; exit 1; }

run() {
    if [ -n "${DISPLAY:-}" ]; then
        ./SJ3 --physics-test < /dev/null 2>&1
    elif command -v xvfb-run >/dev/null; then
        xvfb-run -a ./SJ3 --physics-test < /dev/null 2>&1
    else
        echo "needs an X display, or xvfb-run" >&2; exit 1
    fi
}

hash=$(run | grep -ao 'physics hash: [0-9]*' | awk '{print $3}')
[ -n "$hash" ] || { echo "the test did not report a hash"; exit 1; }

if [ "${1:-}" = "--accept" ]; then
    echo "$hash" > "$EXPECTED_FILE"
    echo "recorded $hash as expected"
    exit 0
fi

[ -f "$EXPECTED_FILE" ] || {
    echo "no $EXPECTED_FILE - run with --accept to record one"; exit 1; }

expected=$(cat "$EXPECTED_FILE")
if [ "$hash" = "$expected" ]; then
    echo "physics unchanged ($hash)"
else
    echo "PHYSICS CHANGED"
    echo "  expected $expected"
    echo "  got      $hash"
    exit 1
fi
