# After a reboot: checks whether Volant started by itself. `on` expects it to, `off` expects not.
SECTION=settings
source "/Volumes/My Shared Files/artifacts/lib.sh"
want=${1:?on or off}
step "after the reboot (Launch at Login $want)"
for _ in $(seq 1 45); do pgrep -x Volant >/dev/null && break; sleep 2; done
[ "$want" = off ] && sleep 20
started=$(running Volant)
if [ "$started" = yes ]; then
  pid=$(pgrep -x Volant | head -1)
  record NOTE "how Volant started" "pid $pid, parent $(ps -o ppid= -p "$pid" | tr -d ' '), started $(ps -o lstart= -p "$pid")"
  log show --last 10m --style compact --predicate 'eventMessage CONTAINS[c] "volant" AND (process == "smd" OR process == "backgroundtaskmanagementd" OR process == "launchd" OR process == "loginwindow")' \
    > "$A/login-check-$want-launch.log" 2>&1
fi
record NOTE "boot" "$(sysctl -n kern.boottime | sed 's/.*} //'), login item: $(login_item)"
if [ "$want" = on ]; then
  expect_eq "Volant starts at login after a restart" yes "$started"
else
  expect_eq "Volant does not start at login once turned off" no "$started"
fi
