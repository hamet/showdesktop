#!/bin/bash
# Builds "Show Desktop.app" next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP="Show Desktop.app"
rm -rf "$APP" AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ compiling"
swiftc -O -o "$APP/Contents/MacOS/ShowDesktop" ShowDesktop.swift

echo "→ icon"
mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s         icon.png --out "AppIcon.iconset/icon_${s}x${s}.png"    >/dev/null
  sips -z $((s*2)) $((s*2)) icon.png --out "AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf AppIcon.iconset

cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "✓ $APP"
