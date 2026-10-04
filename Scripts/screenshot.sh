#!/bin/sh
# Renders docs/screenshot-*.png from the real app views, with made-up projects.
# It compiles ReleasesCore into a static library, then the app's views with
# Scripts/screenshot.swift in place of the @main file, into an app with its own
# bundle ID. The capture app points RELEASES_STORE at an empty file, so your
# project list and the app's settings stay untouched.
# Usage: ./Scripts/screenshot.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
BUILD="$ROOT/.build/screenshot"
APP="$BUILD/Releases Screenshot.app"
TARGET="$(uname -m)-apple-macos14.0"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" docs
swiftc -O -swift-version 6 -parse-as-library -target "$TARGET" -module-name ReleasesCore \
  -emit-library -static -emit-module -emit-module-path "$BUILD/ReleasesCore.swiftmodule" \
  -o "$BUILD/libReleasesCore.a" Sources/ReleasesCore/*.swift
find Sources/ReleasesApp -name '*.swift' ! -exec grep -q '^@main' {} \; -exec \
  swiftc -O -swift-version 6 -parse-as-library -target "$TARGET" -I "$BUILD" -L "$BUILD" -lReleasesCore \
  -o "$APP/Contents/MacOS/Screenshot" Scripts/screenshot.swift {} +

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Screenshot</string>
  <key>CFBundleIdentifier</key>
  <string>com.flaviocopes.releases.screenshot</string>
  <key>CFBundleName</key>
  <string>Releases</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
open -n "$APP" --args "$ROOT/docs" -AppleLocale en_US -AppleLanguages '(en)' -AppleShowScrollBars WhenScrolling
sleep 1
while pgrep -f "Releases Screenshot.app/Contents/MacOS" >/dev/null; do sleep 1; done
ls -la docs/screenshot-*.png
