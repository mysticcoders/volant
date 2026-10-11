# Installs the release DMG the way a Finder drag does, starts Volant once so it creates its
# container and config.json, then turns off Sparkle's automatic checks so its permission prompt
# and update offers cannot cover the windows under test.
SECTION=install
source "/Volumes/My Shared Files/artifacts/lib.sh"
sw_vers
: > "$A/results.tsv"

step "install"
pkill -x Volant 2>/dev/null
rm -rf "$APP" "$HOME/Library/Containers/$ID"
hdiutil attach "$A/Volant.dmg" -nobrowse -readonly -mountpoint "$W/dmg" >/dev/null || { record FAIL "mount DMG"; exit 1; }
ditto "$W/dmg/Volant.app" "$APP"
hdiutil detach "$W/dmg" >/dev/null
xattr -cr "$APP"
version=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)
build=$(defaults read "$APP/Contents/Info.plist" CFBundleVersion)
echo "$version ($build)" > "$W/version"
record NOTE "installed" "Volant $version ($build), $(sw_vers -productVersion) $(uname -m)"
gatekeeper=$(spctl -a -vv "$APP" 2>&1 | tr '\n' ' ')
case "$gatekeeper" in
  *"Notarized Developer ID"*) record PASS "Gatekeeper accepts the app" "$gatekeeper" ;;
  *) record FAIL "Gatekeeper accepts the app" "$gatekeeper" ;;
esac

step "Spotlight (off in Cirrus images; Volant's app list comes from it)"
sudo mdutil -i on / >/dev/null 2>&1
sudo mdutil -i on /System/Volumes/Data >/dev/null 2>&1
for _ in $(seq 1 60); do mdfind "kMDItemCFBundleIdentifier == com.apple.TextEdit" | grep -q TextEdit && break; sleep 5; done
expect_eq "Spotlight indexes TextEdit" /System/Applications/TextEdit.app "$(mdfind 'kMDItemCFBundleIdentifier == com.apple.TextEdit' | head -1)"

step "guest settings"
defaults write com.apple.loginwindow TALLogoutSavesState -bool false
defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool false
defaults write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false
defaults write -g AppleKeyboardUIMode -int 2
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'

step "first launch"
launch_volant
expect_eq "first launch creates config.json" yes "$([ -f "$CONFIG" ] && echo yes || echo no)"
quit_volant
defaults write "$CONTAINER/Library/Preferences/$ID" SUEnableAutomaticChecks -bool false
defaults write "$CONTAINER/Library/Preferences/$ID" SUHasLaunchedBefore -bool true
cp "$CONFIG" "$W/config-initial.json"
echo "summonHotKey: $(config_get summonHotKey)"
