#!/bin/bash
# Diagnose Sparkle's update check in a throwaway VM against the live feed.
# Usage: spike-sparkle.sh <path-to-older-Volant.dmg> [--keep]
#
# docs/sparkle-update-defect.md reports the feed download transferring 0 bytes and timing out.
# Its stated cause does not survive inspection of the shipped bundle, so this reproduces the
# failure and captures Sparkle's own logging rather than reasoning about the packaging.
set -euo pipefail

BASE_VM="${BASE_VM:-volant-sequoia-15}"
VM="volant-sparkle-$(date +%Y%m%d-%H%M%S)"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)
CONTAINER='~/Library/Containers/com.mysticcoders.volant'
PREFS="$CONTAINER/Data/Library/Preferences/com.mysticcoders.volant.plist"

DMG="${1:?Usage: spike-sparkle.sh <path-to-older-Volant.dmg> [--keep]}"
KEEP=0
for arg in "${@:2}"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
DMG_DIR="$(cd "$(dirname "$DMG")" && pwd)"
DMG_NAME="$(basename "$DMG")"

start_vm() {
  tart clone "$BASE_VM" "$VM"
  tart set "$VM" --cpu 4 --memory 8192
  tart run "$VM" --no-clipboard --dir="dmg:$DMG_DIR:ro" >"/tmp/$VM.log" 2>&1 &
  VM_IP="$(tart ip "$VM" --wait 240)"
  for _ in $(seq 1 45); do nc -z -G 2 "$VM_IP" 22 2>/dev/null && break; sleep 2; done
  echo "VM $VM is up at $VM_IP"
}

guest() { ssh "${SSH_OPTS[@]}" "admin@$VM_IP" "$@"; }

cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    echo "Kept $VM at $VM_IP. ssh -i $SSH_KEY admin@$VM_IP ; tart stop $VM; tart delete $VM"
    return
  fi
  tart stop "$VM" >/dev/null 2>&1 || true
  tart delete "$VM" >/dev/null 2>&1 || true
  echo "Deleted $VM"
}
trap cleanup EXIT

start_vm

echo "=== install ==="
guest "set -e
  pkill -x Volant 2>/dev/null || true
  hdiutil attach '/Volumes/My Shared Files/dmg/$DMG_NAME' -nobrowse -mountpoint /tmp/volant-dmg >/dev/null
  rm -rf /Applications/Volant.app
  ditto /tmp/volant-dmg/Volant.app /Applications/Volant.app
  hdiutil detach /tmp/volant-dmg >/dev/null
  xattr -c -r /Applications/Volant.app 2>/dev/null || true
  echo \"gatekeeper: \$(spctl -a -vv /Applications/Volant.app 2>&1 | tr '\n' ' ')\"
  echo \"version: \$(defaults read /Applications/Volant.app/Contents/Info.plist CFBundleShortVersionString) build \$(defaults read /Applications/Volant.app/Contents/Info.plist CFBundleVersion)\""

echo "=== baseline network reachability from the guest ==="
guest "curl -sS -o /dev/null -w 'curl appcast: HTTP %{http_code}, %{size_download} bytes\n' https://usevolant.com/updates/appcast.xml || true"

echo "=== first launch to create the container ==="
guest "echo admin | sudo -S launchctl asuser \$(id -u) /usr/bin/open -a /Applications/Volant.app 2>/dev/null || true
  for i in \$(seq 1 40); do [ -d $CONTAINER ] && break; sleep 1; done
  echo \"container: \$([ -d $CONTAINER ] && echo created || echo missing)\"
  sleep 3
  pkill -x Volant 2>/dev/null || true
  sleep 2"

echo "=== force a scheduled check on next launch ==="
# Sparkle only checks when the interval has elapsed, so the last check is backdated.
guest "defaults write $PREFS SUEnableAutomaticChecks -bool true
  defaults write $PREFS SUScheduledCheckInterval -int 3600
  defaults write $PREFS SULastCheckTime -date '2020-01-01T00:00:00Z'
  defaults write $PREFS SUHasLaunchedBefore -bool true
  defaults read $PREFS 2>/dev/null | grep -i -E 'SU[A-Za-z]+' || true"

echo "=== relaunch and wait for the check ==="
guest "echo admin | sudo -S launchctl asuser \$(id -u) /usr/bin/open -a /Applications/Volant.app 2>/dev/null || true
  sleep 90
  echo \"process: \$(pgrep -x Volant >/dev/null && echo running || echo gone)\"
  echo \"SULastCheckTime now: \$(defaults read $PREFS SULastCheckTime 2>/dev/null || echo unset)\""

echo "=== Sparkle and helper logs ==="
guest "echo admin | sudo -S log show --last 6m --info --debug --predicate 'subsystem == \"org.sparkle-project.Sparkle\"' 2>/dev/null | tail -40"
echo "--- appcast / downloader traffic ---"
guest "echo admin | sudo -S log show --last 6m --info --debug --predicate 'process == \"Downloader\" OR process == \"Volant\"' 2>/dev/null | grep -i -E 'appcast|download|update|sparkle|error|timed out|cancel|bytes' | head -40"

echo "=== sandbox denials ==="
guest "echo admin | sudo -S log show --last 6m --info --debug --predicate 'eventMessage CONTAINS \"deny\" OR eventMessage CONTAINS \"Sandbox\" OR eventMessage CONTAINS \"spk\"' 2>/dev/null | grep -i -E 'volant|sparkle|downloader|spk' | head -30"

echo "=== did an update window appear? ==="
guest "lsappinfo list 2>/dev/null | grep -i -E 'volant|software update' | head -10 || true"

echo "=== running helper processes ==="
guest "ps ax | grep -i -E 'Downloader|Installer|Sparkle' | grep -v grep || echo 'no Sparkle helpers running'"

if [ "$KEEP" -eq 1 ]; then trap - EXIT; cleanup; fi
