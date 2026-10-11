#!/usr/bin/env python3
"""Run installed-app acceptance checks for Settings (#2), app shortcuts (#3) and translation (#5)
in a disposable clone of the UI test VM.

The notarized release DMG (the newest one in website/public/updates unless --dmg names another) is
installed into a throwaway clone of `volant-ui-xcode` and driven from SSH with system key events
and AppleScript UI scripting. Each check reads its result independently of the app: the process
list, the frontmost app, config.json, the login-item database or the clipboard. The clone is
deleted afterwards unless --keep is given. Nothing runs on the owner's Mac or touches their data.

Launch at Login needs real reboots, so the host restarts the clone between guest phases. Results go
to results.tsv and summary.md in the printed artifact folder; the exit status is 1 when a check
failed or a phase could not run.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "installed-acceptance"
SECTIONS = ("shortcuts", "translation", "settings")


def newest_dmg():
    """Returns the release DMG with the highest version in website/public/updates."""
    def version(path):
        return tuple(int(part) for part in re.findall(r"\d+", path.stem))
    dmgs = sorted((ROOT / "website" / "public" / "updates").glob("Volant-*.dmg"), key=version)
    if not dmgs:
        raise SystemExit("No release DMG in website/public/updates; pass --dmg.")
    return dmgs[-1]


parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
parser.add_argument("--dmg", type=Path, help="a notarized Volant DMG (default: newest in website/public/updates)")
parser.add_argument("--only", action="append", choices=SECTIONS, help="run only these sections (repeatable)")
parser.add_argument("--source-vm", default=os.environ.get("VOLANT_UI_VM", "volant-ui-xcode"))
parser.add_argument("--clone", default="volant-acceptance")
parser.add_argument("--keep", action="store_true", help="leave the clone running afterwards; delete it yourself")
parser.add_argument("--explore", action="store_true", help="install only and keep the clone, to inspect the UI by hand")
args = parser.parse_args()
sections = [] if args.explore else args.only or list(SECTIONS)
args.keep = args.keep or args.explore
dmg = (args.dmg or newest_dmg()).resolve()
if not dmg.is_file():
    raise SystemExit(f"{dmg} does not exist.")

output = Path(tempfile.mkdtemp(prefix="volant-acceptance-"))
print(f"Artifacts: {output}", flush=True)
print(f"DMG: {dmg}", flush=True)

vms = {vm["Name"]: vm for vm in json.loads(subprocess.check_output(["tart", "list", "--format", "json"]))}
if args.source_vm not in vms:
    raise SystemExit(f"Prepare {args.source_vm} using docs/ui-testing.md. Nothing was run on the host.")
if any(vm["Running"] for vm in vms.values() if vm["Source"] == "local"):
    raise SystemExit("A local Tart VM is running; wait for its work to finish rather than start a second VM.")
if args.clone in vms:
    raise SystemExit(f"{args.clone} already exists; delete it first (tart delete {args.clone}).")

shutil.copy(dmg, output / "Volant.dmg")
for path in (HERE / "guest").iterdir():
    shutil.copy(path, output / path.name)
key = output / "ssh-key"
subprocess.run(["ssh-keygen", "-t", "ed25519", "-N", "", "-q", "-f", str(key)], check=True)
guest_dir = "/Volumes/My Shared Files/artifacts"
log = (output / "tart.log").open("w")
state = {"process": None, "address": "(unknown)"}
failures = []


def agent_ready():
    """Reports whether the Tart guest agent answers yet."""
    try:
        return subprocess.run(["tart", "exec", args.clone, "/usr/bin/true"], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=15).returncode == 0
    except subprocess.TimeoutExpired:
        return False


def boot():
    """Starts the clone headlessly with the artifact folder shared and waits until SSH answers."""
    state["process"] = subprocess.Popen(
        ["tart", "run", args.clone, "--no-graphics", "--no-audio", "--no-clipboard", f"--dir=artifacts:{output}"],
        stdout=log, stderr=subprocess.STDOUT)
    deadline = time.time() + 300
    while not agent_ready():
        if state["process"].poll() is not None or time.time() > deadline:
            raise RuntimeError(f"Guest did not become reachable; see {output / 'tart.log'}")
        time.sleep(5)
    subprocess.run(["tart", "exec", args.clone, "/bin/bash", "-c",
                    f"mkdir -p ~/.ssh && grep -qf '{guest_dir}/ssh-key.pub' ~/.ssh/authorized_keys 2>/dev/null"
                    f" || cat '{guest_dir}/ssh-key.pub' >> ~/.ssh/authorized_keys"], check=True)
    state["address"] = subprocess.check_output(["tart", "ip", args.clone], text=True).strip()
    for _ in range(60):
        if ssh("true", quiet=True) == 0:
            return
        time.sleep(2)
    raise RuntimeError("SSH did not answer after boot")


def shutdown():
    """Stops the clone and waits for its tart process to exit."""
    subprocess.run(["tart", "stop", args.clone], check=False, timeout=180)
    if state["process"]:
        state["process"].wait(timeout=180)


def ssh(command, quiet=False, logname=None, timeout=1800):
    """Runs a command in the guest's admin account and returns its exit status."""
    base = ["ssh", "-i", str(key), "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=10", f"admin@{state['address']}", command]
    if quiet:
        return subprocess.run(base, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60).returncode
    with (output / f"{logname}.log").open("a") as handle:
        return subprocess.run(base, stdout=handle, stderr=subprocess.STDOUT, timeout=timeout).returncode


