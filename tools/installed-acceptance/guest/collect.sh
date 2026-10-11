# Copies logs and crash reports out of the guest after all phases.
SECTION=collect
source "/Volumes/My Shared Files/artifacts/lib.sh"
log show --last 2h --style compact --predicate 'subsystem == "com.mysticcoders.volant"' > "$A/volant.log" 2>&1
cp "$W"/config-*.json "$A/" 2>/dev/null
reports=$(ls ~/Library/Logs/DiagnosticReports/*Volant* 2>/dev/null)
if [ -n "$reports" ]; then
  cp $reports "$A/"
  record FAIL "no Volant crash reports" "$(echo "$reports" | wc -l | tr -d ' ') report(s)"
else
  record PASS "no Volant crash reports"
fi
