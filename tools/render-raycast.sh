#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
raycast_render_dir=$(mktemp -d /tmp/volant-raycast-render.XXXXXX)
trap 'rm -rf "$raycast_render_dir"' EXIT
cp tools/raycast/render.swift "$raycast_render_dir/main.swift"
swiftc -O Shared/LauncherRouting.swift Volant/Import/*.swift Volant/Settings/Preferences.swift Volant/Snippets/Snippets.swift Volant/Quicklinks/Quicklinks.swift Volant/HotKeys/KeyCombo.swift "$raycast_render_dir/main.swift" -o "$raycast_render_dir/render"
"$raycast_render_dir/render"
"$raycast_render_dir/render" dark
"$raycast_render_dir/render" empty
"$raycast_render_dir/render" dark compact
