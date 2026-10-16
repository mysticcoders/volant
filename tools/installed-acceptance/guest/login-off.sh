# Turns Launch at Login off in Settings and quits Volant before the second reboot (#2).
SECTION=settings
source "/Volumes/My Shared Files/artifacts/lib.sh"
S="Volant Settings"
LOGIN="role=AXCheckBox:Launch at Login"
pgrep -x Volant >/dev/null || launch_volant
allow_capture
key 53; sleep 1
open_settings General
AX Volant press "$S" "$LOGIN" >/dev/null; sleep 3
expect_eq "turning Launch at Login off updates the switch" 0 "$(AX Volant find "$S" "$LOGIN" | sed 's/.* | //')"
disposition=$(login_item)
case "$disposition" in
  absent|*disabled*) record PASS "macOS disables the login item when turned off" "$disposition" ;;
  *) record FAIL "macOS disables the login item when turned off" "$disposition" ;;
esac
key 53; sleep 0.5
quit_volant
forget_relaunch
expect_eq "Volant is not running before the reboot" no "$(running Volant)"
phase_finished
