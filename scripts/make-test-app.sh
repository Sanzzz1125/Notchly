#!/bin/bash
# Makes build/NotchlyTest.app: a copy of build/Notchly.app with its own bundle id (com.sanketh.Notchly.test).
# It has its own settings domain and no notchly:// URL scheme, so tests and screenshots can never read or
# change the real app's settings or receive its Spotify sign-in.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d build/Notchly.app ] || { echo "Build first: ./build.sh"; exit 1; }
rm -rf build/NotchlyTest.app
cp -R build/Notchly.app build/NotchlyTest.app
PL=build/NotchlyTest.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.sanketh.Notchly.test" "$PL"
/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$PL" 2>/dev/null || true
codesign --force --sign - build/NotchlyTest.app/Contents/Frameworks/libNotchlyMedia.dylib >/dev/null 2>&1 || true
codesign --force --sign - build/NotchlyTest.app >/dev/null 2>&1
echo build/NotchlyTest.app
