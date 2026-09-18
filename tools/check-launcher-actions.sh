#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture_dir=$(mktemp -d /tmp/volant-actions-check.XXXXXX)
trap 'rm -rf "$fixture_dir"' EXIT
bundle="$fixture_dir/Volant Actions Fixture.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
# Compile the production catalog with release asset optimization for branded native rendering.
xcrun actool Volant/Resources/Assets.xcassets --compile "$bundle/Resources" --platform macosx --minimum-deployment-target 15.0 --target-device mac --optimization space --output-partial-info-plist "$fixture_dir/assets.plist" >/dev/null
cp Volant/Resources/emoji.json "$bundle/Resources/"
ditto Volant/Resources/HelloWorld "$bundle/Resources/HelloWorld"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>VolantActionsFixture</string><key>CFBundleName</key><string>Volant Actions Fixture</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.actionsfixture</string><key>NSAccentColorName</key><string>AccentColor</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cp tools/launcher/actions.swift "$fixture_dir/main.swift"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*')
python3 tools/run-bounded-check.py 300 'Compile Actions fixture' swiftc -target "$(uname -m)-apple-macosx15.0" "${sources[@]}" "$fixture_dir/main.swift" -o "$bundle/MacOS/VolantActionsFixture"
python3 tools/run-bounded-check.py 120 'Light Actions fixture' "$bundle/MacOS/VolantActionsFixture" "$fixture_dir"
python3 tools/run-bounded-check.py 120 'Dark Actions fixture' "$bundle/MacOS/VolantActionsFixture" "$fixture_dir" dark
for scale in compact large; do
    python3 tools/run-bounded-check.py 120 "Light Actions $scale" "$bundle/MacOS/VolantActionsFixture" "$fixture_dir" "$scale"
    python3 tools/run-bounded-check.py 120 "Dark Actions $scale" "$bundle/MacOS/VolantActionsFixture" "$fixture_dir" dark "$scale"
done
