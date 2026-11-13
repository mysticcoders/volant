#!/bin/bash
# Builds the /try calculator module (build.sh), uploads its brotli and gzip copies to the private R2
# bucket the website worker serves them from, writes website/public/try/calculator.json (its name and
# sizes, for the progress bar), and recaptures the homepage hero's example answers from the new module.
#
#   tools/try-wasm/publish-calculator.sh           upload to Cloudflare (the volant-try bucket)
#   tools/try-wasm/publish-calculator.sh --local   upload to the local wrangler dev state instead
#
# Needs everything build.sh needs, and wrangler signed in to the account that owns the bucket.
# Uploading doesn't deploy the website: commit calculator.json and the hero fixture, then deploy
# through Scripts/ship.sh as usual. Old module versions stay in the bucket until removed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="--remote"
[[ "${1:-}" == "--local" ]] && TARGET="--local"
NAME="$("$ROOT/tools/try-wasm/build.sh")"
OUT="$ROOT/tools/try-wasm/out"
cd "$ROOT/website"
CONFIG=()
if [[ "$TARGET" == "--local" ]]; then
  [[ -f dist/server/wrangler.json ]] || npm run build >/dev/null
  # The same state folder scripts/try-preview.sh serves from; dist/ is wiped by every build.
  CONFIG=(--config dist/server/wrangler.json --persist-to .wrangler/try-state)
fi
for ENCODING in br gz; do
  npx --no-install wrangler r2 object put "volant-try/$NAME.$ENCODING" --file "$OUT/$NAME.$ENCODING" \
    --content-type application/wasm "$TARGET" ${CONFIG[@]+"${CONFIG[@]}"}
done
printf '{"file":"%s","bytes":%s,"brotliBytes":%s,"gzipBytes":%s}\n' "$NAME" \
  "$(stat -f %z "$OUT/$NAME")" "$(stat -f %z "$OUT/$NAME.br")" "$(stat -f %z "$OUT/$NAME.gz")" \
  > "$ROOT/website/public/try/calculator.json"
node "$ROOT/website/scripts/try-hero-capture.mjs" "$OUT/$NAME"
echo "Published $NAME $TARGET"
cat "$ROOT/website/public/try/calculator.json"
