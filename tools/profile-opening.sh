#!/bin/bash
# Opt-in local test of the installed app. Startup trials cleanly quit/relaunch it.
set -euo pipefail
cd "$(dirname "$0")/.."
opening_output=${1:?Usage: tools/profile-opening.sh NEW_OUTPUT_DIRECTORY [volant|raycast]}
opening_target=${2:-volant}
opening_modes=${3:-all}
case "$opening_modes" in all|reopen) ;; *) echo "Mode must be all or reopen" >&2; exit 2 ;; esac
case "$opening_target" in
  volant) opening_app=/Applications/Volant.app ;;
  raycast) opening_app=/Applications/Raycast.app ;;
  *) echo 'Target must be volant or raycast' >&2; exit 2 ;;
esac
opening_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$opening_app/Contents/Info.plist")
mkdir -p "$opening_output"
opening_output=$(cd "$opening_output" && pwd)
swiftc -O tools/launch-speed/main.swift -o "$opening_output/VolantOpeningBenchmark"
{
    date -u
    git rev-parse HEAD
    shasum -a 256 tools/launch-speed/main.swift "$opening_app/Contents/MacOS/$opening_executable"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$opening_app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$opening_app/Contents/Info.plist"
    sw_vers
    uname -m
    sysctl hw.model hw.memsize
} > "$opening_output/environment.txt"
"$opening_output/VolantOpeningBenchmark" reopen "$opening_target" > "$opening_output/reopen.csv"
if [[ "$opening_modes" == all ]]; then
    "$opening_output/VolantOpeningBenchmark" startup "$opening_target" > "$opening_output/startup.csv"
fi
python3 tools/launch-speed/summarize.py "$opening_output" "$opening_modes" > "$opening_output/summary.md"
