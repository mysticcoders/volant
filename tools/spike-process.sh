#!/bin/bash
# Spike: what can a process-management command do from inside App Sandbox?
# Builds one binary, runs it twice in signed app bundles that differ only by the
# App Sandbox entitlement, and diffs the result. Read-only: termination is probed
# with signal 0, which performs the permission check without sending a signal.
set -euo pipefail
cd "$(dirname "$0")/.."
spike_dir=$(mktemp -d /tmp/volant-process-spike.XXXXXX)
trap 'rm -rf "$spike_dir"' EXIT

build() {
    local variant="$1" entitlements="$2"
    local bundle="$spike_dir/$variant.app/Contents"
    mkdir -p "$bundle/MacOS"
    cat > "$bundle/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>probe</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.processspike.$variant</string><key>CFBundleName</key><string>Volant Process Spike</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PLIST
    cp "$spike_dir/probe" "$bundle/MacOS/probe"
    codesign --force --sign - --entitlements "$entitlements" "$spike_dir/$variant.app" 2>/dev/null
    echo "$bundle/MacOS/probe"
}

# The sandboxed variant carries Volant's own entitlements; the baseline carries none.
sed 's|\$(PRODUCT_BUNDLE_IDENTIFIER)|com.mysticcoders.volant.processspike.sandboxed|g' \
    Volant/Volant.entitlements > "$spike_dir/sandboxed.entitlements"
cat > "$spike_dir/plain.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST

swiftc -O tools/process/main.swift -o "$spike_dir/probe"

plain=$(build plain "$spike_dir/plain.entitlements")
sandboxed=$(build sandboxed "$spike_dir/sandboxed.entitlements")

"$plain" > "$spike_dir/plain.txt" 2>&1 || echo "plain variant exited $?" >> "$spike_dir/plain.txt"
"$sandboxed" > "$spike_dir/sandboxed.txt" 2>&1 || echo "sandboxed variant exited $?" >> "$spike_dir/sandboxed.txt"

echo "########## UNSANDBOXED ##########"
cat "$spike_dir/plain.txt"
echo
echo "########## SANDBOXED (Volant entitlements) ##########"
cat "$spike_dir/sandboxed.txt"
echo
echo "########## DIFF ##########"
diff "$spike_dir/plain.txt" "$spike_dir/sandboxed.txt" || true
