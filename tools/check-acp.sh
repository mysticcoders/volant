#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/core-module.sh
acp_check_dir=$(mktemp -d /tmp/volant-acp-check.XXXXXX)
trap 'rm -rf "$acp_check_dir"' EXIT
cp tools/acp/check.swift "$acp_check_dir/main.swift"
swiftc "${VOLANT_CORE_FLAGS[@]}" VolantAgentHost/ACPConnection.swift "$acp_check_dir/main.swift" -o "$acp_check_dir/check"
"$acp_check_dir/check"
