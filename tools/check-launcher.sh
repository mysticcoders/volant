#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/app-module.sh
launcher_check_dir=$(mktemp -d /tmp/volant-launcher-check.XXXXXX)
trap 'rm -rf "$launcher_check_dir"' EXIT
# The fixture imports the app module built once by tools/app-module.sh; its FAIL lines count the added
# import, so they read one more than the line in tools/launcher/check.swift.
{ echo '@testable import VolantApp'; cat tools/launcher/check.swift; } > "$launcher_check_dir/main.swift"
python3 tools/run-bounded-check.py 300 "Compile launcher fixtures" swiftc "${VOLANT_APP_FLAGS[@]}" "$launcher_check_dir/main.swift" -o "$launcher_check_dir/check"
python3 tools/run-bounded-check.py 120 "Light launcher interactions" "$launcher_check_dir/check" "$launcher_check_dir"
python3 tools/run-bounded-check.py 120 "Dark launcher interactions" "$launcher_check_dir/check" "$launcher_check_dir" dark
