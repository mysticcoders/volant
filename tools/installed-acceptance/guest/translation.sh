# Translation acceptance (#5): Apple's download consent (decline, then accept), translation and
# Copy, offline behavior for an installed and a missing pair, and right-to-left Arabic. Results
# are read from the view's accessibility values and the clipboard. Needs the guest's network.
SECTION=translation
source "/Volumes/My Shared Files/artifacts/lib.sh"
export LC_ALL=en_US.UTF-8
ARABIC="Arabic (United Arab Emirates)"

pgrep -x Volant >/dev/null || launch_volant
allow_capture
killall NotificationCenter 2>/dev/null
key 53; sleep 1

result() { osascript -l JavaScript "$A/ax.js" Volant find "*" "prefix=Translation: " 2>/dev/null | sed 's/.* | Translation: //'; }
status() { osascript -l JavaScript "$A/ax.js" Volant find "*" "prefix=Translation status: " 2>/dev/null | sed 's/.* | Translation status: //'; }
source_text() { AX Volant find "*" "Text to translate" | sed 's/.* | //'; }
has_sheet() { AX Volant count "*" role=AXSheet; }

# Replaces the source text by selecting all and typing, as a person would.
enter_text() {
  AX Volant focus "*" "Text to translate" >/dev/null; sleep 0.3
  key 0 "{command down}"; type_text "$1"; sleep "${2:-1}"
}

# Waits for a non-empty result different from $1, up to $2 seconds; prints it.
wait_result() {
  local previous=$1 limit=${2:-30} current
  for _ in $(seq 1 $((limit / 2))); do
    current=$(result)
    [ -n "$current" ] && [ "$current" != "$previous" ] && break
    sleep 2
  done
  result
}

# Answers macOS's Download Languages sheet. Its buttons are a remote view that ignores AXPress,
# so they are clicked: every Download button for "accept", only Done for "decline".
consent() {
  for _ in $(seq 1 10); do [ "$(has_sheet)" -ge 1 ] && break; sleep 1; done
  [ "$(has_sheet)" -ge 1 ] || return 1
  killall NotificationCenter 2>/dev/null; sleep 1
  local frames
  frames=$(AX Volant frames "*" role=AXButton | sed 's/.*@ //' | tail -3)
  if [ "$1" = accept ]; then
    echo "$frames" | head -2 | while read -r x y w h; do click_at $((x + w / 2)) $((y + h / 2)); sleep 1.5; done
  else
    read -r x y w h <<< "$(echo "$frames" | tail -1)"
    click_at $((x + w / 2)) $((y + h / 2))
  fi
}

# Presses Done on the sheet if it is still up after an accepted download.
finish_sheet() {
  [ "$(has_sheet)" -ge 1 ] || return 0
  read -r x y w h <<< "$(AX Volant frames "*" role=AXButton | sed 's/.*@ //' | tail -1)"
  click_at $((x + w / 2)) $((y + h / 2)); sleep 2
}

step "open Translate"
key 49 "{option down}"; sleep 1; type_text translate; sleep 2.5
expect_eq "typing translate opens the Translate view" 1 "$(AX Volant count "*" "Text to translate")"
AX Volant menu "*" "prefix=Source language" English >/dev/null; sleep 1
AX Volant menu "*" "prefix=Target language" Spanish >/dev/null; sleep 1
enter_text "Good morning, how are you today?" 3
case "$(status)" in
  *"need a download"*) record PASS "an uninstalled pair asks for ⌘T instead of downloading" "$(status)" ;;
  *) record NOTE "status for English to Spanish before any download" "$(status)" ;;
esac

step "download consent: decline"
key 17 "{command down}"
if consent decline; then
  record PASS "⌘T brings up macOS's download consent"
  sleep 4
  expect_eq "declining keeps the source text" "Good morning, how are you today?" "$(source_text)"
  expect_eq "declining translates nothing" "" "$(result)"
  record NOTE "status after declining" "$(status)"
  shot declined
else
  record FAIL "⌘T brings up macOS's download consent" "no sheet; status: $(status)"
