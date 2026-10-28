#!/usr/bin/env python3
"""Keep the explicit Swift inventory aligned with the project's exact dependency pin."""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
project = (root / 'project.yml').read_text()
match = re.search(r'^  Sparkle:\n    url: (\S+)\n    exactVersion: (\S+)\n', project, re.MULTILINE)
if not match:
    raise SystemExit('Sparkle dependency changed: update and review its security inventory.')
pins = json.loads((root / 'tools/security/Package.resolved').read_text())['pins']
if len(pins) != 1 or pins[0]['location'] != match[1] or pins[0]['state']['version'] != match[2]:
    raise SystemExit('Swift security inventory differs from project.yml.')
print('Swift security inventory matches the exact Sparkle pin.')
