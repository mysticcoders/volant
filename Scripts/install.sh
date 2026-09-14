#!/bin/bash
# Build Release, install to /Applications, register as a login item, and launch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project Volant.xcodeproj -scheme Volant -configuration Release -derivedDataPath build-release build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
SRC="$ROOT/build-release/Build/Products/Release/Volant.app"
DEST="/Applications/Volant.app"
osascript -e 'if application id "com.mysticcoders.vey" is running then tell application id "com.mysticcoders.vey" to quit'
osascript -e 'if application id "com.mysticcoders.volant" is running then tell application id "com.mysticcoders.volant" to quit'
python3 "$ROOT/tools/migrate-bundle-data.py"
# Stage a fresh bundle: overwriting the existing directory can retain the old
# bundle identity in macOS privacy services after the Vey → Volant migration.
STAGING="$(mktemp -d /Applications/.volant-install.XXXXXX)"
cleanup() {
  if [[ ! -e "$DEST" && -d "$STAGING/Previous.app" ]]; then
    mv "$STAGING/Previous.app" "$DEST"
  fi
  rm -rf "$STAGING"
}
trap cleanup EXIT
ditto "$SRC" "$STAGING/Volant.app"
codesign --verify --deep --strict "$STAGING/Volant.app"
if [[ -e "$DEST" ]]; then mv "$DEST" "$STAGING/Previous.app"; fi
mv "$STAGING/Volant.app" "$DEST"
# Refresh the installed identity after a bundle-ID migration; never reset the user's global registry.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
open -a "$DEST" --args --register-login
echo "installed: $DEST"
