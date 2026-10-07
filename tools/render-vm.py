#!/usr/bin/env python3
"""Render native fixtures on a newer macOS in a headless Tart guest that has no Xcode.

The fixtures are compiled on the host against its SDK, which is what decides whether AppKit and
SwiftUI draw the newer system styling such as Liquid Glass, and only the finished app bundles are
run in the guest. This is render evidence for a newer OS, not a test gate: a fixture that stops on
a behavioral check still returns the images it wrote before stopping, and its exit code is reported.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--vm", default=os.environ.get("VOLANT_RENDER_VM", "volant-render-27"))
args = parser.parse_args()
KEY = Path.home() / ".ssh" / "volant-render-vm"
if not KEY.exists():
    raise SystemExit(f"Install an SSH key in the guest first; see docs/ui-testing.md ({KEY} is missing).")
output = Path(tempfile.mkdtemp(prefix="volant-render-vm-"))
print(f"Render artifacts: {output}", flush=True)

FIXTURES = [
    ("VolantLauncherFixture", "tools/launcher/check.swift"),
    ("VolantActionsFixture", "tools/launcher/actions.swift"),
    ("VolantSettingsPreview", "tools/settings/main.swift"),
    ("VolantThemeFixture", "tools/themes/render.swift"),
]
build = f'''
set -euo pipefail
source tools/core-module.sh
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Volant Shared -name '*.swift' ! -path 'Volant/App/*')
for pair in {" ".join(f"{name}:{path}" for name, path in FIXTURES)}; do
    name="${{pair%%:*}}"; main="${{pair#*:}}"
    bundle="{output}/bundles/$name.app/Contents"
    mkdir -p "$bundle/MacOS" "$bundle/Resources" "{output}/work/$name"
    xcrun actool Volant/Resources/Assets.xcassets --compile "$bundle/Resources" --platform macosx --minimum-deployment-target 15.0 \\
        --target-device mac --optimization space --output-partial-info-plist "{output}/work/$name/assets.plist" >/dev/null
    cp Volant/Resources/emoji.json "$bundle/Resources/"
    ditto Volant/Resources/HelloWorld "$bundle/Resources/HelloWorld"
    printf '%s' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>'"$name"'</string><key>CFBundleIdentifier</key><string>com.mysticcoders.volant.render.'"$name"'</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>' > "$bundle/Info.plist"
    cp "$main" "{output}/work/$name/main.swift"
    swiftc -target "$(uname -m)-apple-macosx15.0" "${{VOLANT_CORE_FLAGS[@]}}" "${{sources[@]}}" "{output}/work/$name/main.swift" -o "$bundle/MacOS/$name"
done
'''
print("Compiling fixtures on the host", flush=True)
subprocess.run(["bash", "-c", build], check=True)
subprocess.run(["tar", "-cf", str(output / "bundles.tar"), "-C", str(output), "bundles"], check=True)

# Each fixture runs in both appearances; images are collected whatever the exit code.
runs = [
    ("VolantLauncherFixture", "light", "\"$work\""), ("VolantLauncherFixture", "dark", "\"$work\" dark"),
    ("VolantActionsFixture", "light", "\"$work\""), ("VolantActionsFixture", "dark", "\"$work\" dark"),
    ("VolantSettingsPreview", "both", "--render"),
    ("VolantThemeFixture", "all", "\"$work\""),
]
steps = "\n".join(
    f'work=$(mktemp -d /tmp/volant-render.XXXXXX)\n'
    f'set +e; "$root/bundles/{name}.app/Contents/MacOS/{name}" {arguments} > "$output/{name}-{label}.log" 2>&1; '
    f'echo "{name} {label}: exit $?" >> "$output/summary.txt"; set -e'
    for name, label, arguments in runs
)
guest_script = f'''#!/bin/bash
set -euo pipefail
output='/Volumes/My Shared Files/artifacts'
root=$(mktemp -d /tmp/volant-render-root.XXXXXX)
tar -xf "$output/bundles.tar" -C "$root"
sw_vers > "$output/guest-version.txt"
: > "$output/summary.txt"
{steps}
mkdir -p "$output/images"
# A window-server capture of live Settings, because offscreen caching cannot draw glass backdrops.
"$root/bundles/VolantSettingsPreview.app/Contents/MacOS/VolantSettingsPreview" > "$output/live-settings.log" 2>&1 &
preview=$!
sleep 4
screencapture -x "$output/images/live-settings-light.png" >> "$output/live-settings.log" 2>&1 || echo "screencapture failed: $?" >> "$output/live-settings.log"
kill "$preview" 2>/dev/null || true
for image in /tmp/volant-*.png /tmp/volant-*.jpg /tmp/volant-settings-renders/*.png; do
    [[ ! -f "$image" ]] || cp "$image" "$output/images/"
done
'''
(output / "guest.sh").write_text(guest_script)

vms = json.loads(subprocess.check_output(["tart", "list", "--format", "json"]))
match = next((item for item in vms if item["Source"] == "local" and item["Name"] == args.vm), None)
if match is None:
    raise SystemExit(f"Clone {args.vm} first, for example: tart clone ghcr.io/cirruslabs/macos-golden-gate-vanilla:27.0 {args.vm}")
if match["Running"]:
    raise SystemExit(f"{args.vm} is already running; wait for its current work to finish. No host fallback.")
log = (output / "tart.log").open("w")
process = subprocess.Popen(["tart", "run", args.vm, "--no-graphics", "--no-audio", "--no-clipboard", f"--dir=artifacts:{output}"],
                           stdout=log, stderr=subprocess.STDOUT)
try:
    # Cirrus's vanilla images have no Tart guest agent, only SSH for admin, who is logged in on the
    # console. Fixtures must run in that GUI session to reach the window server.
    ssh = ["ssh", "-i", str(KEY), "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
           "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=5"]
    deadline = time.monotonic() + 300
    while True:
        if process.poll() is not None:
            raise RuntimeError(f"Tart stopped during boot; see {output / 'tart.log'}")
        address = subprocess.run(["tart", "ip", args.vm], capture_output=True, text=True).stdout.strip()
        if address and subprocess.run(ssh + [f"admin@{address}", "who | grep -q console"],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            break
        if time.monotonic() >= deadline:
            raise RuntimeError("Guest SSH or console login did not become ready within 300 seconds")
        time.sleep(3)
    subprocess.run(ssh + [f"admin@{address}", "sudo launchctl asuser $(id -u admin) sudo -u admin /bin/bash '/Volumes/My Shared Files/artifacts/guest.sh'"],
                   check=True, timeout=1800)
    print((output / "guest-version.txt").read_text(), (output / "summary.txt").read_text(), sep="", flush=True)
    print(f"Images: {output / 'images'}", flush=True)
finally:
    if process.poll() is None:
        subprocess.run(["tart", "stop", args.vm], check=False, timeout=30)
        process.wait(timeout=30)
    log.close()
