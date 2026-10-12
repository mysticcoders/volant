# Settings and data acceptance (#2): the status menu's version, keyboard navigation in light and
# dark appearance, export, import, Reload Configuration and Reveal in Finder. Results are read
# from config.json, the file system, the frontmost app and the window server.
SECTION=settings
source "/Volumes/My Shared Files/artifacts/lib.sh"
S="Volant Settings"
DOCS="$HOME/Documents/acceptance"
TE=com.apple.TextEdit
rm -rf "$DOCS"; mkdir -p "$DOCS"

pgrep -x Volant >/dev/null || launch_volant
allow_capture
key 53; sleep 1

# Chooses a folder in an open or save panel by typing its path into Go to Folder.
choose_folder() {
  key 5 "{command down, shift down}"; sleep 1.5
  type_text "$1"; sleep 0.8
  key 36; sleep 2
}

# Selects the row after the current one with the Down arrow and reports the selected section.
selected_section() {
  osascript -l JavaScript -e '
    const rows = Application("System Events").processes.byName("Volant").windows.byName("Volant Settings").entireContents()
      .filter(e => { try { return e.role() === "AXRow" && e.selected(); } catch (x) { return false; } });
    rows.length ? rows[0].entireContents().map(e => { try { return e.value(); } catch (x) { return ""; } }).filter(Boolean).join("") : "none"' 2>&1
}

step "status menu"
osascript -e 'tell application "System Events" to tell process "Volant"' -e 'click menu bar item 1 of menu bar 2' -e 'delay 0.8' \
  -e 'set out to {}' -e 'repeat with m in menu items of menu 1 of menu bar item 1 of menu bar 2' \
  -e 'set end of out to (name of m as text) & "=" & (enabled of m as text)' -e 'end repeat' -e 'return out' -e 'end tell' > "$W/menu.txt" 2>&1
key 53; sleep 0.5
expect_eq "the status menu shows the version and build, disabled" "Volant $(cat "$W/version")=false" \
  "$(tr ',' '\n' < "$W/menu.txt" | sed 's/^ //' | grep '^Volant [0-9]')"
record NOTE "status menu items" "$(cat "$W/menu.txt")"
open_settings
expect_eq "Settings… opens Settings in front" "$ID" "$(front)"

for appearance in light dark; do
  step "keyboard navigation, $appearance"
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $([ $appearance = dark ] && echo true || echo false)"
  sleep 2
  osascript -e "tell application id \"$ID\" to activate"; sleep 1
  AX Volant select "$S" General >/dev/null; sleep 1
  AX Volant focus "$S" "Sidebar" >/dev/null; sleep 0.5
  key 125; sleep 1
  expect_eq "Down arrow in the sidebar moves to Appearance ($appearance)" Appearance "$(selected_section)"
  shot "keyboard-$appearance-appearance"
  key 125; key 125; key 125; key 125; key 125; sleep 1
  expect_eq "repeated Down reaches Data & Configuration ($appearance)" "Data & Configuration" "$(selected_section)"
  shot "keyboard-$appearance-data"
  key 126; key 126; key 126; key 126; key 126; key 126; sleep 1
  expect_eq "Up returns to General ($appearance)" General "$(selected_section)"
  key 48; sleep 0.5
  focus=$(focused)
  case "$focus" in
    AXCheckBox*|AXButton*) record PASS "Tab moves from the sidebar into the pane ($appearance)" "$focus" ;;
    *) record FAIL "Tab moves from the sidebar into the pane ($appearance)" "focused: $focus" ;;
  esac
  shot "keyboard-$appearance-general"
done
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'
sleep 1
osascript -e "tell application id \"$ID\" to activate"; sleep 1
key 53; sleep 1
expect_eq "Escape closes Settings" 0 "$(onscreen Volant | grep -c "$S")"

step "change a setting"
open_settings General
before=$(config_get showOnLaunch)
AX Volant press "$S" "role=AXCheckBox:Show launcher when Volant starts" >/dev/null; sleep 1.5
expect_eq "turning off Show launcher when Volant starts writes config.json" "false" "$(config_get showOnLaunch)"
record NOTE "showOnLaunch before the change" "$before"

step "export"
AX Volant select "$S" "Data & Configuration" >/dev/null; sleep 1.5
AX Volant press "$S" "role=AXButton:Volant backup#2" >/dev/null; sleep 3
if [ "$(AX Volant count "*" "Export Here")" -ge 1 ]; then
  record PASS "accessibility can press Export…"
