#!/bin/bash
# Archive, sign with the Developer ID, notarize, staple, and zip. Requires a notarytool keychain profile
# named "vey": xcrun notarytool store-credentials vey --apple-id <id> --team-id REMBT6JY4N
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
IDENTITY="Developer ID Application: Mystic Coders, LLC (REMBT6JY4N)"
VERSION="$(grep -m1 MARKETING_VERSION project.yml | sed 's/.*"\(.*\)"/\1/')"
OUT="$ROOT/dist"
rm -rf "$OUT" && mkdir -p "$OUT"

xcodegen generate --quiet
xcodebuild -project Volant.xcodeproj -scheme Volant -configuration Release \
  -archivePath "$OUT/Volant.xcarchive" archive \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM=REMBT6JY4N \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" | tail -2

APP="$OUT/Volant.xcarchive/Products/Applications/Volant.app"
codesign --verify --deep --strict --verbose=2 "$APP"
# The archive must carry exactly the intended entitlements and no debugger access.
ENT="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p -)"
echo "$ENT" | grep -q 'app-sandbox" => true' || { echo "missing sandbox entitlement"; exit 1; }
echo "$ENT" | grep -q 'get-task-allow' && { echo "get-task-allow present in release build"; exit 1; }
echo "$ENT" | grep -q 'network' && { echo "network entitlement present"; exit 1; }
codesign -dv "$APP" 2>&1 | grep -q 'Authority=Developer ID Application' || { echo "not signed with Developer ID"; exit 1; }
ZIP="$OUT/Volant-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile vey --wait
xcrun stapler staple "$APP"
rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=2 "$APP"
shasum -a 256 "$ZIP"
