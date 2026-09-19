#!/bin/bash
# Signed, headless XPC delivery check. No app windows, hotkeys, clipboard monitoring or owner config.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f extensions/raycast-base64/encode.wasm ]] || bash tools/build-raycast-example.sh
: "${VOLANT_EXTENSION_APP:?Path to the exported, signed Volant.app}"
identity='Developer ID Application: Mystic Coders, LLC (REMBT6JY4N)'
fixture=$(mktemp -d /tmp/volant-extension-xpc.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
bundle="$fixture/Extension Smoke.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/XPCServices"
ditto "$VOLANT_EXTENSION_APP/Contents/XPCServices/VolantExtensionHost.xpc" "$bundle/XPCServices/VolantExtensionHost.xpc"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>ExtensionSmoke</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.extensionsmoke</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cp tools/extensions/xpc.swift "$fixture/main.swift"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*')
swiftc "${sources[@]}" "$fixture/main.swift" -o "$bundle/MacOS/ExtensionSmoke"
codesign --force --sign "$identity" --options runtime --timestamp "$fixture/Extension Smoke.app"
codesign --verify --deep --strict "$fixture/Extension Smoke.app"
ditto extensions/hello-rust "$fixture/hello"
ditto extensions/spin-rust "$fixture/spin"
ditto extensions/raycast-base64 "$fixture/base64"
"$bundle/MacOS/ExtensionSmoke" "$fixture"
