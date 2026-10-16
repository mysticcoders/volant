# App shortcut acceptance (#3): record, deliver, hide, change, conflict, remove, keyboard-only edit
# and reopen, all in the installed app without restarting it. Delivery is judged by the frontmost
# app and TextEdit's on-screen windows, never by Volant's own state.
SECTION=shortcuts
source "/Volumes/My Shared Files/artifacts/lib.sh"
TE=com.apple.TextEdit
S="Volant Settings"
CMD_OPT="{command down, option down}"

finder_front() { osascript -e 'tell application "Finder" to activate' >/dev/null; sleep 1; }
textedit_hotkey() { config_get appHotKeys.0.hotKey; }

# Closes Volant's Notes window if a test key opened it.
close_notes() {
  [ "$(onscreen Volant | grep -c ' Notes$')" -ge 1 ] || return 0
  AX Volant press Notes "close button" >/dev/null
  sleep 1
}

# Clicks TextEdit's recorder in the App Shortcuts list and presses a combination.
record_textedit() {
  AX Volant press "$S" "prefix=TextEdit shortcut:" >/dev/null
  sleep 0.8
  key "$1" "$2" >/dev/null
  sleep 0.6
}

# From Finder, presses a combination and reports which app ends up in front.
press_from_finder() {
  finder_front
  key "$1" "$2" >/dev/null
  if [ "${3:-}" = expect-textedit ]; then wait_front $TE 8; else sleep 2; front; fi
}

launch_volant
allow_capture
key 53; sleep 1

step "launcher hotkey"
key 49 "{option down}"; sleep 1.5
launcher=$(onscreen Volant | grep -c '^3 ')
expect_eq "Option-Space shows the launcher" 1 "$launcher"
key 49 "{option down}"; sleep 1.5
expect_eq "Option-Space again hides it" 0 "$(onscreen Volant | grep -c '^3 ')"

step "open Settings from the launcher"
finder_front
key 49 "{option down}"; sleep 1; type_text "volant settings"; sleep 1.5; key 36; sleep 2.5
expect_eq "Settings opens from the launcher" 1 "$(onscreen Volant | grep -c "$S")"
active=$(front)
if [ "$active" = "$ID" ]; then
  record PASS "Settings is the active window when opened from the launcher"
else
  record FAIL "Settings is the active window when opened from the launcher" "frontmost app is $active, so typing goes there"
  osascript -e "tell application id \"$ID\" to activate"; sleep 1
fi
AX Volant select "$S" "App Shortcuts" >/dev/null; sleep 1.5
AX Volant set "$S" "role=AXTextField" TextEdit >/dev/null
for _ in $(seq 1 30); do [ "$(AX Volant count "$S" "prefix=TextEdit shortcut:")" -ge 1 ] && break; sleep 2; done
shot app-shortcuts

step "record a shortcut"
record_textedit 17 "$CMD_OPT"
saved=$(AX Volant count "$S" "TextEdit shortcut saved")
expect_eq "recording writes config.json" "cmd+option+t" "$(textedit_hotkey)"
expect_eq "the row says Saved" 1 "$saved"

step "deliver, hide and show"
quit_app $TE
expect_eq "the shortcut launches TextEdit" $TE "$(press_from_finder 17 "$CMD_OPT" expect-textedit)"
sleep 1
key 17 "$CMD_OPT" >/dev/null; sleep 2
expect_eq "pressing it while TextEdit is in front hides it" false \
  "$(osascript -e 'tell application "System Events" to get visible of process "TextEdit"')"
expect_eq "pressing it again shows TextEdit" $TE "$(press_from_finder 17 "$CMD_OPT" expect-textedit)"

step "change the shortcut without restarting"
osascript -e "tell application id \"$ID\" to activate"; sleep 1
record_textedit 16 "$CMD_OPT"
expect_eq "the changed shortcut is saved" "cmd+option+y" "$(textedit_hotkey)"
quit_app $TE
expect_eq "the new combination opens TextEdit" $TE "$(press_from_finder 16 "$CMD_OPT" expect-textedit)"
quit_app $TE
expect_eq "the old combination no longer does" com.apple.finder "$(press_from_finder 17 "$CMD_OPT")"

step "conflict with another Volant shortcut"
osascript -e "tell application id \"$ID\" to activate"; sleep 1
record_textedit 45 "{option down}"
shot conflict-volant
if [ "$(AX Volant count "$S" "That shortcut is already assigned in Volant.")" -ge 1 ]; then
  record PASS "Option-N (Open Notes) is refused for TextEdit with a message"
