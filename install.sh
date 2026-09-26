#!/bin/bash
# Copies the app to /Applications and adds it to the Dock.
set -euo pipefail
cd "$(dirname "$0")"

APP="Show Desktop.app"
[ -d "$APP" ] || ./build.sh

pkill -x ShowDesktop 2>/dev/null || true
rm -rf "/Applications/$APP"
cp -R "$APP" /Applications/

if ! defaults read com.apple.dock persistent-apps | grep -qE 'Show( |%20)Desktop\.app'; then
  defaults write com.apple.dock persistent-apps -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/$APP</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
  killall Dock
fi

echo "✓ installed"
