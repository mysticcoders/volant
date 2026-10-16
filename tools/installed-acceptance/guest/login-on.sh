# Launch at Login, before the first reboot (#2): turn it on in Settings, check the login item,
# remove it in System Settings and confirm Volant shows it off, then turn it on again and quit
# Volant so only the login item can start it after the reboot.
SECTION=settings
source "/Volumes/My Shared Files/artifacts/lib.sh"
S="Volant Settings"
LOGIN="role=AXCheckBox:Launch at Login"
switch_value() { AX Volant find "$S" "$LOGIN" | sed 's/.* | //'; }

pgrep -x Volant >/dev/null || launch_volant
key 53; sleep 1

step "turn on Launch at Login"
open_settings General
expect_eq "Launch at Login starts off" 0 "$(switch_value)"
AX Volant press "$S" "$LOGIN" >/dev/null; sleep 3
expect_eq "the switch turns on" 1 "$(switch_value)"
disposition=$(login_item)
case "$disposition" in
  *enabled*allowed*) record PASS "macOS records an enabled login item" "$disposition" ;;
  *) record FAIL "macOS records an enabled login item" "$disposition" ;;
esac
approval=$(AX Volant count "$S" "prefix=Allow Volant in System Settings")
record NOTE "approval requested" "$([ "$approval" -ge 1 ] && echo "yes: Allow Volant in System Settings is shown" || echo "no; macOS enabled it without asking")"
shot login-on

step "remove it in System Settings"
open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"; sleep 6
AX "System Settings" select "*" Volant >/dev/null; sleep 0.5
minus=$(AX "System Settings" frames "*" role=AXButton | grep -n '| Kind |' | cut -d: -f1)
AX "System Settings" press "*" "role=AXButton#$((minus + 2))" >/dev/null; sleep 2
expect_eq "System Settings no longer lists Volant" 0 "$(AX "System Settings" count "*" Volant)"
expect_eq "macOS drops the login item" absent "$(login_item)"
osascript -e 'quit app "System Settings"' >/dev/null 2>&1
osascript -e "tell application id \"$ID\" to activate"; sleep 1
AX Volant select "$S" Appearance >/dev/null; sleep 1; AX Volant select "$S" General >/dev/null; sleep 1.5
expect_eq "Volant's switch shows it off after the removal" 0 "$(switch_value)"
shot login-removed

step "turn it on again for the reboot"
AX Volant press "$S" "$LOGIN" >/dev/null; sleep 3
expect_eq "the switch turns on again" 1 "$(switch_value)"
key 53; sleep 0.5
quit_volant
forget_relaunch
expect_eq "Volant is not running before the reboot" no "$(running Volant)"
phase_finished