else
  detail="no conflict message"
  [ "$(onscreen Volant | grep -c ' Notes$')" -ge 1 ] && detail="the key opened Volant's Notes window instead of reaching the recorder"
  record FAIL "Option-N (Open Notes) is refused for TextEdit with a message" "$detail"
fi
expect_eq "the earlier binding is kept after that attempt" "cmd+option+y" "$(textedit_hotkey)"
close_notes
osascript -e 'tell application "Finder" to activate' >/dev/null; sleep 1
key 45 "{option down}"; sleep 1.5
expect_eq "Option-N opens Notes again once recording ends" 1 "$(onscreen Volant | grep -c ' Notes$')"
close_notes

step "conflict with another app's shortcut"
"$W/bin/hold-hotkey" 38 2304 > "$W/hold.log" 2>&1 &
holder=$!
sleep 2
record NOTE "another process holds Command-Option-J" "$(head -1 "$W/hold.log")"
osascript -e "tell application id \"$ID\" to activate"; sleep 1
record_textedit 38 "$CMD_OPT"
shot conflict-other-app
after=$(textedit_hotkey)
expect_eq "the old binding is kept when another app holds the combination" "cmd+option+y" "$after"
if [ "$(AX Volant count "$S" "prefix=No key arrived")" -ge 1 ]; then
  record PASS "the recorder says no key arrived when another app takes the combination" \
    "the other app received $(grep -c pressed "$W/hold.log") press(es)"
else
  record FAIL "the recorder says no key arrived when another app takes the combination" \
    "no hint; the other app received $(grep -c pressed "$W/hold.log") press(es)"
fi
key 53; sleep 0.5
if [ "$after" != "cmd+option+y" ]; then record_textedit 16 "$CMD_OPT"; fi
kill $holder 2>/dev/null

step "remove the shortcut"
osascript -e "tell application id \"$ID\" to activate"; sleep 1
AX Volant focus "$S" "prefix=TextEdit shortcut:" >/dev/null; sleep 0.5
key 51 >/dev/null; sleep 0.6
removed=$(AX Volant count "$S" "TextEdit shortcut removed")
expect_eq "Delete removes the binding from config.json" "[]" "$(config_json appHotKeys)"
expect_eq "the row says Removed" 1 "$removed"
quit_app $TE
expect_eq "the removed combination does nothing" com.apple.finder "$(press_from_finder 16 "$CMD_OPT")"
key 53; sleep 1

step "edit with the keyboard only (launcher, Actions, editor)"
finder_front
key 49 "{option down}"; sleep 1; type_text TextEdit; sleep 1.5
key 40 "{command down}"; sleep 1; type_text "Edit Shortcut"; sleep 1; key 36; sleep 2
expect_eq "Command-K, Edit Shortcut & Alias, Return opens the editor" 1 "$(AX Volant count "$S" role=AXSheet)"
expect_eq "the editor focuses the recorder" "TextEdit shortcut:" "$(focused | cut -d, -f2 | sed 's/^ //' | cut -d' ' -f1-2)"
key 49; sleep 0.7; key 32 "$CMD_OPT"; sleep 0.7
expect_eq "Space then a combination records it" "cmd+option+u" "$(textedit_hotkey)"
for _ in 1 2 3; do key 48; sleep 0.3; done
key 49; sleep 1
expect_eq "Tab to Done and Space closes the editor" 0 "$(AX Volant count "$S" role=AXSheet)"
shot keyboard-edit
key 53; sleep 1
quit_app $TE
expect_eq "the keyboard-recorded shortcut opens TextEdit" $TE "$(press_from_finder 32 "$CMD_OPT" expect-textedit)"

step "reopen an app whose last window was closed"
sleep 1
key 13 "{command down}"; sleep 1.5
expect_eq "TextEdit is running with no windows" "yes:0" "$(running TextEdit):$(onscreen TextEdit | grep -c '^0 ')"
press_from_finder 32 "$CMD_OPT" expect-textedit >/dev/null
sleep 1
windows=$(onscreen TextEdit | grep -c '^0 ')
if [ "$windows" -ge 1 ]; then record PASS "the shortcut reopens a window" "$windows window(s)"; else record FAIL "the shortcut reopens a window" "TextEdit has no window"; fi
shot reopen
cp "$CONFIG" "$W/config-shortcuts.json"
phase_finished
