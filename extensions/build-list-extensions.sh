#!/bin/bash
# Builds the Hacker News and Lobsters list extensions for ABI 1 and pins each module's SHA-256 in its
# manifest. Uses rustup's toolchain (Homebrew's cargo lacks the wasm target). To try one, copy its
# folder (manifest.json and the .wasm) into Volant's extensions folder: Settings → Extensions → Open Folder.
#
# Usage: extensions/build-list-extensions.sh [hackernews] [lobsters]
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
names=("$@"); [ ${#names[@]} -gt 0 ] || names=(hackernews lobsters)
for name in "${names[@]}"; do
  (cd "$name" && rustup run stable cargo test --quiet && \
    RUSTFLAGS="-C link-arg=--max-memory=16777216" rustup run stable cargo build --quiet --release --target wasm32-unknown-unknown)
  cp "$name/target/wasm32-unknown-unknown/release/volant_$name.wasm" "$name/$name.wasm"
  python3 - "$name" <<'PY'
import hashlib, json, pathlib, sys
folder = pathlib.Path(sys.argv[1])
manifest = folder / "manifest.json"
data = json.loads(manifest.read_text())
data["sha256"] = hashlib.sha256((folder / data["module"]).read_bytes()).hexdigest()
manifest.write_text(json.dumps(data, indent=2) + "\n")
PY
  echo "built $name/$name.wasm ($(wc -c < "$name/$name.wasm" | tr -d ' ') bytes), hash pinned in $name/manifest.json"
done
