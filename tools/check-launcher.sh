#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
launcher_check_dir=$(mktemp -d /tmp/volant-launcher-check.XXXXXX)
trap 'rm -rf "$launcher_check_dir"' EXIT
cp tools/launcher/check.swift "$launcher_check_dir/main.swift"
launcher_sources=()
while IFS= read -r source; do launcher_sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*')
swiftc "${launcher_sources[@]}" "$launcher_check_dir/main.swift" -o "$launcher_check_dir/check"
"$launcher_check_dir/check" "$launcher_check_dir"
"$launcher_check_dir/check" "$launcher_check_dir" dark
