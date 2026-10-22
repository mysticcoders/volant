# Guest-side helpers for tools/installed-acceptance/run-vm.py. Sourced by each phase script, which
# runs over SSH inside a disposable Tart clone whose image grants UI scripting to sshd and
# osascript. Never run on the owner's Mac.
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
A='/Volumes/My Shared Files/artifacts'
W=/tmp/volant-acceptance
mkdir -p "$W" "$A/shots"
APP=/Applications/Volant.app
ID=com.mysticcoders.volant
CONTAINER="$HOME/Library/Containers/$ID/Data"
SUPPORT="$CONTAINER/Library/Application Support/Volant"
CONFIG="$SUPPORT/config.json"
SECTION=${SECTION:-general}

# Builds the small window-list, hotkey-holder and accessibility-tree tools; /tmp does not survive the reboots.
build_tools() {
  mkdir -p "$W/bin"
  for tool in windows hold-hotkey axtree; do
    [ -x "$W/bin/$tool" ] || xcrun swiftc -O -o "$W/bin/$tool" "$A/$tool.swift" 2>&1 | tail -5
  done
}
build_tools

step() { echo; echo "##### $*"; }

# Marks that a phase script reached its last line. A phase's exit status is only its last command's, so
# run-vm.py treats a phase that never calls this as stopped part way.
phase_finished() { basename "$0" .sh >> "$A/phases-finished"; }

