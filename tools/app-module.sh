#!/bin/bash
# Builds the app's sources (Volant/ and Shared/, without Volant/App/) once as a static VolantApp
# module with testing enabled, and sets VOLANT_APP_FLAGS so a native fixture can compile only its own
# main.swift with `@testable import VolantApp`. The launcher and Actions fixtures used to compile all
# of these sources separately. The build is cached under build/fixture-app, keyed by the sources,
# the VolantCore library and the compiler, so the second fixture reuses the first one's module.
set -euo pipefail
source tools/core-module.sh
volant_app_sources=()
while IFS= read -r source; do volant_app_sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*' | sort)
volant_app_target="$(uname -m)-apple-macosx15.0"
volant_app_dir="build/fixture-app"
volant_app_key=$( { swiftc --version 2>&1; echo "$volant_app_target"; shasum -a 256 "$volant_core_bin/libVolantCore.a"; shasum -a 256 "${volant_app_sources[@]}"; } | shasum -a 256 | cut -d' ' -f1)
if [[ "$(cat "$volant_app_dir/key" 2>/dev/null)" != "$volant_app_key" ]]; then
    rm -rf "$volant_app_dir"
    mkdir -p "$volant_app_dir"
    python3 tools/run-bounded-check.py 300 "Compile VolantApp module for fixtures" swiftc -target "$volant_app_target" "${VOLANT_CORE_FLAGS[@]}" \
        -parse-as-library -enable-testing -module-name VolantApp -emit-module -emit-module-path "$volant_app_dir/VolantApp.swiftmodule" \
        -emit-library -static -o "$volant_app_dir/libVolantApp.a" "${volant_app_sources[@]}"
    printf '%s' "$volant_app_key" > "$volant_app_dir/key"
else
    echo "Reusing the VolantApp module in $volant_app_dir"
fi
VOLANT_APP_FLAGS=(-target "$volant_app_target" -I "$volant_app_dir" -L "$volant_app_dir" -lVolantApp "${VOLANT_CORE_FLAGS[@]}")
