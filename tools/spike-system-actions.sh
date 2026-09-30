#!/bin/bash
# Spike: how Volant could lock, sleep, start the screen saver and show restart or log-out
# dialogs. Builds one probe into two Developer ID signed bundles that differ only in App
# Sandbox, carrying the Apple Events entitlements production would need. Building never runs
# the probe: locking and sleeping belong in a Tart guest, not on the owner's desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
identity=${VOLANT_SIGN_IDENTITY:-'Developer ID Application: Mystic Coders, LLC (REMBT6JY4N)'}
out=${1:-$(mktemp -d /tmp/volant-system-actions.XXXXXX)}
mkdir -p "$out/build"
cp tools/systemactions/probe.swift "$out/build/main.swift"
swiftc -O -target "$(uname -m)-apple-macosx15.0" "$out/build/main.swift" -o "$out/build/probe"
for variant in Sandboxed Unsandboxed; do
    app="$out/$variant Probe.app/Contents"
    mkdir -p "$app/MacOS"
    cp "$out/build/probe" "$app/MacOS/SystemActionsProbe"
    cat > "$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SystemActionsProbe</string>
<key>CFBundleIdentifier</key><string>com.mysticcoders.volant.systemactions.$(echo $variant | tr A-Z a-z)</string>
<key>CFBundleName</key><string>$variant Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Spike: checks whether system actions need Automation consent.</string>
</dict></plist>
PLIST
done
cat > "$out/sandboxed.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.automation.apple-events</key><true/>
<key>com.apple.security.temporary-exception.apple-events</key>
<array><string>com.apple.loginwindow</string><string>com.apple.finder</string><string>com.apple.systemevents</string></array>
</dict></plist>
PLIST
cat > "$out/unsandboxed.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>com.apple.security.automation.apple-events</key><true/>
</dict></plist>
PLIST
codesign --force --sign "$identity" --options runtime --timestamp --entitlements "$out/sandboxed.entitlements" "$out/Sandboxed Probe.app"
codesign --force --sign "$identity" --options runtime --timestamp --entitlements "$out/unsandboxed.entitlements" "$out/Unsandboxed Probe.app"
codesign --verify --deep --strict "$out/Sandboxed Probe.app" "$out/Unsandboxed Probe.app"
echo "built: $out"
