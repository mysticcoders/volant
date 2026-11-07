#!/bin/bash
# Tries dropping each listed keep-list entry on its own and reports whether the trimmed module
# still gives answers identical to the full one (parity.mjs). Used to shrink icu-keep.txt.
# Usage: tools/try-wasm/keep-prune.sh <full.wasm> <entry> [entry ...]
set -uo pipefail
cd "$(dirname "$0")"
FULL="$1"; shift
for entry in "$@"; do
  rg -v -x -F -- "$entry" icu-keep.txt > out/icu/keep-prune.txt
  node icu-data.mjs trim "$FULL" out/icu/keep-prune.txt out/icu/prune.wasm > /dev/null
  if node parity.mjs "$FULL" out/icu/prune.wasm parity-queries.txt > /dev/null 2>&1; then
    echo "removable: $entry"
  else
    echo "needed:    $entry"
  fi
done
