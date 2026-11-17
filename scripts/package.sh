#!/bin/bash
# Builds Notchly.app and zips it for sharing: dist/Notchly-<version>.zip (+ .sha256)
# The app is ad-hoc signed (no Apple Developer account), so recipients open it with right-click -> Open.
set -euo pipefail
cd "$(dirname "$0")/.."
NOTCHLY_NO_LAUNCH=1 ./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
mkdir -p dist
ZIP="dist/Notchly-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --norsrc --noextattr --noacl --keepParent build/Notchly.app "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Created $ZIP ($(du -h "$ZIP" | cut -f1))"
