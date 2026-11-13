#!/bin/bash
# Make .venv hold exactly the hash-locked Python packages the checks import, as CI does. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v uv >/dev/null; then
    echo "uv is missing: brew install uv" >&2
    exit 1
fi
[[ -x .venv/bin/python ]] || uv venv --quiet .venv
uv pip sync --quiet --python .venv/bin/python --require-hashes tools/security/requirements.txt
