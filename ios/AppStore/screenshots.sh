#!/bin/bash
# Capture Volant for iPhone's App Store screenshots in the simulator from the fictional fixtures
# in fixtures/, then frame them with headlines at the store sizes:
#   ios/AppStore/screenshots.sh [iphone|ipad|all]
# Output: ios/build/appstore/<device>/NN-name.png (framed) and raw/ (unframed captures).
set -euo pipefail
cd "$(dirname "$0")/.."
WHICH="${1:-all}"
OUT="build/appstore"
APP="build/sim/Build/Products/Debug-iphonesimulator/Volant.app"
BUNDLE="com.mysticcoders.volant.mobile"
NOTES="$(mktemp -d)/Notes"
SETTINGS="$PWD/AppStore/fixtures/mac-settings.json"

xcodegen generate --quiet
xcodebuild -project VolantMobile.xcodeproj -scheme VolantMobile -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/sim CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build > build/appstore-build.log 2>&1 \
  || { grep "error:" build/appstore-build.log | sort -u; exit 1; }
swiftc -O -o build/frame AppStore/frame.swift

# Copies the fixture notes and dates them relative to now, newest first, since git keeps no dates.
mkdir -p "$NOTES"
cp AppStore/fixtures/notes/*.md "$NOTES/"
hours=(0.2 2 23 49 74 121 214 359)
i=0
for note in $(ls "$NOTES" | sort -r); do
  touch -t "$(date -v-"$(printf '%.0f' "$(echo "${hours[$i]} * 60" | bc)")"M +%Y%m%d%H%M)" "$NOTES/$note"
  i=$((i + 1))
done

# Each shot: name | headline | subline | launch arguments.
SHOTS=(
  "01-home|Your toolkit, one tap away|Notes, snippets, quicklinks and a calculator|"
  "02-notes|Plain Markdown notes|Synced with Volant on your Mac through iCloud|-fixtureTab notes"
  "03-note|Write in Markdown, read it beautifully|Checklists, code blocks and quotes|-fixtureNote 2026-11-12-a1f3c0de.md -notes.preview YES"
  "04-search|One search for everything|Notes, snippets, links and answers as you type|-fixtureTab search -fixtureQuery map"
  "05-snippets|Your snippets, everywhere|Copy with dates and placeholders filled in|-fixtureTool snippets"
  "06-calculator|Units, time zones and dates|The same calculator as Volant on the Mac|-fixtureTool calculator -fixtureQuery 3pm Tokyo in London"
  "07-privacy|Private by design|Your notes stay in your own iCloud|-onboardingComplete NO -fixtureOnboardingPage 2"
)

# capture <device> <udid> <width> <height> [display] [rotate]: display picks one of a multi-screen
# device's screens (simctl's --display), and rotate turns the raw framebuffer upright (degrees).
capture() {
  local device="$1" udid="$2" width="$3" height="$4" display="${5:-}" rotate="${6:-0}"
  mkdir -p "$OUT/$device/raw"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b > /dev/null
  xcrun simctl ui "$udid" appearance dark
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName "" 2>/dev/null || true
  xcrun simctl install "$udid" "$APP"
  for shot in "${SHOTS[@]}"; do
    IFS='|' read -r name headline subline args <<< "$shot"
    local extra=(-onboardingComplete YES)
    [[ "$args" == *onboardingComplete* ]] && extra=()
    local query=()
    if [[ "$args" == *-fixtureQuery* ]]; then
      query=(-fixtureQuery "${args#*-fixtureQuery }")
      args="${args%%-fixtureQuery*}"
    fi
    xcrun simctl terminate "$udid" "$BUNDLE" 2>/dev/null || true
    # shellcheck disable=SC2086
    xcrun simctl launch "$udid" "$BUNDLE" -notesDirectory "$NOTES" -fixtureMacSettings "$SETTINGS" \
      ${extra[@]+"${extra[@]}"} $args ${query[@]+"${query[@]}"} > /dev/null
    sleep 4
    xcrun simctl io "$udid" screenshot ${display:+--display="$display"} "$OUT/$device/raw/$name.png" > /dev/null 2>&1
    [[ "$rotate" != 0 ]] && magick "$OUT/$device/raw/$name.png" -rotate "$rotate" "$OUT/$device/raw/$name.png"
    ./build/frame "$OUT/$device/raw/$name.png" "$OUT/$device/$name.png" "$width" "$height" "$headline" "$subline"
    echo "$device $name"
  done
  xcrun simctl status_bar "$udid" clear 2>/dev/null || true
}

udid() { xcrun simctl list devices available | awk -v want="$1" -v os="${2:-26.5}" '$0 ~ "^-- iOS "os {on=1; next} /^--/{on=0} on && index($0, want" (") {match($0, /[0-9A-F-]{36}/); print substr($0, RSTART, RLENGTH); exit}'; }

[[ "$WHICH" == iphone || "$WHICH" == all ]] && capture iphone "$(udid "iPhone 17 Pro Max")" 1320 2868
[[ "$WHICH" == ipad || "$WHICH" == all ]] && capture ipad "$(udid "iPad Pro 13-inch (M5)")" 2064 2752
# iPhone Duo: the folded outer screen ("LCD", portrait) now; the unfolded inner screen
# ("LCD-1", landscape) once the simulator is unfolded in DeviceHub, as duo-inner.
[[ "$WHICH" == duo ]] && capture duo "$(udid "iPhone Duo" 27.1)" 1398 2034 LCD
[[ "$WHICH" == duo-inner ]] && capture duo-inner "$(udid "iPhone Duo" 27.1)" 2853 2007 LCD-1
echo "Framed screenshots in ios/$OUT"
