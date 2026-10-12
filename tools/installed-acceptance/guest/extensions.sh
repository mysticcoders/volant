# Network extensions: install the Hacker News and Lobsters extensions, approve their hosts from the
# launcher prompt, read real stories, open a story and its discussion, then remove a host and uninstall
# an extension in Settings. Needs the guest's network. Results are read from config.json, the
# extensions folder, the launcher's accessibility text and the browser's window title.
SECTION=extensions
source "/Volumes/My Shared Files/artifacts/lib.sh"
S="Volant Settings"
EXT_DIR="$SUPPORT/Extensions"

hosts() { /usr/bin/python3 -c "import json;print(json.dumps(json.load(open('$CONFIG')).get('extensionHosts', []), separators=(',', ':')))"; }
launcher_text() { AX Volant dump "*" 2>/dev/null; "$W/bin/axtree" "$ID" dump "*" 2>/dev/null; }
story_rows() { "$W/bin/axtree" "$ID" dump "*" 2>/dev/null | grep -c ' points · '; }

# Opens the launcher in search mode and types a query, then waits for the rows to settle.
query() {
  osascript -e 'tell application "Finder" to activate' >/dev/null; sleep 0.5
  key 49 "{option down}"; sleep 1; key 33 "{command down}"; sleep 0.4
  key 0 "{command down}"; type_text "$1"; sleep 1.5
}

# Waits up to $1 seconds for story rows to appear; prints how many there are.
wait_stories() {
  for _ in $(seq 1 "$1"); do [ "$(story_rows)" -ge 1 ] && break; sleep 1; done
  story_rows
}

pgrep -x Volant >/dev/null || launch_volant
allow_capture
key 53; sleep 1

step "install"
mkdir -p "$EXT_DIR"
rm -rf "$EXT_DIR/hackernews" "$EXT_DIR/lobsters"
cp -R "$A/extensions/hackernews" "$A/extensions/lobsters" "$EXT_DIR/"
open_settings Extensions
if [ "$(AX Volant find "$S" "community-extensions-toggle" | sed 's/.* | //')" != 1 ]; then
  AX Volant press "$S" "community-extensions-toggle" >/dev/null; sleep 1
fi
AX Volant press "$S" "Refresh" >/dev/null; sleep 1.5
expect_eq "community extensions are allowed" true "$(config_get communityExtensionsAllowed)"
expect_eq "both extensions are listed" 2 "$(AX Volant count "$S" "prefix=extension-toggle-community.volant.")"
key 53; sleep 1

step "Hacker News: approve its host from the launcher"
query hn
key 36; sleep 2
shot hn-prompt
prompt=$(launcher_text)
case "$prompt" in
  *"hn.algolia.com"*) record PASS "the prompt lists hn.algolia.com before anything is fetched" ;;
  *) record FAIL "the prompt lists hn.algolia.com before anything is fetched" "no host list shown" ;;
esac
expect_eq "nothing is allowed before the owner answers" "[]" "$(hosts)"
key 36; sleep 1
rows=$(wait_stories 20)
shot hn-stories
if [ "$rows" -ge 10 ]; then record PASS "Allow and Run shows Hacker News front-page stories" "$rows rows"; else record FAIL "Allow and Run shows Hacker News front-page stories" "$rows rows"; fi
expect_eq "the host is saved as allowed" '["hn.algolia.com"]' "$(hosts)"
expect_eq "the extension is enabled" True \
  "$(/usr/bin/python3 -c "import json;print(json.load(open('$CONFIG'))['extensions']['community.volant.hn']['enabled'])")"

step "open a story and its discussion"
key 36; sleep 4
browser=$(front)
case "$browser" in
  com.apple.Safari|com.google.Chrome|org.mozilla.firefox) record PASS "Return opens the story in the browser" "$browser" ;;
  *) record FAIL "Return opens the story in the browser" "frontmost: $browser" ;;
esac
osascript -e "quit app id \"$browser\"" >/dev/null 2>&1; sleep 2
query hn; key 36; wait_stories 20 >/dev/null
key 36 "{command down}"; sleep 5
title=$(osascript -e 'tell application "System Events" to tell (first process whose frontmost is true) to get name of window 1' 2>&1)
case "$title" in
  *"Hacker News"*) record PASS "Command-Return opens the discussion on news.ycombinator.com" "$title" ;;
  *) record FAIL "Command-Return opens the discussion on news.ycombinator.com" "window: $title" ;;
