#!/bin/bash
# Debug and test builds can't show what the release sandbox may read: Xcode adds a read exception
# for "/" to them. This signs a small probe with only the sandbox and file entitlements of
# Volant/Volant.entitlements, runs it, and asks the sandbox which of the owner's folders it may read.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/volant-sandbox-reads.XXXXXX)
trap 'rm -rf "$work"' EXIT
# iCloud and other restricted keys need a provisioning profile, and an ad-hoc signature can't carry them.
python3 - Volant/Volant.entitlements "$work/probe.entitlements" <<'PY'
import plistlib, sys
release = plistlib.loads(open(sys.argv[1], "rb").read())
keep = {k: v for k, v in release.items() if k == "com.apple.security.app-sandbox" or ".files." in k}
open(sys.argv[2], "wb").write(plistlib.dumps(keep))
PY
# A sandboxed command-line tool needs a bundle identifier in an embedded Info.plist, or it traps at launch.
plutil -create xml1 "$work/Info.plist"
plutil -insert CFBundleIdentifier -string com.mysticcoders.volant.sandbox-probe "$work/Info.plist"
clang -O1 -o "$work/probe" tools/sandbox-reads/probe.c -Wl,-sectcreate,__TEXT,__info_plist,"$work/Info.plist"
codesign -s - -f -i com.mysticcoders.volant.sandbox-probe --entitlements "$work/probe.entitlements" "$work/probe" 2>/dev/null
home=$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')
# The sandbox answers only for paths that exist, so an account without ~/Applications can't be checked.
if [[ ! -d "$home/Applications" ]]; then
    echo "SKIP: $home/Applications does not exist"
    exit 0
fi
# The home folder is the control: if the probe may read it, the sandbox isn't limiting the probe at all.
"$work/probe" allow "$home/Applications/" deny "$home/"
