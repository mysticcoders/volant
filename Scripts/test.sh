#!/bin/bash
# Select UI verification from the diff; --ui always/never/only is an explicit override.
set -euo pipefail
cd "$(dirname "$0")/.."
ui_mode=auto
base=origin/main
ci=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ui) ui_mode="$2"; shift 2 ;;
        --base) base="$2"; shift 2 ;;
        --ci) ci=true; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
case "$ui_mode" in auto|always|never|only) ;; *) echo 'Invalid --ui mode' >&2; exit 2 ;; esac
run_ui=false
if [[ "$ui_mode" == auto ]]; then
    scope_json=$(python3 tools/test-scope.py --base "$base" --include-working-tree)
    run_ui=$(printf '%s' "$scope_json" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["ui"]).lower())')
elif [[ "$ui_mode" != never ]]; then
    run_ui=true
fi
printf 'UI verification: %s (mode: %s)\n' "$run_ui" "$ui_mode"
# Runs one step and reports how long it took, so slow steps show up in CI logs.
timed() {
    local start=$SECONDS
    "$@"
    printf 'step time: %4ss  %s\n' "$((SECONDS - start))" "$*"
}
timed python3 tools/test-scope-tests.py
timed python3 tools/check-input-confinement.py --self-test
timed python3 tools/check-release-copy.py --self-test
timed python3 tools/check-input-confinement.py
timed python3 tools/interaction-speed/check.py
timed python3 tools/ui-vm-dispatch-tests.py
timed xcodegen generate --quiet
timed python3 tools/check-dev-entitlements.py
build_options=(-project Volant.xcodeproj -scheme Volant -derivedDataPath build -destination 'platform=macOS')
if [[ "$ci" == true ]]; then
    build_options+=(CODE_SIGNING_ALLOWED=NO ENABLE_APP_SANDBOX=NO)
fi
if [[ "$ui_mode" != only ]]; then
    timed swiftlint lint --strict --quiet --config .swiftlint.yml
    timed ./tools/check-raycast.sh
    timed ./tools/check-volume.sh
    timed ./tools/check-acp.sh
    timed ./tools/check-ai-http.sh
    timed ./tools/check-rex.sh
    timed ./tools/check-extensions.sh
    timed ./tools/check-paste-key.sh
    timed swift test --package-path Core
    timed xcodebuild "${build_options[@]}" test -skip-testing:VolantTests/NotesRenderTests \
        -skip-testing:VolantTests/LiveMarkdownTests/testLanguageChangePreservesContentSelectionAndUndo \
        -skip-testing:VolantTests/LiveMarkdownTests/testTypingFenceAndChangingModesDoNotRewriteSource
    # Reads the .stringsdata that test build wrote, so it runs after it.
    timed python3 tools/strings.py --check
fi
if [[ "$run_ui" == true ]]; then
    if [[ "$ci" != true && "${VOLANT_HOST_UI_TESTS:-0}" != 1 ]]; then
        python3 tools/test-ui-vm.py
        exit 0
    fi
    timed ./tools/check-launcher.sh
    timed ./tools/check-launcher-actions.sh
    timed ./tools/check-dictation-hud.sh
    timed xcodebuild "${build_options[@]}" test -only-testing:VolantTests/NotesRenderTests \
        -only-testing:VolantTests/LiveMarkdownTests/testLanguageChangePreservesContentSelectionAndUndo \
        -only-testing:VolantTests/LiveMarkdownTests/testTypingFenceAndChangingModesDoNotRewriteSource
else
    echo 'Skipped native UI/keyboard/render fixtures: no UI changes, or explicitly disabled.'
fi
