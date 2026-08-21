#!/usr/bin/env bash
# Build SJ3 and make sure the working directory is runnable.
#
#   ./build.sh          build
#   ./build.sh clean    remove build output first, then build
set -euo pipefail

cd "$(dirname "$0")"

HEADERS=Pascal-SDL-2-Headers
HEADERS_URL=https://github.com/ev1313/Pascal-SDL-2-Headers

if [ "${1:-}" = "clean" ]; then
    rm -f ./*.o ./*.ppu ./SJ3
fi

# The SDL2 Pascal headers are not vendored; fetch them on first build.
if [ ! -d "$HEADERS" ]; then
    echo "Cloning SDL2 Pascal headers..."
    git clone --depth 1 "$HEADERS_URL" "$HEADERS"
fi

# The game halts at startup if any of these is missing, and it rewrites them on
# exit, so they are gitignored and seeded from defaults/ instead.
for f in defaults/*; do
    name=$(basename "$f")
    if [ ! -e "$name" ]; then
        echo "Installing default $name"
        cp "$f" "$name"
    fi
done

fpc -Mtp -Fu"./$HEADERS/" SJ3.PAS

echo
echo "Built ./SJ3 - run it from this directory."
