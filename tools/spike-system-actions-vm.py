#!/usr/bin/env python3
"""Run the system-actions spike in a disposable Tart guest, one boot per session.

Locking cannot be undone remotely, and sleep or a restart dialog changes the session, so each
state-changing step gets a fresh boot. Probes run in the console user's GUI session over SSH,
because Cirrus's vanilla images have no Tart guest agent. Nothing runs on the host desktop.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
vm = os.environ.get("VOLANT_RENDER_VM", "volant-render-27")
key = Path.home() / ".ssh" / "volant-render-vm"
output = Path(tempfile.mkdtemp(prefix="volant-system-actions-"))
print(f"Spike artifacts: {output}", flush=True)
subprocess.run(["./tools/spike-system-actions.sh", str(output / "build")], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for variant in ["Sandboxed", "Unsandboxed"]:
    subprocess.run(["ditto", "-c", "-k", "--keepParent", str(output / "build" / f"{variant} Probe.app"), str(output / f"{variant}.zip")], check=True)

ALL_SESSIONS = [
    ("baseline", [(v, a) for v in ["Sandboxed", "Unsandboxed"] for a in ["permissions", "screensaver", "displaysleep"]] + [("Sandboxed", "lock")]),
    ("lock-unsandboxed", [("Unsandboxed", "lock")]),
    ("restart-sandboxed", [("Sandboxed", "restartdialog")]),
    ("restart-unsandboxed", [("Unsandboxed", "restartdialog")]),
    ("sleep-sandboxed", [("Sandboxed", "sleep")]),
    ("sleep-unsandboxed", [("Unsandboxed", "sleep")]),
    ("lock-sandboxed", [("Sandboxed", "lock")]),
    ("screensaver-unsandboxed", [("Unsandboxed", "screensaver")]),
    ("screensaver-sandboxed", [("Sandboxed", "screensaver")]),
]
import sys
wanted = sys.argv[1:]
SESSIONS = [s for s in ALL_SESSIONS if not wanted or s[0] in wanted]
ssh = ["ssh", "-i", str(key), "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=5", "-o", "IdentitiesOnly=yes"]
results = []
for name, steps in SESSIONS:
    vms = json.loads(subprocess.check_output(["tart", "list", "--format", "json"]))
    if next((item for item in vms if item["Name"] == vm and item["Source"] == "local"), {}).get("Running"):
        raise SystemExit(f"{vm} is already running")
    log = (output / f"{name}-tart.log").open("w")
    process = subprocess.Popen(["tart", "run", vm, "--no-graphics", "--no-audio", "--no-clipboard", f"--dir=artifacts:{output}"], stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 300
        while True:
            address = subprocess.run(["tart", "ip", vm], capture_output=True, text=True).stdout.strip()
            if address and subprocess.run(ssh + [f"admin@{address}", "who | grep -q console"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                break
            if time.monotonic() > deadline:
                raise RuntimeError("guest not ready")
            time.sleep(3)
        setup = "root=/tmp/sysact; rm -rf $root; mkdir -p $root; cd $root; for v in Sandboxed Unsandboxed; do ditto -x -k \"/Volumes/My Shared Files/artifacts/$v.zip\" .; done; sw_vers -productVersion"
        version = subprocess.run(ssh + [f"admin@{address}", setup], capture_output=True, text=True, timeout=60).stdout.strip()
        for variant, action in steps:
            command = f"sudo launchctl asuser $(id -u admin) sudo -u admin '/tmp/sysact/{variant} Probe.app/Contents/MacOS/SystemActionsProbe' {action}"
            try:
                out = subprocess.run(ssh + [f"admin@{address}", command], capture_output=True, text=True, timeout=60).stdout.strip().splitlines()
                line = next((l for l in reversed(out) if l.startswith("{")), None)
                result = json.loads(line) if line else {"noOutput": True}
            except subprocess.TimeoutExpired:
                result = {"timedOut": True}
            if action in ("screensaver",):
                subprocess.run(ssh + [f"admin@{address}", "killall ScreenSaverEngine legacyScreenSaver 2>/dev/null; true"], timeout=20)
            if action == "restartdialog":
                # The restart dialog restarts on its own after a 60 second countdown; a consent
                # prompt does not. A changed boot time is the proof of which one appeared.
                boot = lambda: subprocess.run(ssh + [f"admin@{address}", "sysctl -n kern.boottime"], capture_output=True, text=True, timeout=20).stdout.strip()
                before = boot()
                time.sleep(80)
                deadline = time.monotonic() + 240
                after = ""
                while time.monotonic() < deadline:
                    address = subprocess.run(["tart", "ip", vm], capture_output=True, text=True).stdout.strip()
                    try: after = boot()
                    except subprocess.TimeoutExpired: after = ""
                    if after: break
                    time.sleep(5)
                result["bootTimeChanged"] = bool(after) and after != before
            if action == "sleep":
                time.sleep(15)
                alive = subprocess.run(ssh + [f"admin@{address}", "pmset -g log | grep -E ' (Sleep|Wake) ' | tail -3"], capture_output=True, text=True, timeout=40)
                result["afterSleep"] = alive.stdout.strip().splitlines()[-3:] if alive.returncode == 0 else "unreachable"
            entry = {"session": name, "guest": version, "variant": variant, "action": action, "result": result}
            results.append(entry)
            print(json.dumps(entry), flush=True)
    finally:
        subprocess.run(["tart", "stop", vm], check=False, timeout=60)
        process.wait(timeout=60)
        log.close()
(output / "results.json").write_text(json.dumps(results, indent=2))
print(f"Results: {output / 'results.json'}")
