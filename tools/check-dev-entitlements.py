#!/usr/bin/env python3
"""Debug builds ("Volant Dev") sign with Volant/VolantDev.entitlements, which must equal the generated
Volant/Volant.entitlements without the iCloud entitlements (key-value store for settings, Documents
container for notes), so dev and release builds differ only in identity and iCloud sync. Both files must
also grant read access to the owner's ~/Applications, so the app index can find apps there."""
import plistlib
import sys
from pathlib import Path

release = plistlib.loads(Path("Volant/Volant.entitlements").read_bytes())
dev = plistlib.loads(Path("Volant/VolantDev.entitlements").read_bytes())
for key in ("com.apple.developer.ubiquity-kvstore-identifier", "com.apple.developer.icloud-container-identifiers",
            "com.apple.developer.icloud-services", "com.apple.developer.ubiquity-container-identifiers"):
    release.pop(key, None)
if release != dev:
    keys = sorted(set(release) ^ set(dev) | {k for k in set(release) & set(dev) if release[k] != dev[k]})
    sys.exit("Volant/VolantDev.entitlements differs from Volant.entitlements (without iCloud) in: " + ", ".join(keys))
# The app index asks Spotlight for apps in the owner's ~/Applications, and inside the sandbox Spotlight
# returns only files the app may read. Both builds therefore need read access to that one folder.
home_apps = "com.apple.security.temporary-exception.files.home-relative-path.read-only"
for name, entitlements in (("Volant.entitlements", release), ("VolantDev.entitlements", dev)):
    if "/Applications/" not in entitlements.get(home_apps, []):
        sys.exit(f"Volant/{name} lacks read access to ~/Applications ({home_apps})")
print("PASS: dev entitlements match release entitlements without iCloud")
