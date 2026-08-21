#!/usr/bin/env bash
# Print a hash of the assembly the compiler emits for the whole program.
#
# Mechanical changes - reformatting, removing commented-out code, renaming a
# local - must leave this hash untouched. If it moves, the change altered the
# program.
set -euo pipefail

cd "$(dirname "$0")/.."
SRC=$(pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

cp ./*.PAS "$W"/
cp -r Pascal-SDL-2-Headers "$W"/ 2>/dev/null || {
    echo "Pascal-SDL-2-Headers missing - run ./build.sh first"; exit 1; }

cd "$W"
if ! fpc -Mtp -a -Fu./Pascal-SDL-2-Headers/ SJ3.PAS > build.log 2>&1; then
    echo "BUILD FAILED"
    grep -aiE "Error|Fatal" build.log | head -5
    exit 1
fi

cat ./*.s | sha256sum | cut -d' ' -f1
