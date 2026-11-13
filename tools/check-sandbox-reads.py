#!/usr/bin/env python3
"""Debug and test builds can't show what the release sandbox may read: Xcode adds a read exception
for "/" to them. This signs a small probe with only the sandbox and file entitlements of
Volant/Volant.entitlements, runs it, and asks the sandbox which of the owner's folders it may read."""
import os
import plistlib
import pwd
import subprocess
import sys
import tempfile
from pathlib import Path

os.chdir(Path(__file__).resolve().parent.parent)
home = pwd.getpwuid(os.getuid()).pw_dir
# The sandbox answers only for paths that exist, so an account without ~/Applications can't be checked.
if not os.path.isdir(f"{home}/Applications"):
    print(f"SKIP: {home}/Applications does not exist")
    sys.exit(0)
release = plistlib.loads(Path("Volant/Volant.entitlements").read_bytes())
# iCloud and other restricted keys need a provisioning profile, and an ad-hoc signature can't carry them.
keep = {k: v for k, v in release.items() if k == "com.apple.security.app-sandbox" or ".files." in k}
with tempfile.TemporaryDirectory(prefix="volant-sandbox-reads.") as work:
    entitlements, info, probe = (Path(work) / name for name in ("probe.entitlements", "Info.plist", "probe"))
    entitlements.write_bytes(plistlib.dumps(keep))
    # A sandboxed command-line tool needs a bundle identifier in an embedded Info.plist, or it traps at launch.
    info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.mysticcoders.volant.sandbox-probe"}))
    subprocess.run(["clang", "-O1", "-o", probe, "tools/sandbox-reads/probe.c",
                    f"-Wl,-sectcreate,__TEXT,__info_plist,{info}"], check=True)
    subprocess.run(["codesign", "-s", "-", "-f", "-i", "com.mysticcoders.volant.sandbox-probe",
                    "--entitlements", entitlements, probe], check=True, capture_output=True)
    # The home folder is the control: if the probe may read it, the sandbox isn't limiting the probe at all.
    sys.exit(subprocess.run([probe, "allow", f"{home}/Applications/", "deny", f"{home}/"]).returncode)
