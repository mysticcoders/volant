#!/bin/bash
# Builds the /try calculator module (VolantCore's CalculationAnswer.answers for wasm32-unknown-wasip1)
# and writes it, named by its content hash, to tools/try-wasm/out/ (git-ignored):
#   VolantAnswers-<hash>.wasm       the module (about 15.6 MB)
#   VolantAnswers-<hash>.wasm.br    brotli, what browsers download (about 4.1 MB)
#   VolantAnswers-<hash>.wasm.gz    gzip, for clients without brotli (about 5.6 MB)
# It prints the module's file name. publish-calculator.sh uploads them to R2.
#
# Steps: swift build -Osize, strip; trim ICU's common data to English (icu-keep.txt, icu-data.mjs);
# binaryen wasm-opt -Oz. Each step keeps answers identical (parity.mjs, native comparison).
# Needs the swift.org 6.4.2 open-source toolchain and its Wasm SDK (`swift sdk install` of
# swift-6.4.2-RELEASE_wasm; Xcode's compiler can't use the SDK), binaryen (`brew install binaryen`),
# brotli and Node.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SWIFT="${SWIFT:-$HOME/Library/Developer/Toolchains/swift-6.4.2-RELEASE.xctoolchain/usr/bin/swift}"
cd "$ROOT/tools/try-wasm"
"$SWIFT" build --swift-sdk swift-6.4.2-RELEASE_wasm -c release --product VolantAnswers -Xswiftc -Osize -Xlinker --strip-all >&2
mkdir -p out
rm -f out/VolantAnswers*.wasm out/VolantAnswers*.wasm.br out/VolantAnswers*.wasm.gz
node icu-data.mjs trim .build/release/VolantAnswers.wasm icu-keep.txt out/trimmed.wasm >&2
wasm-opt -Oz --enable-bulk-memory --enable-sign-ext --enable-mutable-globals --enable-nontrapping-float-to-int \
  out/trimmed.wasm -o out/VolantAnswers.wasm >&2
rm -f out/trimmed.wasm
HASH="$(shasum -a 256 out/VolantAnswers.wasm | cut -c1-16)"
NAME="VolantAnswers-$HASH.wasm"
mv out/VolantAnswers.wasm "out/$NAME"
brotli -q 11 -c "out/$NAME" > "out/$NAME.br"
gzip -9nc "out/$NAME" > "out/$NAME.gz"
echo "$NAME"
