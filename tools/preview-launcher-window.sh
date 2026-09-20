#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/core-module.sh
fixture_dir=$(mktemp -d /tmp/volant-window.XXXXXX)
trap 'rm -rf "$fixture_dir"' EXIT
bundle="$fixture_dir/Volant Window Preview.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
cp dist/export/Volant.app/Contents/Resources/Assets.car "$bundle/Resources/"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>VolantWindowPreview</string><key>CFBundleName</key><string>Volant Window Preview</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.windowpreview</string><key>NSAccentColorName</key><string>AccentColor</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*')
swiftc "${VOLANT_CORE_FLAGS[@]}" "${sources[@]}" tools/window/main.swift -o "$bundle/MacOS/VolantWindowPreview"
echo "Preview app: ${bundle%/Contents}"
"$bundle/MacOS/VolantWindowPreview" "${1:-light}"
