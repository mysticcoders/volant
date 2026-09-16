#!/bin/bash
set -euo pipefail
root=/tmp/volant-installed-final-ab
mkdir -p "$root"
ditto /Applications/Volant.app "$root/original.app"
restore() {
 /tmp/volant-switch-benchmark --quit || return
 if [[ -d /Applications/Volant.app ]]; then mv /Applications/Volant.app "$root/finished-$(date +%s).app"; fi
 ditto "$root/original.app" /Applications/Volant.app
 /tmp/volant-switch-benchmark /Applications/Volant.app
}
trap restore EXIT
for round in 1 2 3; do
 for target in candidate baseline; do
  /tmp/volant-switch-benchmark --quit
  mv /Applications/Volant.app "$root/displaced-$target-$round.app"
  source="$root/original.app"
  if [[ "$target" == candidate ]]; then source=/tmp/volant-faster-build/Build/Products/Release/Volant.app; fi
  ditto "$source" /Applications/Volant.app
  /tmp/volant-switch-benchmark /Applications/Volant.app
  shasum -a 256 /Applications/Volant.app/Contents/MacOS/Volant > "$root/$target-$round.sha256"
  /tmp/volant-compare-opening reopen volant > "$root/$target-reopen-$round.csv"
  /tmp/volant-compare-opening startup volant > "$root/$target-startup-$round.csv"
 done
done
