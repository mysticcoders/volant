#!/bin/bash
# Renders the 1280×640 social card used by the GitHub repository preview and the website's
# Open Graph and Twitter tags, from the shipping app icon. Drawn offscreen; no window opens.
# PNG rather than WebP: GitHub's social preview accepts only PNG, JPG or GIF, and several link
# preview services do not render WebP.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/volant-social.XXXXXX)
trap 'rm -rf "$work"' EXIT
swiftc -O tools/social/card.swift -o "$work/card"
"$work/card" Volant/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png website/public/images/social-card.png
echo "rendered website/public/images/social-card.png"
