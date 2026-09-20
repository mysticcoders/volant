#!/bin/bash
# Spike: can an unsandboxed XPC service embedded in a sandboxed app terminate another process?
# Builds a sandboxed fixture app with an embedded unsandboxed helper, both Developer ID signed,
# and leaves the bundle in place for a runner to exercise. Building signs but never runs it:
# quitting a real application belongs in the guest, not on the owner's desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
identity=${VOLANT_SIGN_IDENTITY:-'Developer ID Application: Mystic Coders, LLC (REMBT6JY4N)'}
out=${1:-$(mktemp -d /tmp/volant-privaccess.XXXXXX)}
mkdir -p "$out"

app="$out/PrivAccess Spike.app/Contents"
service="$app/XPCServices/VolantPrivAccessHost.xpc/Contents"
mkdir -p "$app/MacOS" "$service/MacOS"

cat > "$service/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>VolantPrivAccessHost</string>
<key>CFBundleIdentifier</key><string>com.mysticcoders.volant.privaccess</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>VolantPrivAccessHost</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>XPCService</key><dict><key>ServiceType</key><string>Application</string></dict>
</dict></plist>
PLIST

cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>PrivAccessSpike</string>
<key>CFBundleIdentifier</key><string>com.mysticcoders.volant.privaccessspike</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>PrivAccess Spike</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST

# Top-level code must live in main.swift when more than one file is compiled together.
mkdir -p "$out/build/host" "$out/build/client"
cp tools/privaccess/host.swift "$out/build/host/main.swift"
cp tools/privaccess/client.swift "$out/build/client/main.swift"
# Match Volant's deployment target. Without it the host compiler links Swift runtime
# libraries that do not exist on the macOS 15 baseline, and the service dies on launch.
target="$(uname -m)-apple-macosx15.0"
swiftc -O -target "$target" tools/privaccess/protocol.swift "$out/build/host/main.swift" -o "$service/MacOS/VolantPrivAccessHost"
swiftc -O -target "$target" tools/privaccess/protocol.swift "$out/build/client/main.swift" -o "$app/MacOS/PrivAccessSpike"

# The helper carries no entitlements, which is how VolantAgentHost ships: an XPC service
# without the app-sandbox key runs outside the sandbox. An earlier attempt set the key to
# false instead; that was changed at the same time as two other things while chasing a launch
# failure whose actual cause was the deployment target, so it was never shown to be harmful.
# Matching the shipping helper is the reason to prefer this form.
cat > "$out/helper.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>
PLIST
# The client carries Volant's own sandbox entitlement so the comparison is honest.
cat > "$out/client.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
</dict></plist>
PLIST

codesign --force --sign "$identity" --options runtime --timestamp \
    --entitlements "$out/helper.entitlements" "$app/XPCServices/VolantPrivAccessHost.xpc"
codesign --force --sign "$identity" --options runtime --timestamp \
    --entitlements "$out/client.entitlements" "$out/PrivAccess Spike.app"
codesign --verify --deep --strict "$out/PrivAccess Spike.app"

# The attack the code-signing requirement exists to stop: a repackaged app that embeds the
# genuine, validly signed helper but whose own binary is not signed by this team. Only the
# outer bundle is re-signed, so the helper keeps its Developer ID signature.
ditto "$out/PrivAccess Spike.app" "$out/Intruder.app"
codesign --force --sign - --entitlements "$out/client.entitlements" "$out/Intruder.app"

echo "built and signed: $out/PrivAccess Spike.app"
echo "built intruder:   $out/Intruder.app (ad-hoc outer signature, genuine helper)"
echo "helper entitlements:"
codesign -d --entitlements - "$app/XPCServices/VolantPrivAccessHost.xpc" 2>/dev/null | tail -5
echo "client entitlements:"
codesign -d --entitlements - "$out/PrivAccess Spike.app" 2>/dev/null | tail -5