esac
osascript -e "quit app id \"$(front)\"" >/dev/null 2>&1; sleep 2

step "Hacker News: new and search"
query "hn new"; key 36
expect_eq "hn new shows stories" yes "$([ "$(wait_stories 20)" -ge 5 ] && echo yes || echo no)"
key 53; sleep 0.5
query "hn rust"; key 36
expect_eq "hn rust searches stories" yes "$([ "$(wait_stories 20)" -ge 1 ] && echo yes || echo no)"
key 53; sleep 0.5

step "Lobsters"
query lobsters; key 36; sleep 2
case "$(launcher_text)" in
  *"lobste.rs"*) record PASS "the Lobsters prompt lists lobste.rs" ;;
  *) record FAIL "the Lobsters prompt lists lobste.rs" ;;
esac
key 36
rows=$(wait_stories 20)
shot lobsters-stories
if [ "$rows" -ge 10 ]; then record PASS "Lobsters hottest stories appear" "$rows rows"; else record FAIL "Lobsters hottest stories appear" "$rows rows"; fi
key 53; sleep 0.5
query "lobsters rust"; key 36
expect_eq "lobsters rust shows the rust tag" yes "$([ "$(wait_stories 20)" -ge 1 ] && echo yes || echo no)"
key 53; sleep 0.5
query "lobsters two words here"; key 36; sleep 4
case "$(launcher_text)" in
  *"Type lobsters"*) record PASS "an unusable query explains itself instead of fetching" ;;
  *) record FAIL "an unusable query explains itself instead of fetching" ;;
esac
key 53; sleep 0.5
expect_eq "both hosts are allowed" '["hn.algolia.com","lobste.rs"]' "$(hosts)"

step "Settings: hosts, users and removal"
open_settings Extensions
shot settings-hosts
expect_eq "Network Access shows who uses hn.algolia.com" 1 "$(AX Volant count "$S" "Used by Hacker News")"
expect_eq "Network Access shows who uses lobste.rs" 1 "$(AX Volant count "$S" "Used by Lobsters")"
AX Volant press "$S" "extension-host-remove-lobste.rs" >/dev/null; sleep 1.5
expect_eq "Remove takes lobste.rs out of the allowed hosts" '["hn.algolia.com"]' "$(hosts)"
key 53; sleep 1
query lobsters; key 36; sleep 2
case "$(launcher_text)" in
  *"lobste.rs"*) record PASS "after removal, Lobsters asks for lobste.rs again" ;;
  *) record FAIL "after removal, Lobsters asks for lobste.rs again" ;;
esac
key 53; sleep 0.5
key 53; sleep 0.5
expect_eq "cancelling the prompt allows nothing" '["hn.algolia.com"]' "$(hosts)"

step "Settings: uninstall"
open_settings Extensions
AX Volant press "$S" "extension-uninstall-community.volant.hn" >/dev/null; sleep 1.5
shot uninstall-confirm
AX Volant press "*" "Uninstall" >/dev/null; sleep 2
expect_eq "Uninstall removes the Hacker News folder" no "$([ -d "$EXT_DIR/hackernews" ] && echo yes || echo no)"
expect_eq "Uninstall removes hn.algolia.com, which nothing else uses" "[]" "$(hosts)"
expect_eq "Uninstall forgets the Hacker News approval" no \
  "$(/usr/bin/python3 -c "import json;print('yes' if 'community.volant.hn' in json.load(open('$CONFIG')).get('extensions',{}) else 'no')")"
expect_eq "Lobsters stays installed" yes "$([ -d "$EXT_DIR/lobsters" ] && echo yes || echo no)"
key 53; sleep 0.5

step "dark appearance screenshots"
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'; sleep 2
query lobsters; key 36; wait_stories 20 >/dev/null; shot dark-stories
key 53; sleep 0.5
open_settings Extensions; shot dark-settings
key 53; sleep 0.5
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'