else
  record FAIL "accessibility can press Export…" \
    "pressing the second button in the Volant backup row opened the $(AX Volant count "*" "Import" | sed 's/^[1-9].*/Import/;s/^0$/no/') panel; both buttons expose Import…'s label and frame"
fi
AX Volant press "*" Cancel >/dev/null 2>&1; sleep 1.5
click_element "$S" "role=AXButton:Volant backup" 78; sleep 3
expect_eq "clicking Export… opens a folder panel with Export Here" 1 "$(AX Volant count "*" "Export Here")"
choose_folder "$DOCS"
key 36; sleep 4
export=$(find "$DOCS" -maxdepth 1 -name 'Volant-Backup-*' -type d | head -1)
if [ -n "$export" ] && [ -f "$export/config.json" ]; then
  record PASS "Export writes a dated backup folder with config.json" "$(basename "$export")"
  expect_eq "Export reveals the backup in Finder" com.apple.finder "$(wait_front com.apple.finder 5)"
else
  alert=$(AX Volant dump "*" | grep -A3 "Export failed" | grep AXStaticText | tail -1 | sed 's/.* | //')
  record FAIL "Export writes a dated backup folder with config.json" "${alert:-nothing written and no alert}"
  shot export-failed
  key 36; sleep 1
fi

step "import"
manual="$DOCS/Volant-Backup-2026-01-01"
mkdir -p "$manual"
python3 - "$W/config-initial.json" "$manual/config.json" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
config["showOnLaunch"] = True
config.setdefault("aliases", {})["zq"] = "/System/Applications/TextEdit.app"
json.dump(config, open(sys.argv[2], "w"), indent=2, sort_keys=True)
PY
osascript -e "tell application id \"$ID\" to activate"; sleep 1
AX Volant press "$S" "role=AXButton:Volant backup" >/dev/null; sleep 3
expect_eq "Import… opens a folder panel with Import" 1 "$(AX Volant count "*" "role=AXButton:Import")"
choose_folder "$manual"
key 36; sleep 2.5
shot import-confirm
if [ "$(AX Volant count "*" "Import this backup?")" -ge 1 ]; then
  record PASS "Import shows a preview before applying"
  AX Volant press "*" "role=AXButton:Import" >/dev/null; sleep 3
else
  record FAIL "Import shows a preview before applying" "$(AX Volant dump "*" | grep -m2 AXStaticText | sed 's/.* | //' | tr '\n' ' ')"
  key 53; sleep 1
fi
expect_eq "Import restores the backed-up setting" "true" "$(config_get showOnLaunch)"
expect_eq "Import adds the backed-up alias" "/System/Applications/TextEdit.app" "$(config_get aliases.zq)"

step "Reload Configuration"
python3 - "$CONFIG" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
config.setdefault("aliases", {})["zr"] = "/System/Applications/TextEdit.app"
json.dump(config, open(sys.argv[1], "w"), indent=2, sort_keys=True)
PY
open_settings "Data & Configuration"
AX Volant press "$S" "role=AXButton:Apply edits made outside Settings" >/dev/null; sleep 2
expect_eq "Reload Configuration shows no error" 0 "$(AX Volant count "*" "Configuration not applied")"
key 53; sleep 1
quit_app $TE
osascript -e 'tell application "Finder" to activate' >/dev/null; sleep 1
record NOTE "aliases in config.json after Reload" "$(config_json aliases)"
key 49 "{option down}"; sleep 1; key 33 "{command down}"; sleep 0.5; type_text zq; sleep 2.5
shot alias-imported
key 36
expect_eq "an imported alias opens its app" $TE "$(wait_front $TE 8)"
quit_app $TE
osascript -e 'tell application "Finder" to activate' >/dev/null; sleep 1
key 49 "{option down}"; sleep 1; key 33 "{command down}"; sleep 0.5; type_text zr; sleep 2.5
shot alias-reloaded
key 36
expect_eq "an alias added outside Settings works after Reload" $TE "$(wait_front $TE 8)"
quit_app $TE

step "Reveal in Finder"
open_settings "Data & Configuration"
click_element "$S" "role=AXButton:config.json" 90; sleep 3
expect_eq "Reveal in Finder brings Finder forward" com.apple.finder "$(wait_front com.apple.finder 5)"
target=$(osascript -e 'tell application "System Events" to tell process "Finder" to get name of window 1' 2>&1)
expect_eq "the Finder window shows config.json's folder" Vey "$target"
shot reveal
key 13 "{command down}"; sleep 0.5
