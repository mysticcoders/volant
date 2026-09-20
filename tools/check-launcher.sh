#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/core-module.sh
launcher_check_dir=$(mktemp -d /tmp/volant-launcher-check.XXXXXX)
trap 'rm -rf "$launcher_check_dir"' EXIT
cp tools/launcher/check.swift "$launcher_check_dir/main.swift"
launcher_sources=()
while IFS= read -r source; do launcher_sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*')
python3 tools/run-bounded-check.py 300 "Compile launcher fixtures" swiftc "${VOLANT_CORE_FLAGS[@]}" "${launcher_sources[@]}" "$launcher_check_dir/main.swift" -o "$launcher_check_dir/check"
python3 tools/run-bounded-check.py 120 "Light launcher interactions" "$launcher_check_dir/check" "$launcher_check_dir"
python3 tools/run-bounded-check.py 120 "Dark launcher interactions" "$launcher_check_dir/check" "$launcher_check_dir" dark
