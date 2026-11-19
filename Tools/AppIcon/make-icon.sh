#!/bin/bash
# Rebuilds Resources/AppIcon.icns (and a preview PNG) from Tools/AppIcon/Icon.swift.
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp -d)
swiftc -o "$TMP/render" Icon.swift main.swift
"$TMP/render" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o ../../Resources/AppIcon.icns
cp "$TMP/AppIcon.iconset/icon_512x512@2x.png" ../../Resources/AppIcon-preview.png
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
