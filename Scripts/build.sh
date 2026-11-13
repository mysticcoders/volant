#!/bin/bash
# Prepare the Python test packages, regenerate the Xcode project and build the Debug app. Run from anywhere.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/python-env.sh
xcodegen generate --quiet
xcodebuild -project Volant.xcodeproj -scheme Volant -configuration Debug -derivedDataPath build -allowProvisioningUpdates build | tail -3
echo "built: $ROOT/build/Build/Products/Debug/Volant.app"
