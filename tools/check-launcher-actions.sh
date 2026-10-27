#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/app-module.sh
fixture_dir=$(mktemp -d /tmp/volant-actions-check.XXXXXX)
trap 'rm -rf "$fixture_dir"' EXIT
bundle="$fixture_dir/Volant Actions Fixture.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
# Compile the production catalog with release asset optimization for branded native rendering.
xcrun actool Volant/Resources/Assets.xcassets --compile "$bundle/Resources" --platform macosx --minimum-deployment-target 15.0 --target-device mac --optimization space --output-partial-info-plist "$fixture_dir/assets.plist" >/dev/null
cp Volant/Resources/emoji.json "$bundle/Resources/"
# Compile the String Catalogs so the Spanish pass below renders the shipped translation.
for catalog in Localizable Core; do
    xcrun xcstringstool compile "Volant/Resources/$catalog.xcstrings" --output-directory "$bundle/Resources" >/dev/null
done
ditto Volant/Resources/HelloWorld "$bundle/Resources/HelloWorld"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>VolantActionsFixture</string><key>CFBundleName</key><string>Volant Actions Fixture</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.actionsfixture</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.0.0</string></dict></plist>
PLIST
{ echo '@testable import VolantApp'; cat tools/launcher/actions.swift; } > "$fixture_dir/main.swift"
python3 tools/run-bounded-check.py 300 'Compile Actions fixture' swiftc "${VOLANT_APP_FLAGS[@]}" "$fixture_dir/main.swift" -o "$bundle/MacOS/VolantActionsFixture"
python3 tools/run-bounded-check.py 120 'Light Actions fixture' "$bundle/MacOS/VolantActionsFixture" "$fixture_dir"
python3 tools/run-bounded-check.py 120 'Dark Actions fixture' "$bundle/MacOS/VolantActionsFixture" "$fixture_dir" dark
python3 tools/run-bounded-check.py 120 'Light Spanish Actions fixture' "$bundle/MacOS/VolantActionsFixture" "$fixture_dir" spanish -AppleLanguages '(es)'
python3 tools/run-bounded-check.py 120 'Dark Spanish Actions fixture' "$bundle/MacOS/VolantActionsFixture" "$fixture_dir" dark spanish -AppleLanguages '(es)'
# Size changes layout and appearance changes color, independently, so each non-default size runs once,
# one in each appearance, instead of every size in both.
python3 tools/run-bounded-check.py 120 "Light Actions compact" "$bundle/MacOS/VolantActionsFixture" "$fixture_dir" compact
python3 tools/run-bounded-check.py 120 "Dark Actions large" "$bundle/MacOS/VolantActionsFixture" "$fixture_dir" dark large
