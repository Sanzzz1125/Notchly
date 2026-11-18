#!/bin/bash
# Records the README screenshots from the real, running app.
#  - Runs build/Notchly.app with factory settings (in memory, -factoryDefaults) and sample data (demo mode),
#    so none of your own calendar, clipboard or music appears and your real settings are untouched.
#  - Captures only Notchly's own windows (screencapture -l), never the rest of the screen.
# Raw captures go to build/shots/, then scripts/compose.py builds the presentation images in docs/.
# Usage: ./build.sh && ./scripts/screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x build/Notchly.app/Contents/MacOS/Notchly ] || { echo "Build first: ./build.sh"; exit 1; }
./scripts/make-test-app.sh >/dev/null       # isolated copy: own settings, can never touch the real app
BIN="build/NotchlyTest.app/Contents/MacOS/Notchly"
OUT="build/shots"; rm -rf "$OUT"; mkdir -p "$OUT" docs
swiftc -O scripts/winshot.swift -o build/winshot 2>/dev/null

pkill -x Notchly 2>/dev/null || true; sleep 0.5
trap 'pkill -x Notchly 2>/dev/null' EXIT
nohup "$BIN" -factoryDefaults YES -demoMode YES -debugHooks YES -onboarded YES \
  -tab_weather YES -weatherEnabled YES \
  -demoMedia spotify -spotifyEnabled YES -spotifyDefaultID demo0 -spotifyDefaultName Movzzzzzz >/dev/null 2>&1 &
sleep 3
# park the pointer away from the notch so only scripted opens happen
shot() { build/winshot Notchly "$OUT/$1.png" "${2:-}"; echo "  $OUT/$1.png"; }

echo "Closed island (music ears) and alert"
sleep 1; shot closed
notifyutil -p notchly.debug.alert; sleep 1.0; shot alert
sleep 6

echo "Tabs"
for t in home tray clipboard notes calendar reminders timer stats controls weather stash apps; do
  notifyutil -p notchly.debug.open.$t; sleep 1.3; shot "tab-$t"
done
notifyutil -p notchly.debug.open.home; sleep 1.0; notifyutil -p notchly.debug.spotify.picker; sleep 1.3; shot picker
notifyutil -p notchly.debug.close; sleep 0.8

echo "Settings and onboarding"
for p in stash playlists appearance tabshome shortcuts privacy; do
  notifyutil -p notchly.debug.settings.$p; sleep 1.3; shot "settings-$p" "Notchly"
done
for n in 0 1; do notifyutil -p notchly.debug.onboard.$n; sleep 1.3; shot "onboarding-$n" "Welcome"; done
python3 scripts/compose.py || echo "(install Pillow, pip3 install pillow, to build the docs/ images from build/shots/)"
echo "Done."
