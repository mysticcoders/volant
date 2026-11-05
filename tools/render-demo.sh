#!/bin/bash
# Renders the README demo: the real launcher with fictional data, typed through an app search, a
# calculation and the agents list, in the render VM (tools/render-vm.py --demo), then assembled into
# website/public/images/volant-demo.webp. Each frame's file name carries how long it shows.
set -euo pipefail
cd "$(dirname "$0")/.."
log=$(mktemp /tmp/volant-demo-render.XXXXXX)
python3 tools/render-vm.py --demo "$@" | tee "$log"
images=$(sed -n 's/^Images: //p' "$log")
frames=()
while IFS= read -r frame; do
    milliseconds=$(basename "$frame" .png | cut -d- -f4)
    frames+=(-d "$milliseconds" "$frame")
done < <(find "$images" -name 'volant-demo-*.png' | sort)
(( ${#frames[@]} > 0 )) || { echo "No demo frames in $images" >&2; exit 1; }
img2webp -loop 0 -lossy -q 82 -m 6 "${frames[@]}" -o website/public/images/volant-demo.webp
ls -l website/public/images/volant-demo.webp
