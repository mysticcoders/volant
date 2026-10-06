#!/bin/bash
# Builds VolantCore and sets VOLANT_CORE_FLAGS so the ad-hoc swiftc checks can import it
# instead of recompiling the core sources they used to list by path.
set -euo pipefail
if ! core_build_log=$(swift build --package-path Core 2>&1); then
    printf '%s\n' "$core_build_log" >&2
    exit 1
fi
volant_core_bin=$(swift build --package-path Core --show-bin-path)
# SwiftPM has placed the module beside the library and under Modules/ in different releases.
if [[ ! -e "$volant_core_bin/VolantCore.swiftmodule" && ! -e "$volant_core_bin/Modules/VolantCore.swiftmodule" ]]; then
    echo "VolantCore.swiftmodule not found in $volant_core_bin" >&2
    ls -la "$volant_core_bin" >&2
    exit 1
fi
if [[ ! -e "$volant_core_bin/libVolantCore.a" ]]; then
    echo "libVolantCore.a not found in $volant_core_bin; the package product must be static" >&2
    ls -la "$volant_core_bin" >&2
    exit 1
fi
VOLANT_CORE_FLAGS=(-I "$volant_core_bin" -I "$volant_core_bin/Modules" -L "$volant_core_bin" -lVolantCore)
