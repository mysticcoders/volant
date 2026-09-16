#!/bin/bash
set -euo pipefail
root=/tmp/volant-layout-final-ab
mkdir -p "$root"
test -d "$root/original.app"
/usr/bin/log stream --style compact --level debug --signpost --timeout 10m --predicate 'subsystem == "com.mysticcoders.volant" AND category == "Opening"' >> "$root/signposts.log" 2>> "$root/signposts-stderr.log" &
trace_pid=$!
restore() {
 kill "$trace_pid" 2>/dev/null || true
 wait "$trace_pid" 2>/dev/null || true
 /tmp/volant-switch-benchmark --quit || return
 if [[ -d /Applications/Volant.app ]]; then mv /Applications/Volant.app "$root/finished-$(date +%s).app"; fi
 ditto "$root/original.app" /Applications/Volant.app
 /tmp/volant-switch-benchmark /Applications/Volant.app
}
trap restore EXIT
for round in 3; do
 for target in candidate baseline; do
  /tmp/volant-switch-benchmark --quit
  mv /Applications/Volant.app "$root/displaced-$target-$round.app"
  source="$root/original.app"
  if [[ "$target" == candidate ]]; then source=/tmp/volant-faster-build/Build/Products/Release/Volant.app; fi
  ditto "$source" /Applications/Volant.app
  /tmp/volant-switch-benchmark /Applications/Volant.app
  pgrep -x Volant > "$root/$target-$round.pid"
  shasum -a 256 /Applications/Volant.app/Contents/MacOS/Volant > "$root/$target-$round.sha256"
  /tmp/volant-layout-opening reopen volant > "$root/$target-reopen-$round.csv"
 done
done
