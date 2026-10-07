#!/usr/bin/env python3
"""Profile the memory of the real Volant app in a disposable headless Tart guest.

The host builds the Release app unsigned and signs it ad hoc. The iCloud key-value entitlement is
left out because it needs a provisioning profile; everything else, the sandbox included, is
kept. The guest seeds fictional data only (generated notes, generated clipboard text and system
wallpaper images), launches the app with `--memory-check` and, at each phase the app pauses on,
records `footprint`, `vmmap -summary`, `heap --sortBySize` and the helper processes attributed to
Volant. Nothing runs on the host desktop and no owner data is read. The guest is stopped
afterward. VM numbers are functional evidence, not a measurement of the owner's installed app.

The guest persists between runs, so each run first deletes the app's container and the
clipboard key: a key created under an earlier ad hoc signature makes the keychain ask for
access, which blocks launch, and leftover notes, clipboard history or phase markers would skew
the next run.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent.parent
os.chdir(ROOT)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--vm", default=os.environ.get("VOLANT_RENDER_VM", "volant-render-27"))
parser.add_argument("--label", default="run", help="name for this run's artifacts")
args = parser.parse_args()
KEY = Path.home() / ".ssh" / "volant-render-vm"
if not KEY.exists():
    raise SystemExit(f"Install an SSH key in the guest first; see docs/ui-testing.md ({KEY} is missing).")
output = Path(tempfile.mkdtemp(prefix=f"volant-memory-app-{args.label}-"))
print(f"Memory artifacts: {output}", flush=True)

print("Building the Release app on the host", flush=True)
subprocess.run(["xcodegen", "generate", "--quiet"], check=True)
subprocess.run(["xcodebuild", "-project", "Volant.xcodeproj", "-scheme", "Volant", "-configuration", "Release",
                "-derivedDataPath", str(output / "build"), "CODE_SIGNING_ALLOWED=NO", "build"],
               check=True, stdout=(output / "build.log").open("w"), stderr=subprocess.STDOUT)
app = output / "build" / "Build" / "Products" / "Release" / "Volant.app"
for framework in sorted((app / "Contents" / "Frameworks").glob("*.framework")):
    subprocess.run(["codesign", "-f", "-s", "-", "--deep", str(framework)], check=True, capture_output=True)
for service in sorted((app / "Contents" / "XPCServices").glob("*.xpc")):
    entitlements = ROOT / service.stem / f"{service.stem}.entitlements"
    command = ["codesign", "-f", "-s", "-"] + (["--entitlements", str(entitlements)] if entitlements.exists() else []) + [str(service)]
    subprocess.run(command, check=True, capture_output=True)
with (ROOT / "Volant" / "Volant.entitlements").open("rb") as source:
    entitlements = plistlib.load(source)
entitlements.pop("com.apple.developer.ubiquity-kvstore-identifier", None)
names = entitlements.get("com.apple.security.temporary-exception.mach-lookup.global-name", [])
entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] = [
    name.replace("$(PRODUCT_BUNDLE_IDENTIFIER)", "com.mysticcoders.volant") for name in names]
with (output / "app.entitlements").open("wb") as target:
    plistlib.dump(entitlements, target)
subprocess.run(["codesign", "-f", "-s", "-", "--entitlements", str(output / "app.entitlements"), str(app)], check=True, capture_output=True)
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(output / "Volant.zip")], check=True)

guest_script = r'''#!/bin/bash
set -uo pipefail
output='/Volumes/My Shared Files/artifacts'
root=$(mktemp -d /tmp/volant-memory.XXXXXX)
ditto -x -k "$output/Volant.zip" "$root"
sw_vers > "$output/guest-version.txt"
container="$HOME/Library/Containers/com.mysticcoders.volant/Data"
markers="$container/tmp/memory-check"
for index in 1 2 3 4; do
    wallpaper=$(ls /System/Library/Desktop\ Pictures/*.heic 2>/dev/null | sed -n "${index}p")
    [[ -n "$wallpaper" ]] && sips -s format png -Z 1400 "$wallpaper" --out "$root/fictional-$index.png" >/dev/null 2>&1
done

helpers() {
    ps -axo pid,ppid,rss,lstart,comm | grep -E 'Volant|SafariPlatformSupport|CredentialProvider|AutoFill' | grep -v grep
    for pid in $(pgrep -f 'SafariPlatformSupport.Helper|CredentialProviderExtensionHelper|AutoFill'); do
        echo "helper $pid: $(sudo -n launchctl procinfo "$pid" 2>/dev/null | grep -iE 'responsible (pid|path)' | tr -s ' \t' ' ' | tr '\n' ';')"
    done
}

sample() {
    local phase="$1" pid
    pid=$(pgrep -x Volant | head -1)
    [[ -n "$pid" ]] || { echo "no Volant process at $phase" >> "$output/summary.txt"; return; }
    footprint "$pid" > "$output/$phase-footprint.txt" 2>&1
    vmmap -summary "$pid" > "$output/$phase-vmmap.txt" 2>&1
    sudo -n heap --sortBySize "$pid" > "$output/$phase-heap.txt" 2>&1 || heap --sortBySize "$pid" > "$output/$phase-heap.txt" 2>&1
    helpers > "$output/$phase-helpers.txt" 2>&1
    for host in VolantAgentHost VolantRatesHost VolantExtensionHost VolantAIHost; do
        hp=$(pgrep -x "$host" | head -1)
        [[ -n "$hp" ]] && footprint "$hp" 2>/dev/null | head -3 >> "$output/$phase-helpers.txt"
    done
}

seed() {
    mkdir -p "$container/Library/Application Support/Vey/Notes"
    for index in $(seq 1 200); do
        { echo "# Fictional note $index"; echo; for line in $(seq 1 60); do echo "Line $line of a made-up note about project $index, with some words to search."; done; } \
            > "$container/Library/Application Support/Vey/Notes/fictional-$index.md"
    done
    for index in $(seq 1 25); do
        echo "Fictional clipboard text $index: the quick brown fox jumps over the lazy dog." | pbcopy
        sleep 1
    done
    for image in "$root"/fictional-*.png; do
        [[ -f "$image" ]] || continue
        osascript -e "set the clipboard to (read (POSIX file \"$image\") as «class PNGf»)" >/dev/null 2>&1
        sleep 1.5
    done
}

: > "$output/summary.txt"
pkill -x Volant 2>/dev/null
rm -rf "$HOME/Library/Containers/com.mysticcoders.volant"
while security delete-generic-password -s com.mysticcoders.vey.clipboard-key >/dev/null 2>&1; do :; done
helpers > "$output/before-launch-helpers.txt" 2>&1
open -n --stdout "$output/app.log" --stderr "$output/app.err" "$root/Volant.app" --args --memory-check
for phase in launch summon typed settings closed relieved; do
    deadline=$((SECONDS + 300))
    until [[ -f "$markers/$phase.ready" ]]; do
        if (( SECONDS > deadline )); then echo "timed out waiting for $phase" >> "$output/summary.txt"; break 2; fi
        sleep 1
    done
    sample "$phase"
    [[ "$phase" == launch ]] && { seed; sample "seeded"; }
    touch "$markers/$phase.go"
done
for _ in $(seq 1 30); do pgrep -x Volant >/dev/null || break; sleep 1; done
pkill -x Volant 2>/dev/null
grep '^memory-check' "$output/app.log" >> "$output/summary.txt" 2>/dev/null
cp "$HOME"/Library/Logs/DiagnosticReports/Volant* "$output/" 2>/dev/null
log show --last 10m --style compact --predicate 'process == "Volant"' 2>/dev/null | grep -iE 'crash|fault|exception|terminat' | tail -40 > "$output/app-system-log.txt"
'''
(output / "guest.sh").write_text(guest_script)

vms = json.loads(subprocess.check_output(["tart", "list", "--format", "json"]))
match = next((item for item in vms if item["Source"] == "local" and item["Name"] == args.vm), None)
if match is None:
    raise SystemExit(f"Clone {args.vm} first; see docs/ui-testing.md")
if match["Running"]:
    raise SystemExit(f"{args.vm} is already running; wait for its current work to finish. No host fallback.")
log = (output / "tart.log").open("w")
process = subprocess.Popen(["tart", "run", args.vm, "--no-graphics", "--no-audio", "--no-clipboard", f"--dir=artifacts:{output}"],
                           stdout=log, stderr=subprocess.STDOUT)
try:
    ssh = ["ssh", "-i", str(KEY), "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
           "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=5", "-o", "IdentitiesOnly=yes"]
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
                   check=False, timeout=1800)
    print((output / "summary.txt").read_text(), flush=True)
finally:
    if process.poll() is None:
        subprocess.run(["tart", "stop", args.vm], check=False, timeout=60)
        process.wait(timeout=60)
    log.close()
