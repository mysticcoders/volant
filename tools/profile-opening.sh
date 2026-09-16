#!/bin/bash
# Opt-in local test of the installed app. Startup trials cleanly quit/relaunch it.
set -euo pipefail
cd "$(dirname "$0")/.."
opening_output=${1:?Usage: tools/profile-opening.sh NEW_OUTPUT_DIRECTORY}
mkdir -p "$opening_output"
opening_output=$(cd "$opening_output" && pwd)
swiftc -O tools/launch-speed/main.swift -o "$opening_output/VolantOpeningBenchmark"
{
    date -u
    git rev-parse HEAD
    shasum -a 256 tools/launch-speed/main.swift /Applications/Volant.app/Contents/MacOS/Volant
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Volant.app/Contents/Info.plist
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/Volant.app/Contents/Info.plist
    sw_vers
    uname -m
    sysctl hw.model hw.memsize
} > "$opening_output/environment.txt"
"$opening_output/VolantOpeningBenchmark" reopen > "$opening_output/reopen.csv"
"$opening_output/VolantOpeningBenchmark" startup > "$opening_output/startup.csv"
python3 tools/launch-speed/summarize.py "$opening_output" > "$opening_output/summary.md"
