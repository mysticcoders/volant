#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
node -e 'if (+process.versions.node.split(".")[0] < 22) { console.error("Node 22 or newer is required"); process.exit(1) }'
volant_adapter_dir="$HOME/.local/share/volant/acp"
mkdir -p "$volant_adapter_dir"
cp Integrations/acp/package.json Integrations/acp/package-lock.json "$volant_adapter_dir/"
npm ci --prefix "$volant_adapter_dir" --omit=dev
