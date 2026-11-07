#!/bin/bash
# Local preview of the website with the /try demo working end to end: builds the site, copies the
# calculator module (from tools/try-wasm/out, made by tools/try-wasm/build.sh) into local R2, starts
# wrangler dev with scheduled-event testing, and fires both Cron schedules once so the exchange
# rates are in local KV. State lives in .wrangler/try-state, outside dist/, so rebuilds keep it.
# Usage: scripts/try-preview.sh [port]    (default 8797)
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${1:-8797}"
STATE=.wrangler/try-state
npm run build >/dev/null
NAME="$(node -e "process.stdout.write(require('./public/try/calculator.json').file)")"
for ENCODING in br gz; do
  npx --no-install wrangler r2 object put "volant-try/$NAME.$ENCODING" --file "../tools/try-wasm/out/$NAME.$ENCODING" \
    --content-type application/wasm --local --persist-to "$STATE" --config dist/server/wrangler.json >/dev/null
done
(
  for _ in $(seq 1 60); do
    curl -s -o /dev/null "http://127.0.0.1:$PORT/try" && break
    sleep 1
  done
  curl -s -o /dev/null "http://127.0.0.1:$PORT/cdn-cgi/handler/scheduled?cron=0+*/6+*+*+*"
  curl -s -o /dev/null "http://127.0.0.1:$PORT/cdn-cgi/handler/scheduled?cron=*/5+*+*+*+*"
  echo "Preview ready: http://127.0.0.1:$PORT/ (rates refreshed into local KV)"
) &
exec npx --no-install wrangler dev --config dist/server/wrangler.json --persist-to "$STATE" --test-scheduled --port "$PORT" --ip 127.0.0.1
