#!/bin/bash
# Archive Volant for iPhone with the App Store profiles, check the signed result, and export an
# .ipa for TestFlight:  Scripts/testflight.sh
# The build number is the current time (yyyymmddHHMM) unless VOLANT_BUILD is set; the version is
# MARKETING_VERSION in project.yml. With ASC_KEY_ID set (the key at
# ~/.appstoreconnect/private_keys/AuthKey_<id>.p8) the .ipa is uploaded; the issuer comes from
# ASC_ISSUER_ID or ~/.appstoreconnect/issuer_id, as for the Mac release. Without a key, open the
# .ipa in Transporter. Profile names default to the team's "Volant mobile production profile",
# "Volant mobile widget production profile" and "Volant mobile share production profile";
# override with VOLANT_APP_PROFILE, VOLANT_WIDGETS_PROFILE, VOLANT_SHARE_PROFILE.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${VOLANT_BUILD:-$(date +%Y%m%d%H%M)}"
OUT="build/testflight/$BUILD"
APP_PROFILE="${VOLANT_APP_PROFILE:-Volant mobile production profile}"
WIDGETS_PROFILE="${VOLANT_WIDGETS_PROFILE:-Volant mobile widget production profile}"
SHARE_PROFILE="${VOLANT_SHARE_PROFILE:-Volant mobile share production profile}"
ASC_DIR="${VOLANT_ASC_DIR:-$HOME/.appstoreconnect}"
if [[ -z "${ASC_ISSUER_ID:-}" && -s "$ASC_DIR/issuer_id" ]]; then ASC_ISSUER_ID="$(tr -d '[:space:]' < "$ASC_DIR/issuer_id")"; fi
mkdir -p "$OUT"
echo "Volant for iPhone build $BUILD -> ios/$OUT"
xcodegen generate --quiet
if ! xcodebuild -project VolantMobile.xcodeproj -scheme VolantMobile -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath build/release -archivePath "$OUT/Volant.xcarchive" \
    CURRENT_PROJECT_VERSION="$BUILD" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" \
    VOLANT_APP_PROFILE="$APP_PROFILE" VOLANT_WIDGETS_PROFILE="$WIDGETS_PROFILE" VOLANT_SHARE_PROFILE="$SHARE_PROFILE" \
    archive > "$OUT/archive.log" 2>&1; then
  grep -E "error:" "$OUT/archive.log" | sort -u
  echo "Archive failed; full log in ios/$OUT/archive.log" >&2
  exit 1
fi
sed -e "s/VOLANT_APP_PROFILE/$APP_PROFILE/" -e "s/VOLANT_WIDGETS_PROFILE/$WIDGETS_PROFILE/" \
    -e "s/VOLANT_SHARE_PROFILE/$SHARE_PROFILE/" ExportOptions-AppStore.plist > "$OUT/ExportOptions.plist"
# Export with only system tools on PATH: Xcode's /usr/bin/rsync starts its receiver from PATH, and a
# Homebrew rsync 3.x there rejects the --extended-attributes option, failing the copy.
if ! env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$OUT/Volant.xcarchive" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" > "$OUT/export.log" 2>&1; then
  grep -E "error" "$OUT/export.log" | sort -u
  echo "Export failed; full log in ios/$OUT/export.log" >&2
  exit 1
fi
IPA="$OUT/export/Volant.ipa"
mkdir -p "$OUT/check"
ditto -x -k "$IPA" "$OUT/check"
python3 - "$OUT/check/Payload/Volant.app" <<'PY'
import plistlib, subprocess, sys
app = sys.argv[1]
def entitlements(path):
    out = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", path], capture_output=True).stdout
    return plistlib.loads(out) if out else {}
group, container = "group.com.mysticcoders.volant", "iCloud.com.mysticcoders.volant"
for path, wants_icloud in [(app, True), (f"{app}/PlugIns/VolantWidgets.appex", False), (f"{app}/PlugIns/VolantShare.appex", True)]:
    ent = entitlements(path)
    assert not ent.get("get-task-allow"), f"{path} is a debug signature"
    assert ent.get("com.apple.security.application-groups") == [group], f"{path} lacks {group}"
    if wants_icloud:
        assert ent.get("com.apple.developer.icloud-container-identifiers") == [container], f"{path} lacks {container}"
        assert ent.get("com.apple.developer.icloud-container-environment") == "Production", f"{path} is not on the Production iCloud environment"
print("Signed entitlements check passed")
import json, re
actions = json.load(open(f"{app}/Metadata.appintents/extract.actionsdata"))["actions"]
named = [f"{name}: {meta['descriptionMetadata']['descriptionText']['key']}" for name, meta in actions.items()
         if re.search(r"\b(mac|macos|iphone|ipad)\b", (meta.get("descriptionMetadata") or {}).get("descriptionText", {}).get("key", ""), re.I)]
assert not named, "App Intent descriptions may not name a platform (ITMS-90626): " + "; ".join(named)
print("App Intent descriptions check passed")
PY
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -f "$ASC_DIR/private_keys/AuthKey_$ASC_KEY_ID.p8" ]]; then
  xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "Uploaded build $BUILD; it appears in TestFlight after Apple finishes processing."
else
  echo "Exported ios/$IPA. Upload it with Transporter, or set ASC_KEY_ID to upload from here."
fi
