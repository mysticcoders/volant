# Quits and relaunches Volant, then checks that the bindings recorded by the given section still
# deliver. Run between sections by run-vm.py.
SECTION=${1:-shortcuts}
source "/Volumes/My Shared Files/artifacts/lib.sh"
TE=com.apple.TextEdit

step "restart Volant"
before=$(config_json appHotKeys)
quit_volant
quit_app $TE
launch_volant
key 53; sleep 1
expect_eq "bindings in config.json survive a restart" "$before" "$(config_json appHotKeys)"
osascript -e 'tell application "Finder" to activate' >/dev/null; sleep 1
key 32 "{command down, option down}" >/dev/null
expect_eq "the shortcut works after a restart" $TE "$(wait_front $TE 8)"
expect_eq "Option-Space works after a restart" 1 "$(key 49 '{option down}' >/dev/null; sleep 1.5; onscreen Volant | grep -c '^3 ')"
key 53; sleep 0.5
quit_app $TE
