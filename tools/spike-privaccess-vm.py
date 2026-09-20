#!/usr/bin/env python3
"""Exercise the signed privileged-helper spike in a headless Tart guest.

The bundle is built and Developer ID signed on the host, because the guest has no signing
identity, then shipped in and run there. Quitting a real application never happens on the
owner's desktop.
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
output = Path(tempfile.mkdtemp(prefix="volant-privaccess-"))
print(f"Tart spike artifacts: {output}", flush=True)

vms = json.loads(subprocess.check_output(["tart", "list", "--format", "json"]))
match = next((item for item in vms if item["Source"] == "local" and item["Name"] == vm), None)
if match is None:
    raise SystemExit(f"Prepare {vm} using docs/ui-testing.md. Nothing was run on the host.")
if match["Running"]:
    raise SystemExit(f"{vm} is already running; wait for its current work to finish.")

build = output / "build"
subprocess.run(["./tools/spike-privaccess.sh", str(build)], check=True, stdout=subprocess.DEVNULL)

# ditto preserves the signature; tar of the .app keeps extended attributes off, so use a
# ditto-made zip which is the documented way to move a signed bundle intact.
archive = output / "spike.zip"
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(build / "PrivAccess Spike.app"), str(archive)], check=True)
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(build / "Intruder.app"), str(output / "intruder.zip")], check=True)

guest_script = r'''#!/bin/bash
set -uo pipefail
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
output='/Volumes/My Shared Files/artifacts'
root=$(mktemp -d /tmp/volant-privaccess.XXXXXX)
cd "$root"
ditto -x -k "$output/spike.zip" .
ditto -x -k "$output/intruder.zip" .
app="$root/PrivAccess Spike.app"

echo "### signature verification in guest"
codesign --verify --deep --strict --verbose=2 "$app" 2>&1 | tail -4
echo "### helper entitlements as shipped"
codesign -d --entitlements - "$app/Contents/XPCServices/VolantPrivAccessHost.xpc" 2>&1 | tail -4

echo
echo "### launching TextEdit"
open -a TextEdit || true
sleep 4
pgrep -x TextEdit >/dev/null || { echo "TextEdit did not launch"; exit 2; }

echo "### running INTRUDER client (ad-hoc signed, genuine helper)"
"$root/Intruder.app/Contents/MacOS/PrivAccessSpike" com.apple.TextEdit 2>&1 | grep -v sandbox_extension_issue_file
echo "intruder exit: $?"
if pgrep -x TextEdit >/dev/null; then echo "### TextEdit survived the intruder"; else echo "### WARNING intruder killed it"; fi

echo
echo "### running legitimate sandboxed client"
"$app/Contents/MacOS/PrivAccessSpike" com.apple.TextEdit 2>&1 | grep -v sandbox_extension_issue_file
echo "client exit: $?"

echo "### helper crash reports, if any"
ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | head -5
for report in $(ls -t ~/Library/Logs/DiagnosticReports/*PrivAccess* ~/Library/Logs/DiagnosticReports/*Volant* 2>/dev/null | head -2); do
    echo "--- $report"
    head -30 "$report"
done
echo "### recent xpc log"
log show --last 3m --info --debug --predicate 'eventMessage CONTAINS[c] "privaccess" OR process == "xpcproxy" OR process == "secinitd" OR process == "amfid"' 2>/dev/null | grep -iv "^Timestamp" | grep -i -E "privaccess|xpcproxy|denied|refus|invalid|error|sandbox" | tail -25

if pgrep -x TextEdit >/dev/null; then
    echo "### TextEdit survived; cleaning up from the shell"
    pkill -x TextEdit || true
else
    echo "### TextEdit is gone"
fi
echo "### done"
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
        if subprocess.run(["tart", "exec", vm, "/usr/bin/true"], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, timeout=15).returncode == 0:
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
