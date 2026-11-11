#!/bin/bash
# Renders the 10-feature demo video: the real Volant views with fictional data, scripted by
# tools/marketing/video/scenes.json, drawn in the render VM (tools/render-vm.py --video), then encoded
# into dist-video/clips/*.mp4 (one per scene, each with its title card) and dist-video/volant-features.mp4.
# Arguments go to render-vm.py, for example --scenes 3,0 to redraw one scene and the end card.
# Set VOLANT_VIDEO_FRAMES to a folder of frames from an earlier run to encode again without the VM.
set -euo pipefail
cd "$(dirname "$0")/.."
images=${VOLANT_VIDEO_FRAMES:-}
if [[ -z "$images" ]]; then
    log=$(mktemp /tmp/volant-video-render.XXXXXX)
    python3 tools/render-vm.py --video "$@" | tee "$log"
    grep -q "VolantVideo dark: exit 0" "$log" || { echo "The video fixture failed; see the log above" >&2; exit 1; }
    images=$(sed -n 's/^Images: //p' "$log")
fi
python3 tools/marketing/video/encode.py "$images" --output dist-video
