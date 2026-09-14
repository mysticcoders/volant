#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
volume_check_dir=$(mktemp -d /tmp/volant-volume-check.XXXXXX)
trap 'rm -rf "$volume_check_dir"' EXIT
cp tools/volume/check.swift "$volume_check_dir/main.swift"
swiftc Shared/LauncherRouting.swift Volant/SystemControl/VolumeControl.swift "$volume_check_dir/main.swift" -o "$volume_check_dir/check"
"$volume_check_dir/check"
