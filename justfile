# Run `just` to list the recipes.

default:
    @just --list

# Check the tools needed to build and test Volant, and say how to install what is missing.
doctor:
    #!/bin/bash
    missing=0
    ok() { printf '  ok       %s\n' "$1"; }
    need() { printf '  MISSING  %s: %s\n' "$1" "$2"; missing=1; }
    maybe() { printf '  optional %s: %s\n' "$1" "$2"; }
    echo "Required to build and test:"
    macos=$(sw_vers -productVersion)
    if (( ${macos%%.*} >= 15 )); then ok "macOS $macos"; else need "macOS $macos" "macOS 15 or later is required"; fi
    xcode=$(xcodebuild -version 2>/dev/null | head -1)
    if [[ "$xcode" =~ ^Xcode\ ([0-9]+) ]] && (( BASH_REMATCH[1] >= 26 )); then ok "$xcode ($(xcode-select -p))"
    else need "Xcode 26" "install Xcode 26 from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"; fi
    for tool in xcodegen swiftlint uv; do
        if command -v "$tool" >/dev/null; then ok "$tool"; else need "$tool" "brew install $tool"; fi
    done
    if command -v python3 >/dev/null; then ok "python3"; else need "python3" "xcode-select --install"; fi
    if [[ ! -x .venv/bin/python ]]; then need "Python test packages" "run: just build (or tools/python-env.sh)"
    elif uv pip sync --dry-run --python .venv/bin/python --require-hashes tools/security/requirements.txt 2>&1 | grep -q "Would make no changes"; then ok "Python test packages (.venv)"
    else need "Python test packages" ".venv is out of date; run: just build (or tools/python-env.sh)"; fi
    echo "Optional:"
    vm="${VOLANT_UI_VM:-volant-ui-xcode}"
    if ! command -v tart >/dev/null; then maybe "tart" "UI tests run in a Tart VM; brew install cirruslabs/cli/tart"
    elif tart list --format json | grep -q "\"Name\" *: *\"$vm\""; then ok "tart, VM $vm"
    else maybe "VM $vm" "UI tests need this Tart VM (or set VOLANT_UI_VM)"; fi
    if command -v npm >/dev/null; then ok "npm"; else maybe "npm" "only for the website; brew install node"; fi
    if command -v gh >/dev/null; then ok "gh"; else maybe "gh" "only for pull requests; brew install gh"; fi
    exit $missing

# Prepare the Python test packages, regenerate the Xcode project and build Volant Dev.
build:
    Scripts/build.sh

# Run the checks for what this branch changed, against BASE.
test base="origin/main":
    Scripts/test.sh --base {{base}}

# Run the VolantCore tests.
test-core:
    swift test --package-path Core
