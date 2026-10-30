#!/bin/bash
# Compiles VolantInputHost's PasteKey with a checker that resolves the paste key in installed keyboard
# layouts (U.S., Dvorak, Dvorak – QWERTY ⌘, French). It reads layout data only; it never changes the
# input source or posts events.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/volant-paste-key.XXXXXX)
trap 'rm -rf "$work"' EXIT
cp tools/input-host/paste-key.swift "$work/main.swift"
swiftc VolantInputHost/PasteKey.swift "$work/main.swift" -o "$work/check"
"$work/check"
