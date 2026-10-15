#!/bin/bash
# Spike: can a sandboxed Volant tell which process owns a listening TCP port?
# Starts a fictional dev server (tools/process/ports.swift in listen mode) in a temporary project
# folder, probes it from two signed bundles that differ only by the App Sandbox entitlement, then
# stops it. The sandboxed bundle carries VolantDev.entitlements, the release set minus iCloud, because
# an ad-hoc signature cannot launch with the iCloud entitlement. Read-only: only the script's own listener is signalled, by the script, at the end.
set -euo pipefail
cd "$(dirname "$0")/.."
spike_dir=$(mktemp -d /tmp/volant-ports-spike.XXXXXX)
project="$spike_dir/my-vibe-app"
mkdir -p "$project"
port="${1:-47823}"
listener=""
trap '[[ -n "$listener" ]] && kill "$listener" 2>/dev/null; rm -rf "$spike_dir"' EXIT

swiftc -O -target "$(uname -m)-apple-macosx15.0" tools/process/ports.swift -o "$spike_dir/ports"

build() {
    local variant="$1" entitlements="$2"
    local bundle="$spike_dir/$variant.app/Contents"
    mkdir -p "$bundle/MacOS"
    cat > "$bundle/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>ports</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.portsspike.$variant</string><key>CFBundleName</key><string>Volant Ports Spike</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PLIST
    cp "$spike_dir/ports" "$bundle/MacOS/ports"
    codesign --force --sign - --entitlements "$entitlements" "$spike_dir/$variant.app" 2>/dev/null
    echo "$bundle/MacOS/ports"
}

sed 's|\$(PRODUCT_BUNDLE_IDENTIFIER)|com.mysticcoders.volant.portsspike.sandboxed|g' \
    Volant/VolantDev.entitlements > "$spike_dir/sandboxed.entitlements"
printf '%s' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>' > "$spike_dir/plain.entitlements"
plain=$(build plain "$spike_dir/plain.entitlements")
sandboxed=$(build sandboxed "$spike_dir/sandboxed.entitlements")

(cd "$project" && exec "$spike_dir/ports" listen "$port" > "$spike_dir/listener.txt") &
listener=$!
for _ in $(seq 1 50); do [[ -s "$spike_dir/listener.txt" ]] && break; sleep 0.1; done
[[ "$(head -1 "$spike_dir/listener.txt")" == "$listener" ]] || { echo "listener did not start: $(cat "$spike_dir/listener.txt")"; exit 1; }
sleep 1

echo "########## UNSANDBOXED ##########"
"$plain" probe "$port" "$listener" "$project" || echo "plain variant exited $?"
echo
echo "########## SANDBOXED (Volant entitlements) ##########"
"$sandboxed" probe "$port" "$listener" "$project" || echo "sandboxed variant exited $?"
