#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/core-module.sh
fixture_dir=$(mktemp -d /tmp/volant-marketing.XXXXXX)
trap 'rm -rf "$fixture_dir"' EXIT
bundle="$fixture_dir/VolantPreview.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
cp dist/export/Volant.app/Contents/Resources/Assets.car "$bundle/Resources/"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>VolantPreview</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.preview</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*')
swiftc "${VOLANT_CORE_FLAGS[@]}" "${sources[@]}" tools/marketing/main.swift -o "$bundle/MacOS/VolantPreview"
"$bundle/MacOS/VolantPreview" "$PWD/website/public/images"
