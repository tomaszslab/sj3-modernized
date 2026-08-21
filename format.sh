#!/usr/bin/env bash
# Reformat the Pascal sources in place with ptop, then clean up after it.
#
# ptop comes with Free Pascal, so no extra tooling is needed. It has three
# quirks this script works around:
#
#   - it emits a spurious blank line at the top of most files
#   - it leaves trailing whitespace on some lines
#   - it can drop the final newline
#
# ptop also cannot parse FPC's compound assignment operators (it turns "+="
# into "+ ="), so the sources deliberately avoid them; see SDLPort.TimerCallback.
#
# Verify with tools/verify-codegen.sh: formatting must not change the emitted
# assembly.
set -euo pipefail

cd "$(dirname "$0")"

command -v ptop >/dev/null || { echo "ptop not found (apt-get install fp-utils)"; exit 1; }

for f in *.PAS; do
    ptop -c ptop.cfg -i 2 "$f" "$f.fmt" >/dev/null

    # strip leading blank lines and trailing whitespace, collapse runs of blank
    # lines to at most two, and guarantee a final newline
    sed -i -e 's/[[:space:]]*$//' "$f.fmt"
    awk 'NR==1 && $0=="" {next} {print}' "$f.fmt" \
        | cat -s > "$f.tmp"
    mv "$f.tmp" "$f"
    rm -f "$f.fmt"
done

echo "Formatted $(ls -1 ./*.PAS | wc -l) files."
