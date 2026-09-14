#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture_dir=$(mktemp -d /tmp/volant-settings.XXXXXX)
trap 'rm -rf "$fixture_dir"' EXIT
bundle="$fixture_dir/Volant Settings Preview.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
cp dist/export/Volant.app/Contents/Resources/Assets.car "$bundle/Resources/"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>VolantSettingsPreview</string><key>CFBundleName</key><string>Volant Settings Preview</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.settingspreview</string><key>NSAccentColorName</key><string>AccentColor</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*')
swiftc -target "$(uname -m)-apple-macosx15.0" "${sources[@]}" tools/settings/main.swift -o "$bundle/MacOS/VolantSettingsPreview"
echo "Preview app: ${bundle%/Contents}"
"$bundle/MacOS/VolantSettingsPreview" "${1:-light}"
