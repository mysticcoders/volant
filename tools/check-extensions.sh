#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/core-module.sh
[[ -f extensions/raycast-base64/encode.wasm ]] || bash tools/build-raycast-example.sh
fixture=$(mktemp -d /tmp/volant-extension-check.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cp tools/extensions/check.swift "$fixture/main.swift"
swiftc "${VOLANT_CORE_FLAGS[@]}" VolantExtensionHost/ExtensionHost.swift VolantExtensionHost/WASICommand.swift Shared/ExtensionSVGRasterizer.swift Shared/ExtensionImageDecoding.swift "$fixture/main.swift" -o "$fixture/check"
# Match the helper's JIT authorization; macOS 15 cannot interpret WASM SIMD.
cat > "$fixture/jit.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>com.apple.security.cs.allow-jit</key><true/></dict></plist>
PLIST
codesign --force --sign - --options runtime --entitlements "$fixture/jit.plist" "$fixture/check"
"$fixture/check" "$PWD"
set +e
"$fixture/check" "$PWD" --spin
status=$?
set -e
[[ "$status" == 3 ]] || { echo "FAIL: runaway module exit was $status, expected watchdog exit 3"; exit 1; }
set +e
"$fixture/check" "$PWD" --command-spin
status=$?
set -e
[[ "$status" == 3 ]] || { echo "FAIL: runaway command exit was $status, expected watchdog exit 3"; exit 1; }
set +e
"$fixture/check" "$PWD" --svg-spin
status=$?
set -e
if [[ "$status" == 4 ]]; then
    echo 'SKIP: no SVG renderer on this macOS, so the SVG watchdog was not exercised'
else
    [[ "$status" == 3 ]] || { echo "FAIL: slow SVG render exit was $status, expected watchdog exit 3"; exit 1; }
fi
"$fixture/check" "$PWD"
echo 'PASS: watchdog terminates runaway WASM and slow SVG renders; fresh runtime succeeds afterward'
