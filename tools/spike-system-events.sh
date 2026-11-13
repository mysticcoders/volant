#!/bin/bash
# Builds tools/systemevents/probe.swift with the shipped Volant/SystemControl/SystemEvents.swift into
# a Developer ID signed, sandboxed bundle carrying exactly Volant's Apple Events entitlements. Building
# never runs it: changing the appearance or menu bar belongs in a Tart guest, not the owner's desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/core-module.sh
identity=${VOLANT_SIGN_IDENTITY:-'Developer ID Application: Mystic Coders, LLC (REMBT6JY4N)'}
out=${1:-$(mktemp -d /tmp/volant-system-events.XXXXXX)}
app="$out/System Events Probe.app"
mkdir -p "$app/Contents/MacOS"
cp tools/systemevents/probe.swift "$out/main.swift"
swiftc -O -target "$(uname -m)-apple-macosx15.0" "${VOLANT_CORE_FLAGS[@]}" -module-name Probe \
    "$out/main.swift" Volant/SystemControl/SystemEvents.swift -o "$app/Contents/MacOS/SystemEventsProbe"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SystemEventsProbe</string>
<key>CFBundleIdentifier</key><string>com.mysticcoders.volant.sysevents.probe</string>
<key>CFBundleName</key><string>System Events Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Probe: switches the appearance and menu bar through System Events.</string>
</dict></plist>
PLIST
python3 - "$out/probe.entitlements" <<'PY'
import plistlib, sys
release = plistlib.loads(open("Volant/Volant.entitlements", "rb").read())
keys = ["com.apple.security.app-sandbox", "com.apple.security.automation.apple-events", "com.apple.security.temporary-exception.apple-events"]
plistlib.dump({key: release[key] for key in keys}, open(sys.argv[1], "wb"))
PY
codesign --force --sign "$identity" --options runtime --timestamp --entitlements "$out/probe.entitlements" "$app"
codesign --verify --deep --strict "$app"
echo "built: $app"
