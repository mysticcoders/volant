#!/bin/bash
# Passive collection: use the installed app normally while this script listens.
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:?Usage: tools/profile-summons.sh NEW_OUTPUT_DIRECTORY [seconds=120]}
seconds=${2:-120}
[[ "$seconds" =~ ^[0-9]+$ ]] && ((seconds >= 1 && seconds <= 3600)) || exit 2
[[ ! -e "$output" ]] || { echo 'Choose a new output directory.' >&2; exit 2; }
mkdir -p "$output"
output=$(cd "$output" && pwd)
{
 date -u
 sw_vers
 if [[ -f /Applications/Volant.app/Contents/MacOS/Volant ]]; then shasum -a 256 /Applications/Volant.app/Contents/MacOS/Volant; fi
} > "$output/environment.txt"
summarize() {
 python3 tools/interaction-speed/summarize-summons.py "$output/summons.log" > "$output/summary.txt"
 cat "$output/summary.txt"
}
trap summarize EXIT
echo "Use Volant normally for $seconds seconds. No keys are injected and no screen or query text is captured."
/usr/bin/log stream --style compact --level info --signpost --timeout "$seconds" \
 --predicate 'subsystem == "com.mysticcoders.volant" AND category == "Opening"' > "$output/summons.log"
