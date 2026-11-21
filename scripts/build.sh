#!/bin/zsh
# Builds SAT Tracker.app. --install copies it to /Applications and opens it.
set -euo pipefail
cd "${0:A:h}/.."
APP="build/SAT Tracker.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos27.0 -o "$APP/Contents/MacOS/SATTracker" Sources/*.swift
cp Resources/Info.plist "$APP/Contents/"
if [[ ! -f build/AppIcon.icns || scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
  rm -rf build/AppIcon.iconset; mkdir -p build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/"
# Same signing identity every build, so Screen Recording / Accessibility permission survives rebuilds.
ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --options runtime --sign "${ID:--}" "$APP"
if [[ "${1:-}" == "--install" ]]; then
  pkill -x SATTracker 2>/dev/null || true; sleep 0.5
  rm -rf "/Applications/SAT Tracker.app"
  ditto "$APP" "/Applications/SAT Tracker.app"
  open "/Applications/SAT Tracker.app"
fi
echo "built $APP"
