#!/bin/bash
# Build the clipboard test extension in three folders under out/ for owner verification:
# v1 (granted clipboard.write), v2 (new code, same ID) and denied (v1 code, no capability).
# The v1 module is also kept beside this script for tools/check-extensions.sh.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
export RUSTFLAGS="-C link-arg=--max-memory=16777216"
build() {
    rustup run stable cargo build --release --target wasm32-unknown-unknown "$@"
}
package() {
    local dir="out/$1" version="$2" capabilities="$3"
    mkdir -p "$dir"
    cp target/wasm32-unknown-unknown/release/clipboard_test.wasm "$dir/clipboard.wasm"
    python3 - "$dir" "$version" "$capabilities" <<'PY'
import hashlib, json, pathlib, sys
dir, version, capabilities = pathlib.Path(sys.argv[1]), sys.argv[2], json.loads(sys.argv[3])
manifest = {
    "id": "com.mysticcoders.volant.clipboard-test",
    "name": "Clipboard Test",
    "version": version,
    "module": "clipboard.wasm",
    "capabilities": capabilities,
    "timeoutSeconds": 2,
    "sha256": hashlib.sha256((dir / "clipboard.wasm").read_bytes()).hexdigest(),
    "abiVersion": 1,
}
(dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY
}
rm -rf out
build
package v1 1.0.0 '["clipboard.write"]'
package denied 1.0.0 '[]'
build --features v2
package v2 2.0.0 '["clipboard.write"]'
cp out/v1/clipboard.wasm clipboard.wasm
for dir in out/*; do echo "built $dir ($(wc -c < "$dir/clipboard.wasm" | tr -d ' ') bytes)"; done
