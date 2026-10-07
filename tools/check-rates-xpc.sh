#!/bin/bash
# Signed fixture: runs the real rates helper from a built Volant.app inside a sandboxed client and
# fetches the live ECB feed, ExchangeRate-API rates and CoinGecko prices once each; crypto is keyless unless
# VOLANT_COINGECKO_KEY is set. No owner UI, data or settings are involved.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/core-module.sh
: "${VOLANT_RATES_APP:?Path to a built or exported Volant.app}"
identity="${VOLANT_SIGNING_IDENTITY:-Developer ID Application: Mystic Coders, LLC (REMBT6JY4N)}"
fixture=$(mktemp -d /tmp/volant-rates-xpc.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
bundle="$fixture/Rates Smoke.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/XPCServices"
ditto "$VOLANT_RATES_APP/Contents/XPCServices/VolantRatesHost.xpc" "$bundle/XPCServices/VolantRatesHost.xpc"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>RatesSmoke</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.ratessmoke</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc -target "$(uname -m)-apple-macosx15.0" "${VOLANT_CORE_FLAGS[@]}" tools/rates/xpc.swift -o "$bundle/MacOS/RatesSmoke"
cat > "$fixture/client.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
codesign --force --sign "$identity" --options runtime --timestamp=none --entitlements "$fixture/client.entitlements" "$fixture/Rates Smoke.app/Contents/MacOS/RatesSmoke"
codesign --force --sign "$identity" --options runtime --timestamp=none --entitlements "$fixture/client.entitlements" "$fixture/Rates Smoke.app"
codesign --verify --deep --strict "$fixture/Rates Smoke.app"
codesign -d --entitlements - --xml "$bundle/XPCServices/VolantRatesHost.xpc" 2>/dev/null | plutil -p - | grep -q "network.client"
"$bundle/MacOS/RatesSmoke"
