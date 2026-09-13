#!/bin/bash
# Build Release, install to /Applications, register as a login item, and launch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project Volant.xcodeproj -scheme Volant -configuration Release -derivedDataPath build-release build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
SRC="$ROOT/build-release/Build/Products/Release/Volant.app"
DEST="/Applications/Volant.app"
pkill -x Vey 2>/dev/null || true
pkill -x Volant 2>/dev/null || true
sleep 0.5
rm -rf "$DEST"
ditto "$SRC" "$DEST"
open -a "$DEST" --args --register-login
echo "installed: $DEST"
