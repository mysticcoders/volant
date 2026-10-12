#!/bin/bash
# Builds the list fixture used by tools/check-extensions.sh. Paths are remapped so no machine path ends
# up in the committed module.
set -euo pipefail
cd "$(dirname "$0")"
RUSTFLAGS="-C link-arg=--max-memory=16777216 --remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo --remap-path-prefix=$PWD=/src" \
  rustup run stable cargo build --quiet --release --target wasm32-unknown-unknown
cp target/wasm32-unknown-unknown/release/list_fixture.wasm list-fixture.wasm
echo "built list-fixture.wasm ($(wc -c < list-fixture.wasm | tr -d ' ') bytes)"