fi

step "download consent: accept"
key 17 "{command down}"
if consent accept; then
  spanish=$(wait_result "" 300)
  finish_sheet
  if [ -n "$spanish" ]; then record PASS "accepting downloads the languages and translates" "$spanish"; else record FAIL "accepting downloads the languages and translates" "status: $(status)"; fi
  expect_eq "the status says the languages are installed" "Languages installed · On-device translation" "$(status)"
else
  record FAIL "⌘T brings up the consent again after declining" "status: $(status)"
fi
shot spanish

step "copy"
echo sentinel | pbcopy
key 36 "{command down}"; sleep 1
expect_eq "⌘Return copies the translation" "$(result)" "$(pbpaste)"

step "offline, installed pair"
offline
expect_eq "the guest is offline" no "$(network_reachable)"
before=$(result)
enter_text "The museum closes early on Sunday." 1
offline_result=$(wait_result "$before" 20)
if [ -n "$offline_result" ] && [ "$offline_result" != "$before" ]; then
  record PASS "an installed pair translates offline" "$offline_result"
else
  record FAIL "an installed pair translates offline" "status: $(status)"
fi

step "offline, missing pair"
AX Volant menu "*" "prefix=Target language" French >/dev/null; sleep 3
record NOTE "status for English to French offline" "$(status)"
key 17 "{command down}"
if consent accept; then
  sleep 30
  expect_eq "a missing pair cannot finish offline" "" "$(result)"
  finish_sheet
  sleep 3
  case "$(status)" in
    *"couldn't finish"*|*"connection"*) record PASS "the offline failure says what to check" "$(status)" ;;
    *) record FAIL "the offline failure says what to check" "status: $(status)" ;;
  esac
  expect_eq "the source text is kept after the offline failure" "The museum closes early on Sunday." "$(source_text)"
else
  record NOTE "no consent sheet offline" "status: $(status)"
fi
shot offline-missing
online

step "back online"
key 17 "{command down}"
consent accept
french=$(wait_result "" 300)
finish_sheet
if [ -n "$french" ]; then record PASS "the missing pair downloads once back online" "$french"; else record FAIL "the missing pair downloads once back online" "status: $(status)"; fi

step "right-to-left: English to Arabic"
AX Volant menu "*" "prefix=Target language" "$ARABIC" >/dev/null; sleep 3
key 17 "{command down}"
consent accept
arabic=$(wait_result "$french" 300)
finish_sheet
if printf '%s' "$arabic" | python3 -c 'import sys; t=sys.stdin.read(); sys.exit(0 if any("؀" <= c <= "ۿ" for c in t) else 1)'; then
  record PASS "English to Arabic produces Arabic script" "$arabic"
else
  record FAIL "English to Arabic produces Arabic script" "result: [$arabic], status: $(status)"
fi
echo sentinel | pbcopy
key 36 "{command down}"; sleep 1
expect_eq "copying Arabic keeps every character" "$arabic" "$(pbpaste)"
shot rtl-result
record NOTE "inspect right-to-left layout" "shots/translation-rtl-result.png and shots/translation-rtl-source.png"

step "right-to-left: Arabic source"
AX Volant menu "*" "prefix=Source language" "$ARABIC" >/dev/null; sleep 1
AX Volant menu "*" "prefix=Target language" English >/dev/null; sleep 1
source_arabic="مرحبا، كيف حالك اليوم؟"
printf '%s' "$source_arabic" | pbcopy
AX Volant focus "*" "Text to translate" >/dev/null; sleep 0.3
key 0 "{command down}"; key 9 "{command down}"; sleep 1
expect_eq "pasted Arabic is kept exactly in the source" "$source_arabic" "$(source_text)"
english=$(wait_result "$arabic" 30)
if printf '%s' "$english" | grep -q '[A-Za-z]'; then record PASS "Arabic to English translates" "$english"; else record FAIL "Arabic to English translates" "result: [$english], status: $(status)"; fi
shot rtl-source
key 33 "{command down}"; sleep 1
key 53; sleep 0.5
