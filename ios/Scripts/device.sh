#!/bin/bash
# Build Volant for iPhone with the development profiles and install it on a device:
#   Scripts/device.sh <device-udid>
# Profile names default to the team's development profiles; override with VOLANT_APP_PROFILE,
# VOLANT_WIDGETS_PROFILE and VOLANT_SHARE_PROFILE.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:?usage: Scripts/device.sh <device-udid>  (xcrun devicectl list devices)}"
LOG="build/device.log"
mkdir -p build
xcodegen generate --quiet
if ! xcodebuild -project VolantMobile.xcodeproj -scheme VolantMobile -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build/device \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" \
    VOLANT_APP_PROFILE="${VOLANT_APP_PROFILE:-Volant mobile development profile}" \
    VOLANT_WIDGETS_PROFILE="${VOLANT_WIDGETS_PROFILE:-Volant mobile widget development profile}" \
    VOLANT_SHARE_PROFILE="${VOLANT_SHARE_PROFILE:-Volant mobile share development profile}" \
    build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u
  echo "Build failed; full log in ios/$LOG" >&2
  exit 1
fi
APP="build/device/Build/Products/Debug-iphoneos/Volant.app"
for attempt in 1 2 3; do
  if xcrun devicectl device install app --device "$DEVICE" "$APP" > /dev/null; then
    xcrun devicectl device process launch --device "$DEVICE" com.mysticcoders.volant.mobile > /dev/null
    echo "Installed and launched on $DEVICE"
    exit 0
  fi
  echo "Install attempt $attempt failed; retrying" >&2
  sleep 10
done
exit 1
