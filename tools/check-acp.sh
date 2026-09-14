#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
acp_check_dir=$(mktemp -d /tmp/volant-acp-check.XXXXXX)
trap 'rm -rf "$acp_check_dir"' EXIT
cp tools/acp/check.swift "$acp_check_dir/main.swift"
swiftc Shared/ACPTypes.swift VolantAgentHost/ACPConnection.swift "$acp_check_dir/main.swift" -o "$acp_check_dir/check"
"$acp_check_dir/check"