# Records one check in results.tsv as PASS, FAIL or NOTE (evidence that is not a pass/fail).
record() {
  local status=$1 name=$2 detail=${3:-}
  detail=${detail//$'\t'/ }
  detail=${detail//$'\n'/ }
  printf '%s\t%s\t%s\t%s\n' "$SECTION" "$status" "$name" "$detail" >> "$A/results.tsv"
  echo "$status: $name${detail:+ ($detail)}"
}

# Records PASS when the two values match and FAIL otherwise.
expect_eq() {
  local name=$1 want=$2 got=$3
  if [ "$want" = "$got" ]; then record PASS "$name" "$got"; else record FAIL "$name" "wanted [$want], got [$got]"; fi
}

shot() { screencapture -x "$A/shots/$SECTION-$1.png" 2>/dev/null && echo "screenshot $SECTION-$1"; }
front() { lsappinfo info -only bundleid "$(lsappinfo front)" | tail -1 | sed 's/.*="\{0,1\}//; s/"$//'; }
running() { pgrep -x "$1" >/dev/null && echo yes || echo no; }

# Sends a key code with optional modifiers, e.g. `key 8 "{command down, option down}"`.
key() { osascript -e "tell application \"System Events\" to key code $1${2:+ using $2}" 2>&1; }
type_text() { osascript -e "tell application \"System Events\" to keystroke \"$1\"" 2>&1; }

# Runs AppleScript UI scripting against Volant's process.
ax() { osascript -e "tell application \"System Events\" to tell process \"Volant\" to $1" 2>&1; }

# Starts Volant in the console session through LaunchServices and waits for its config file.
launch_volant() {
  open -a "$APP" 2>/dev/null || sudo launchctl asuser "$(id -u)" /usr/bin/open -a "$APP"
  for _ in $(seq 1 40); do
    pgrep -x Volant >/dev/null && [ -f "$CONFIG" ] && break
    sleep 0.5
  done
  sleep 3
}

quit_volant() {
  osascript -e 'quit app id "com.mysticcoders.volant"' >/dev/null 2>&1
  for _ in $(seq 1 20); do pgrep -x Volant >/dev/null || return 0; sleep 0.5; done
  pkill -x Volant; sleep 1
}

# Prints a value from config.json by a jq-style path, read by plutil so no extra tools are needed.
config_get() { /usr/bin/plutil -extract "$1" raw -o - "$CONFIG" 2>/dev/null; }
config_json() { /usr/bin/plutil -extract "$1" json -o - "$CONFIG" 2>/dev/null; }

# Waits until the frontmost app is the given bundle ID or the timeout passes; prints the final one.
wait_front() {
  local want=$1 limit=${2:-10}
  for _ in $(seq 1 $((limit * 2))); do [ "$(front)" = "$want" ] && break; sleep 0.5; done
  front
}

# Quits a test app and waits for it to exit.
quit_app() {
  osascript -e "quit app id \"$1\"" >/dev/null 2>&1
  for _ in $(seq 1 20); do lsappinfo info -only pid "$1" 2>/dev/null | grep -q '=' || return 0; sleep 0.5; done
}

# Lists an app's on-screen windows from the window server (not accessibility) as
# "layer widthxheight title", so visibility checks hold for non-activating panels.
onscreen() { "$W/bin/windows" "$1"; }

# Answers the macOS 15 "bypass the private window picker" prompt that the first screenshot
# from SSH raises, so later key events reach the app under test. Disposable guest only.
allow_capture() {
  screencapture -x "$W/probe.png" 2>/dev/null
  sleep 2
  osascript -e 'tell application "System Events" to tell process "UserNotificationCenter" to click button "Allow" of window 1' >/dev/null 2>&1
  sleep 1
}

# Describes the focused element of the frontmost app.
focused() {
  osascript -e 'tell application "System Events" to tell (first process whose frontmost is true) to get {role, description, name, value} of (value of attribute "AXFocusedUIElement")' 2>&1
}

# Clicks at screen coordinates, for controls accessibility does not expose on their own.
click_at() { osascript -e "tell application \"System Events\" to click at {$1, $2}" >/dev/null 2>&1; }

# Clicks the center of an element found by ax.js, offset horizontally by $4 points if given.
click_element() {
  local x y w h
  read -r x y w h <<< "$(osascript -l JavaScript "$A/ax.js" Volant frame "$1" "$2" 2>/dev/null)"
  [ -n "$h" ] || return 1
  click_at $((x + w / 2 + ${3:-0})) $((y + h / 2))
}

AX() { osascript -l JavaScript "$A/ax.js" "$@" 2>&1; }

# Clicks an item of Volant's status bar menu by name.
status_menu() {
  osascript -e 'tell application "System Events" to tell process "Volant"' \
    -e 'click menu bar item 1 of menu bar 2' -e 'delay 0.8' \
    -e "click menu item \"$1\" of menu 1 of menu bar item 1 of menu bar 2" -e 'end tell' >/dev/null 2>&1
}

# Opens Settings from the status bar menu on the given section and waits for its window.
open_settings() {
  status_menu "Settings…"
  for _ in $(seq 1 20); do [ "$(onscreen Volant | grep -c 'Volant Settings')" -ge 1 ] && break; sleep 0.5; done
  sleep 1
  [ -n "${1:-}" ] && { AX Volant select "Volant Settings" "$1" >/dev/null; sleep 1.5; }
}

# Prints Volant's background-task (login item) disposition, or "absent".
login_item() {
  local entry
  entry=$(echo admin | sudo -S sfltool dumpbtm 2>/dev/null | grep -B1 " Identifier: 2.$ID$" | grep -m1 Disposition)
  [ -n "$entry" ] && echo "$entry" | sed 's/.*Disposition: //' || echo absent
}

# Blocks all network traffic except SSH (the test's own connection) with pf, or restores it.
offline() {
  printf 'set skip on lo0\npass in quick proto tcp to any port 22 flags any keep state\npass out quick proto tcp from any port 22 flags any keep state\nblock drop all\n' > "$W/pf.conf"
  sudo pfctl -q -f "$W/pf.conf" 2>/dev/null
  sudo pfctl -q -e 2>/dev/null
}
online() { sudo pfctl -q -d 2>/dev/null; }
network_reachable() { curl -s -m 5 -o /dev/null https://www.apple.com && echo yes || echo no; }

# Clears loginwindow's list of apps to reopen, so after a reboot only the login item can start
# Volant. Its snapshot lags behind quits, so a fast reboot would otherwise resume Volant.
forget_relaunch() {
  defaults -currentHost delete com.apple.loginwindow TALAppsToRelaunchAtLogin >/dev/null 2>&1
  defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool false
  sleep 2
}

# Volant's focused element as "role | title | description | frame", read through AXUIElement
# (guest/axtree.swift) rather than System Events, which resolves same-named elements to the first.
ax_focused() { "$W/bin/axtree" "$ID" focused "${1:-Volant Settings}" | cut -d'|' -f1,3,4; }
