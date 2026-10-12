#!/usr/bin/env python3
"""Debug builds ("Volant Dev") sign with Volant/VolantDev.entitlements, which must equal the generated
Volant/Volant.entitlements without the iCloud key-value entitlement, so dev and release builds differ
only in identity and settings sync."""
import plistlib
import sys
from pathlib import Path

release = plistlib.loads(Path("Volant/Volant.entitlements").read_bytes())
dev = plistlib.loads(Path("Volant/VolantDev.entitlements").read_bytes())
release.pop("com.apple.developer.ubiquity-kvstore-identifier", None)
if release != dev:
    keys = sorted(set(release) ^ set(dev) | {k for k in set(release) & set(dev) if release[k] != dev[k]})
    sys.exit("Volant/VolantDev.entitlements differs from Volant.entitlements (without iCloud) in: " + ", ".join(keys))
print("PASS: dev entitlements match release entitlements without iCloud")
