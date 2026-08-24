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

# Run on a private display where possible: the test is then hermetic, and it
# neither disturbs nor is disturbed by whatever is on screen.
#
# Two things about SDL here, both of which fail by exiting quietly rather than
# saying anything, which makes them tedious to diagnose:
#   - its own driver probing can pick something that does not work against
#     Xvfb, so SDL_VIDEODRIVER is pinned;
#   - it cannot authenticate against the cookie xvfb-run generates, so this
#     starts a plain Xvfb rather than using xvfb-run.
run() {
    if [ -n "${DISPLAY:-}" ]; then
        SDL_VIDEODRIVER=x11 ./SJ3 --physics-test < /dev/null 2>&1
        return
    fi

    command -v Xvfb >/dev/null || {
        echo "needs an X display, or Xvfb" >&2; exit 1; }

    local disp=99
    while [ -e "/tmp/.X${disp}-lock" ]; do disp=$((disp + 1)); done

    Xvfb ":$disp" -screen 0 1920x1080x24 >/dev/null 2>&1 &
    local xpid=$!
    trap 'kill '"$xpid"' 2>/dev/null' EXIT

    local i=0
    while [ $i -lt 50 ]; do
        DISPLAY=":$disp" xdpyinfo >/dev/null 2>&1 && break
        i=$((i + 1)); sleep 0.1
    done

    DISPLAY=":$disp" SDL_VIDEODRIVER=x11 ./SJ3 --physics-test < /dev/null 2>&1
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
