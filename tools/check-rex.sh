#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/core-module.sh
rex_check_dir=$(mktemp -d /tmp/volant-rex-check.XXXXXX)
trap 'rm -rf "$rex_check_dir"' EXIT
cp tools/rex/watch-check.swift "$rex_check_dir/main.swift"
swiftc "${VOLANT_CORE_FLAGS[@]}" VolantAgentHost/RexHost.swift Shared/HerdrProcess.swift "$rex_check_dir/main.swift" -o "$rex_check_dir/check"
"$rex_check_dir/check" "$rex_check_dir"
