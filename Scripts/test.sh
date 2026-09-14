#!/bin/bash
# Run the unit tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swiftlint lint --strict --quiet --config .swiftlint.yml
./tools/check-raycast.sh
./tools/check-launcher.sh
xcodegen generate --quiet
xcodebuild -project Volant.xcodeproj -scheme Volant -derivedDataPath build test 2>&1 | grep -E "Test (Suite|Case).*(passed|failed)|error:" | tail -20
