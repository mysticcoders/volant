#!/bin/bash
# Build the sample extension with rustup's toolchain (Homebrew's cargo lacks the wasm target) and pin its hash.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
rustup run stable cargo build --release --target wasm32-unknown-unknown
cp target/wasm32-unknown-unknown/release/hello_rust.wasm hello.wasm
python3 - <<'PY'
import hashlib, json, pathlib
p = pathlib.Path("manifest.json"); m = json.loads(p.read_text())
m["sha256"] = hashlib.sha256(pathlib.Path("hello.wasm").read_bytes()).hexdigest()
p.write_text(json.dumps(m, indent=2) + "\n")
PY
echo "built hello.wasm ($(wc -c < hello.wasm | tr -d ' ') bytes), hash pinned in manifest.json"
