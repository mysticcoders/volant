#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/volant-ai-http.XXXXXX)
server_pid=''
cleanup() { [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true; rm -rf "$fixture"; }
trap cleanup EXIT
"${VOLANT_TEST_PYTHON:-python3}" tools/ai/server.py "$fixture/port" > "$fixture/server.log" 2>&1 &
server_pid=$!
for attempt in {1..300}; do
    [[ ! -s "$fixture/port" ]] || break
    kill -0 "$server_pid" 2>/dev/null || break
    sleep 0.1
done
[[ -s "$fixture/port" ]] || { echo 'AI fixture server did not start'; cat "$fixture/server.log"; exit 1; }
swiftc -parse-as-library Shared/ACPTypes.swift Shared/AIHTTPTypes.swift Shared/AIHTTPTransport.swift VolantAIHost/AIHTTPHost.swift tools/ai/check.swift -o "$fixture/check"
"$fixture/check" "http://127.0.0.1:$(cat "$fixture/port")"
