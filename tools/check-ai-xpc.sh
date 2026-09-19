#!/bin/bash
# Headless signed fixture: no owner UI, provider accounts, keys or model inference.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VOLANT_AI_APP:?Path to exported Developer ID Volant.app}"
identity='Developer ID Application: Mystic Coders, LLC (REMBT6JY4N)'
fixture=$(mktemp -d /tmp/volant-ai-xpc.XXXXXX)
server_pid=''
cleanup() { [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true; rm -rf "$fixture"; }
trap cleanup EXIT
python3 tools/ai/server.py "$fixture/port" > "$fixture/server.log" 2>&1 &
server_pid=$!
for attempt in {1..100}; do [[ ! -s "$fixture/port" ]] || break; sleep 0.05; done
bundle="$fixture/AI Smoke.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/XPCServices"
ditto "$VOLANT_AI_APP/Contents/XPCServices/VolantAIHost.xpc" "$bundle/XPCServices/VolantAIHost.xpc"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>AISmoke</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.aismoke</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cp tools/ai/xpc.swift "$fixture/main.swift"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*')
swiftc "${sources[@]}" "$fixture/main.swift" -o "$bundle/MacOS/AISmoke"
codesign --force --sign "$identity" --options runtime --timestamp "$fixture/AI Smoke.app"
codesign --verify --deep --strict "$fixture/AI Smoke.app"
"$bundle/MacOS/AISmoke" "http://127.0.0.1:$(cat "$fixture/port")"