def phase(name, *extra):
    """Runs one guest phase script, logging to <name>.log; a nonzero exit counts as a failed phase."""
    print(f"phase {name}", flush=True)
    status = ssh(f"bash '{guest_dir}/{name}.sh' {' '.join(extra)}", logname=name)
    if status != 0:
        failures.append(f"phase {name} exited {status}")


def reboot():
    """Restarts the clone the way a person restarts a Mac: a clean shutdown, then a fresh boot."""
    print("reboot", flush=True)
    ssh("sudo shutdown -h now", quiet=True)
    try:
        state["process"].wait(timeout=180)
    except subprocess.TimeoutExpired:
        shutdown()
    boot()


subprocess.run(["tart", "clone", args.source_vm, args.clone], check=True)
try:
    boot()
    phase("install")
    if "shortcuts" in sections:
        phase("shortcuts")
        phase("restart-app", "shortcuts")
    if "translation" in sections:
        phase("translation")
    if "settings" in sections:
        phase("settings")
        phase("login-on")
        reboot()
        phase("login-check", "on")
        phase("login-off")
        reboot()
        phase("login-check", "off")
    phase("collect")
except Exception as error:
    failures.append(f"runner: {error}")
finally:
    if args.keep:
        print(f"Kept {args.clone} running: ssh -i {key} admin@{state['address']}. "
              f"Afterwards run: tart stop {args.clone} && tart delete {args.clone}", flush=True)
    else:
        shutdown()
        subprocess.run(["tart", "delete", args.clone], check=False)
    log.close()
    (output / "Volant.dmg").unlink(missing_ok=True)

rows = []
results = output / "results.tsv"
if results.exists():
    rows = [line.split("\t") for line in results.read_text().splitlines() if line.count("\t") >= 2]
failed = [row for row in rows if row[1] == "FAIL"]
lines = [f"# Installed acceptance: {dmg.name}", "", "| Section | Result | Check | Detail |", "|---|---|---|---|"]
lines += [f"| {row[0]} | {row[1]} | {row[2]} | {row[3] if len(row) > 3 else ''} |" for row in rows]
lines += [""] + [f"- {failure}" for failure in failures]
(output / "summary.md").write_text("\n".join(lines) + "\n")
for row in rows:
    print(f"{row[1]:5} {row[0]:12} {row[2]}" + (f"  ({row[3]})" if len(row) > 3 and row[3] else ""))
for failure in failures:
    print(f"ERROR {failure}")
print(f"{len(rows) - len(failed)} passed or noted, {len(failed)} failed. Summary: {output / 'summary.md'}")
raise SystemExit(1 if failed or failures else 0)
