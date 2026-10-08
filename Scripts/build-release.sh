#!/bin/sh
# Builds the universal app, checks the signature survives zipping, and writes
# dist/Releases-Manager-<version>.zip for a GitHub release. Notarizes when the app is
# Developer ID signed (needs a notarytool keychain profile named "notary").
# Usage: ./Scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/^ *static let version = "\(.*\)"$/\1/p' Sources/ReleasesCLI/Commands.swift)
APP="$ROOT/dist/Releases Manager.app"
ZIP="$ROOT/dist/Releases-Manager-$VERSION.zip"
CHECK=$(mktemp -d)

cleanup() {
  rm -rf "$CHECK"
}
trap cleanup EXIT

rm -f "$ZIP"
./Scripts/build-app.sh >/dev/null

TEAM=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
if [ "$TEAM" = "DGFKNTAG99" ]; then
  SIGNATURE="Developer ID"
else
  SIGNATURE="ad-hoc"
fi

lipo "$APP/Contents/MacOS/Releases Manager" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ "$SIGNATURE" = "Developer ID" ]; then
  result=$(xcrun notarytool submit "$ZIP" --keychain-profile notary --wait --output-format json)
  status=$(printf '%s' "$result" | plutil -extract status raw -o - -)
  if [ "$status" != "Accepted" ]; then
    echo "$result" >&2
    submission_id=$(printf '%s' "$result" | plutil -extract id raw -o - -)
    xcrun notarytool log "$submission_id" --keychain-profile notary >&2
    exit 1
  fi
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
fi

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/Releases Manager.app"

echo "Release zip signed with $SIGNATURE"
echo "$ZIP"
shasum -a 256 "$ZIP"
