#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/volant-extension-check.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cp tools/extensions/check.swift "$fixture/main.swift"
swiftc Shared/ExtensionProtocol.swift VolantExtensionHost/ExtensionHost.swift "$fixture/main.swift" -o "$fixture/check"
"$fixture/check" "$PWD"
set +e
"$fixture/check" "$PWD" --spin
status=$?
set -e
[[ "$status" == 3 ]] || { echo "FAIL: runaway module exit was $status, expected watchdog exit 3"; exit 1; }
"$fixture/check" "$PWD"
echo 'PASS: watchdog terminates runaway WASM; fresh runtime succeeds afterward'
