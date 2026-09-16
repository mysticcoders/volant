#!/usr/bin/env python3
"""Run native UI checks in a dedicated, headless Tart guest; never fall back to host UI."""
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
output = Path(tempfile.mkdtemp(prefix="volant-ui-vm-"))
print(f"Tart UI artifacts: {output}", flush=True)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


vms = json.loads(subprocess.check_output(["tart", "list", "--format", "json"]))
match = next((item for item in vms if item["Source"] == "local" and item["Name"] == vm), None)
if match is None:
    raise SystemExit(f"Prepare {vm} using docs/ui-testing.md. No host UI tests were started.")
if match["Running"]:
    raise SystemExit(f"{vm} is already running; wait for its current work to finish. No host fallback.")

# Include dirty source and new files, excluding ignored build products and owner data.
paths = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"]).decode().split("\0")
with tarfile.open(output / "source.tar", "w") as archive:
    for name in sorted(set(filter(None, paths))):
        if Path(name).is_file():
            archive.add(name, arcname=name, recursive=False)

# Share only this isolated artifact directory, never the owner's home or clipboard.
guest_script = '''#!/bin/bash
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
root=$(mktemp -d /tmp/volant-ui-source.XXXXXX)
output='/Volumes/My Shared Files/artifacts'
finish() {
    result=$?
    trap - EXIT
    if [[ -d "$root/build/Logs/Test" ]]; then ditto "$root/build/Logs/Test" "$output/TestResults"; fi
    for image in /tmp/volant-launcher-*.jpg /tmp/volant-destinations-*.png /tmp/volant-snap-*.png /tmp/volant-core-*.png /tmp/volant-actions-*.png; do
        [[ ! -f "$image" ]] || cp "$image" "$output/"
    done
    exit "$result"
}
trap finish EXIT
cd "$root"
tar -xf "$output/source.tar"
sw_vers
xcodebuild -version
command -v xcodegen
Scripts/test.sh --ci --ui only
'''
(output / "guest.sh").write_text(guest_script)
log = (output / "tart.log").open("w")
process = subprocess.Popen(["tart", "run", vm, "--no-graphics", "--no-audio", "--no-clipboard", f"--dir=artifacts:{output}"], stdout=log, stderr=subprocess.STDOUT)
try:
    deadline = time.monotonic() + 180
    while True:
        if process.poll() is not None:
            raise RuntimeError(f"Tart stopped during boot; see {output / 'tart.log'}")
        try:
            probe = subprocess.run(["tart", "exec", vm, "/usr/bin/true"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
            ready = probe.returncode == 0
        except subprocess.TimeoutExpired:
            ready = False
        if ready:
            break
        if time.monotonic() >= deadline:
            raise RuntimeError("Tart guest agent did not become ready within 180 seconds")
        time.sleep(2)
    with (output / "ui.log").open("w") as ui_log:
        run("tart", "exec", vm, "/bin/bash", "/Volumes/My Shared Files/artifacts/guest.sh", stdout=ui_log, stderr=subprocess.STDOUT, timeout=1800)
    print(f"PASS: native UI checks in {vm}; results in {output}", flush=True)
finally:
    if process.poll() is None:
        subprocess.run(["tart", "stop", vm], check=False, timeout=30)
        process.wait(timeout=30)
    log.close()
