#!/bin/bash
# Builds Notchly.app into ./build and launches it.
set -euo pipefail
cd "$(dirname "$0")"

pkill -x Notchly 2>/dev/null || true
swift build -c release

APP="build/Notchly.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Notchly "$APP/Contents/MacOS/Notchly"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: prebuilt .icns (regenerate with `swift scripts/make-icon.swift`), png fallback
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
elif [ -f Resources/AppIcon.png ]; then
  SET="build/AppIcon.iconset"
  rm -rf "$SET"; mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$SET/icon_${s}x${s}.png" >/dev/null 2>&1 || true
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || true
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
  rm -rf "$SET"
fi

# System-wide media bridge (non-fatal if it fails)
mkdir -p "$APP/Contents/Frameworks"
if clang -dynamiclib -fobjc-arc -framework Foundation -o "$APP/Contents/Frameworks/libNotchlyMedia.dylib" bridge/MediaBridge.m 2>/tmp/notchly_bridge.log; then
  codesign --force --sign - "$APP/Contents/Frameworks/libNotchlyMedia.dylib"
else
  echo "media bridge skipped (see /tmp/notchly_bridge.log)"
fi

codesign --force --sign - "$APP"
echo "Built $APP"
open "$APP"
