#!/bin/bash
# Isolated native search/Return/dismiss/reopen fixture; no owner apps are launched.
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:?Usage: tools/profile-interaction.sh NEW_OUTPUT_DIRECTORY [cycles=30] [idle_ms=250] [release_app=/Applications/Volant.app]}
cycles=${2:-30}
idle_ms=${3:-250}
release_app=${4:-/Applications/Volant.app}
[[ "$cycles" =~ ^[0-9]+$ && "$idle_ms" =~ ^[0-9]+$ ]] || exit 2
((cycles >= 1 && cycles <= 200 && idle_ms <= 60000)) || exit 2
[[ ! -e "$output" && -f "$release_app/Contents/Resources/Assets.car" ]] || { echo 'Need a new output directory and compiled release assets.' >&2; exit 2; }
mkdir -p "$output"
output=$(cd "$output" && pwd)
bundle="$output/VolantInteractionFixture.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$output/data"
cp "$release_app/Contents/Resources/Assets.car" "$bundle/Contents/Resources/"
cp tools/interaction-speed/main.swift "$output/main.swift"
python3 - "$bundle" <<'PY'
import pathlib,plistlib,sys
path=pathlib.Path(sys.argv[1])/'Contents'/'Info.plist'
path.write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.mysticcoders.volant.InteractionFixture','CFBundleExecutable':'VolantInteractionFixture','CFBundleName':'Volant Interaction Fixture','CFBundlePackageType':'APPL','LSUIElement':True,'NSHighResolutionCapable':True}))
PY
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*')
swiftc -O "${sources[@]}" "$output/main.swift" -o "$bundle/Contents/MacOS/VolantInteractionFixture" 2> "$output/compile.log"
codesign --force --sign - "$bundle" 2> "$output/signing.log"
{
 date -u
 git rev-parse HEAD
 git diff --stat
 sw_vers
 uname -m
 shasum -a 256 "$bundle/Contents/MacOS/VolantInteractionFixture" "$bundle/Contents/Resources/Assets.car"
} > "$output/environment.txt"
"$bundle/Contents/MacOS/VolantInteractionFixture" "$output/data" "$cycles" "$idle_ms" > "$output/cycles.csv"
python3 tools/interaction-speed/summarize.py "$output/cycles.csv" > "$output/summary.txt"
cat "$output/summary.txt"
