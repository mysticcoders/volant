#!/usr/bin/env python3
"""Run the destructive half of the process spike in a headless Tart guest.

Quitting a real application is the only way to learn whether NSRunningApplication.terminate()
works from inside App Sandbox. That must never happen on the owner's desktop, so it happens
against TextEdit in a throwaway guest, the same rule tools/test-ui-vm.py follows.
"""
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
vm = os.environ.get("VOLANT_UI_VM", "volant-ui-xcode")
output = Path(tempfile.mkdtemp(prefix="volant-process-spike-"))
print(f"Tart spike artifacts: {output}", flush=True)

vms = json.loads(subprocess.check_output(["tart", "list", "--format", "json"]))
match = next((item for item in vms if item["Source"] == "local" and item["Name"] == vm), None)
if match is None:
    raise SystemExit(f"Prepare {vm} using docs/ui-testing.md. Nothing was run on the host.")
if match["Running"]:
    raise SystemExit(f"{vm} is already running; wait for its current work to finish.")

with tarfile.open(output / "source.tar", "w") as archive:
    archive.add("tools/process/main.swift", arcname="tools/process/main.swift", recursive=False)
    archive.add("Volant/Volant.entitlements", arcname="Volant/Volant.entitlements", recursive=False)

guest_script = r'''#!/bin/bash
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
root=$(mktemp -d /tmp/volant-process-spike.XXXXXX)
output='/Volumes/My Shared Files/artifacts'
cd "$root"
tar -xf "$output/source.tar"

sed 's|\$(PRODUCT_BUNDLE_IDENTIFIER)|com.mysticcoders.volant.processspike|g' \
    Volant/Volant.entitlements > sandboxed.entitlements
cat > plain.entitlements <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST

swiftc -O tools/process/main.swift -o probe

build() {
    local variant="$1" entitlements="$2"
    local bundle="$root/$variant.app/Contents"
    mkdir -p "$bundle/MacOS"
    cat > "$bundle/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>probe</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.processspike.$variant</string><key>CFBundleName</key><string>Spike</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PLIST
    cp probe "$bundle/MacOS/probe"
    codesign --force --sign - --entitlements "$entitlements" "$root/$variant.app" 2>/dev/null
}

build plain plain.entitlements
build sandboxed sandboxed.entitlements

attempt() {
    local variant="$1"
    echo "########## $variant ##########"
    open -a TextEdit || true
    sleep 3
    if ! pgrep -x TextEdit >/dev/null; then echo "TextEdit did not launch; skipping"; return; fi
    set +e
    "$root/$variant.app/Contents/MacOS/probe" terminate com.apple.TextEdit 2>&1 | grep -v sandbox_extension_issue_file
    echo "probe exit: $?"
    set -e
    if pgrep -x TextEdit >/dev/null; then
        echo "TextEdit still running after probe; cleaning up with kill from the shell"
        pkill -x TextEdit || true
        sleep 1
    fi
}

attempt plain
attempt sandboxed
echo "########## done ##########"
'''
(output / "guest.sh").write_text(guest_script)

log = (output / "tart.log").open("w")
process = subprocess.Popen(
    ["tart", "run", vm, "--no-graphics", "--no-audio", "--no-clipboard", f"--dir=artifacts:{output}"],
    stdout=log, stderr=subprocess.STDOUT)
try:
    deadline = time.time() + 300
    while True:
        if process.poll() is not None:
            raise RuntimeError(f"Tart stopped during boot; see {output / 'tart.log'}")
        probe = subprocess.run(["tart", "exec", vm, "/usr/bin/true"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        if probe.returncode == 0:
            break
        if time.time() > deadline:
            raise RuntimeError("Guest did not become reachable")
        time.sleep(5)
    with (output / "spike.log").open("w") as spike_log:
        subprocess.run(["tart", "exec", vm, "/bin/bash", "/Volumes/My Shared Files/artifacts/guest.sh"],
                       check=False, stdout=spike_log, stderr=subprocess.STDOUT, timeout=900)
finally:
    subprocess.run(["tart", "stop", vm], check=False, timeout=60)
    process.wait(timeout=60)
    log.close()

print((output / "spike.log").read_text())
