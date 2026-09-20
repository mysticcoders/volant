#!/bin/bash
# Throwaway macOS VM for testing a Volant DMG with Tart.
# Usage: volant-vm-test.sh <path-to-Volant.dmg> [--gatekeeper-prompt] [--keep]
#
# Default install mimics a Finder drag from the DMG: the quarantine flag is cleared, so macOS
# neither shows the download warning nor translocates the app to a read-only random path.
# --gatekeeper-prompt keeps the flag to exercise the "downloaded from the Internet" dialog; that
# dialog is modal, so the app will not finish launching until someone clicks Open in the VM window.
set -euo pipefail

BASE_VM="${BASE_VM:-volant-sequoia-15}"
VM="volant-test-$(date +%Y%m%d-%H%M%S)"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)
CONTAINER='~/Library/Containers/com.mysticcoders.volant'

DMG="${1:?Usage: volant-vm-test.sh <path-to-Volant.dmg> [--gatekeeper-prompt] [--keep]}"
GATEKEEPER_PROMPT=0
KEEP=0
for arg in "${@:2}"; do
  case "$arg" in
    --gatekeeper-prompt) GATEKEEPER_PROMPT=1 ;;
    --keep) KEEP=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
DMG_DIR="$(cd "$(dirname "$DMG")" && pwd)"
DMG_NAME="$(basename "$DMG")"

# Clones the clean baseline, sizes it for UI testing, and boots it with the DMG folder shared read-only and no clipboard sharing.
start_vm() {
  tart clone "$BASE_VM" "$VM"
  tart set "$VM" --cpu 4 --memory 8192
  tart run "$VM" --no-clipboard --dir="dmg:$DMG_DIR:ro" >"/tmp/$VM.log" 2>&1 &
  VM_IP="$(tart ip "$VM" --wait 240)"
  for _ in $(seq 1 45); do nc -z -G 2 "$VM_IP" 22 2>/dev/null && break; sleep 2; done
  echo "VM $VM is up at $VM_IP"
}

# Uses the host's key when the baseline already carries it, and otherwise installs it with the image's default admin/admin login.
ensure_ssh_key() {
  if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "admin@$VM_IP" true 2>/dev/null; then
    return
  fi
  local pub
  pub="$(cat "$SSH_KEY.pub")"
  expect <<EOF >/dev/null
set timeout 90
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR admin@$VM_IP "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
expect {
  "assword:" { send "admin\r"; exp_continue }
  timeout { exit 1 }
}
expect eof
EOF
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes "admin@$VM_IP" true
}

# Runs a command inside the guest over SSH.
guest() {
  ssh "${SSH_OPTS[@]}" "admin@$VM_IP" "$@"
}

# Refuses to continue unless the guest enforces Gatekeeper, since install results are meaningless without it.
require_gatekeeper() {
  local status
  status="$(guest 'spctl --status 2>&1' || true)"
  if [[ "$status" != *"assessments enabled"* ]]; then
    echo "Gatekeeper is off in the guest ($status). Enable it in $BASE_VM first: sudo spctl --master-enable" >&2
    exit 1
  fi
}

# Copies Volant out of the shared DMG, reports Gatekeeper's verdict, and leaves the quarantine flag only in prompt mode.
install_volant() {
  guest "set -e
    killall CoreServicesUIAgent 2>/dev/null || true
    pkill -x Volant 2>/dev/null || true
    hdiutil attach '/Volumes/My Shared Files/dmg/$DMG_NAME' -nobrowse -mountpoint /tmp/volant-dmg >/dev/null
    rm -rf /Applications/Volant.app
    ditto /tmp/volant-dmg/Volant.app /Applications/Volant.app
    hdiutil detach /tmp/volant-dmg >/dev/null
    if [ $GATEKEEPER_PROMPT -eq 1 ]; then
      xattr -w com.apple.quarantine \"0081;\$(printf %x \$(date +%s));Safari;\" /Applications/Volant.app
    else
      xattr -c -r /Applications/Volant.app 2>/dev/null || true
    fi
    echo \"gatekeeper: \$(spctl -a -vv /Applications/Volant.app 2>&1 | tr '\n' ' ')\"
    echo \"version: \$(defaults read /Applications/Volant.app/Contents/Info.plist CFBundleShortVersionString)\"
    echo \"bundle id: \$(defaults read /Applications/Volant.app/Contents/Info.plist CFBundleIdentifier)\""
}

# Launches Volant and waits for real startup: the sandbox container and its config file, not merely a live process.
# macOS refuses plain `open` from an SSH session ("Domain does not support specified action"), so the launch is
# handed to the console session through launchctl, which needs root to switch audit sessions.
launch_volant() {
  guest "echo admin | sudo -S launchctl asuser \$(id -u) /usr/bin/open -a /Applications/Volant.app 2>/dev/null || true
    for i in \$(seq 1 30); do [ -f $CONTAINER/Data/Library/Application\\ Support/Vey/config.json ] && break; sleep 1; done
    echo \"process: \$(ps -o pid,command -p \$(pgrep -x Volant) 2>/dev/null | tail -1 | cut -c1-80)\"
    echo \"container: \$([ -d $CONTAINER ] && echo created || echo missing)\"
    echo \"config: \$(find $CONTAINER -name config.json 2>/dev/null | head -1)\"
    echo \"blocking dialog: \$(pgrep -q CoreServicesUIAgent && echo yes || echo no)\""
}

# Reports whether startup actually completed, so a process parked behind a modal dialog is not treated as success.
verify_started() {
  local out
  out="$(launch_volant)"
  echo "$out"
  if [ "$GATEKEEPER_PROMPT" -eq 1 ]; then
    echo "Gatekeeper prompt mode: click Open in the VM window to continue the launch."
    return
  fi
  if [[ "$out" != *"container: created"* || "$out" != *config.json* ]]; then
    echo "Volant did not complete startup (no container or config written)." >&2
    exit 1
  fi
}

# Stops the VM and deletes it unless --keep was given.
cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    echo "Kept $VM at $VM_IP. Connect with: ssh -i $SSH_KEY admin@$VM_IP"
    echo "Delete later with: tart stop $VM; tart delete $VM"
    return
  fi
  tart stop "$VM" >/dev/null 2>&1 || true
  tart delete "$VM" >/dev/null 2>&1 || true
  echo "Deleted $VM"
}

trap cleanup EXIT
start_vm
ensure_ssh_key
require_gatekeeper
install_volant
verify_started
if [ "$KEEP" -eq 1 ]; then trap - EXIT; cleanup; fi
