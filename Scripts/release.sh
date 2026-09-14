#!/bin/bash
# Build an exported Developer ID app, notarized DMG, and signed Sparkle appcast.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
IDENTITY="${VOLANT_SIGNING_IDENTITY:-Developer ID Application: Mystic Coders, LLC (REMBT6JY4N)}"
PROFILE="${VOLANT_NOTARY_PROFILE:-volant}"
if [[ -n "${VOLANT_NOTARY_KEY:-}" ]]; then
  : "${VOLANT_NOTARY_KEY_ID:?Set the App Store Connect key ID}"
  : "${VOLANT_NOTARY_ISSUER:?Set the App Store Connect issuer ID}"
  NOTARY_ARGS=(--key "$VOLANT_NOTARY_KEY" --key-id "$VOLANT_NOTARY_KEY_ID" --issuer "$VOLANT_NOTARY_ISSUER")
else
  NOTARY_ARGS=(--keychain-profile "$PROFILE")
fi
# Fail before building if Apple credentials are unavailable.
xcrun notarytool history "${NOTARY_ARGS[@]}" --output-format json > /dev/null
FEED="${VOLANT_UPDATE_FEED_URL:-https://usevolant.com/updates/appcast.xml}"
VOLANT_UPDATE_PUBLIC_KEY="${VOLANT_UPDATE_PUBLIC_KEY:-iygB/kS8RY5Jh1g/IkvPRHy47iXRWqFR71jJCz9oTgY=}"
export VOLANT_UPDATE_PUBLIC_KEY
python3 - <<'PY'
import base64, os
assert len(base64.b64decode(os.environ['VOLANT_UPDATE_PUBLIC_KEY'], validate=True)) == 32, 'Invalid Sparkle public key'
PY
[[ "$FEED" == https://* ]] || { echo 'Update feed must use HTTPS'; exit 1; }
VERSION="$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)"
OUT="$(mktemp -d "$ROOT/dist-release.XXXXXX")"
echo "Release output: $OUT"
xcodegen generate --quiet
xcodebuild -project Volant.xcodeproj -scheme Volant -configuration Release \
  -derivedDataPath "$ROOT/build" -archivePath "$OUT/Volant.xcarchive" archive \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM=REMBT6JY4N \
  VOLANT_UPDATE_PUBLIC_KEY="$VOLANT_UPDATE_PUBLIC_KEY" VOLANT_UPDATE_FEED_URL="$FEED" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" > "$OUT/archive.log" 2>&1
# Export re-signs Sparkle's nested tools and XPC services, not just the framework.
xcodebuild -exportArchive -archivePath "$OUT/Volant.xcarchive" \
  -exportPath "$OUT/export" -exportOptionsPlist Scripts/ExportOptions.plist > "$OUT/export.log" 2>&1
APP="$OUT/export/Volant.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - --xml "$APP" > "$OUT/entitlements.plist" 2>/dev/null
python3 - "$OUT/entitlements.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: ent = plistlib.load(f)
assert ent.get('com.apple.security.app-sandbox') is True
assert not ent.get('com.apple.security.get-task-allow')
assert not ent.get('com.apple.security.network.client')
assert not ent.get('com.apple.security.network.server')
PY
codesign -dvvv "$APP" 2> "$OUT/signature.txt"
grep -q 'Authority=Developer ID Application' "$OUT/signature.txt"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" "${NOTARY_ARGS[@]}" --wait --timeout 30m
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
mkdir "$OUT/dmg" "$OUT/updates"
ditto "$APP" "$OUT/dmg/Volant.app"
ln -s /Applications "$OUT/dmg/Applications"
DMG="$OUT/updates/Volant-$VERSION.dmg"
hdiutil create -volname Volant -srcfolder "$OUT/dmg" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait --timeout 30m
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
SPARKLE_BIN="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_appcast" --account volant --download-url-prefix "${FEED%/*}/" "$OUT/updates"
"$SPARKLE_BIN/sign_update" --account volant "$OUT/updates/appcast.xml"
"$SPARKLE_BIN/sign_update" --account volant --verify "$OUT/updates/appcast.xml"
(cd "$OUT/updates" && shasum -a 256 "Volant-$VERSION.dmg") > "$OUT/updates/SHA256SUMS"
echo "Validated release assets: $OUT/updates (not published)"
