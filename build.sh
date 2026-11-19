#!/bin/bash
# Builds build/Tackie.app.
#   ./build.sh           build only
#   ./build.sh install   build, copy to /Applications, and launch
#   ./build.sh release   build and zip it as build/Tackie.zip (for a GitHub release)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Tackie.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tackie "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built: $APP"

case "${1:-}" in
    install)
        pkill -x Tackie 2>/dev/null || true
        rm -rf "/Applications/Tackie.app"
        cp -R "$APP" /Applications/
        echo "Installed to /Applications/Tackie.app"
        open "/Applications/Tackie.app"
        ;;
    release)
        rm -f build/Tackie.zip
        ditto -c -k --keepParent "$APP" build/Tackie.zip
        echo "Release zip: build/Tackie.zip"
        ;;
esac
