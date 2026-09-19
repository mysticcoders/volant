#!/bin/bash
# Build locally; third-party runtime bytes are not checked in or bundled with Volant.
set -euo pipefail
cd "$(dirname "$0")/raycast-wasm"
if [[ -z "${JAVY:-}" ]]; then
    case "$(uname -s):$(uname -m)" in
        Darwin:arm64) platform=arm-macos; checksum=99e9ec6a8e8c98e119d137c08a921d2443d3b873c675a5571e1800f4451e6294 ;;
        Darwin:x86_64) platform=x86_64-macos; checksum=6eed2927575dc2b3fb5a1563eee1ce0874e6da91c9cec39a728c9377a8cc7b5a ;;
        *) echo 'Set JAVY to a Javy 9.1.0 executable on this platform.' >&2; exit 1 ;;
    esac
    compiler=$(mktemp -d /tmp/volant-javy-build.XXXXXX)
    trap 'rm -rf "$compiler"' EXIT
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 "https://github.com/bytecodealliance/javy/releases/download/v9.1.0/javy-$platform-v9.1.0.gz" -o "$compiler/javy.gz"
    printf '%s  %s\n' "$checksum" "$compiler/javy.gz" | shasum -a 256 -c -
    gzip -dc "$compiler/javy.gz" > "$compiler/javy"
    chmod +x "$compiler/javy"
    export JAVY="$compiler/javy"
fi
npm ci --ignore-scripts
npm run build
npm test
