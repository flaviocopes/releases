#!/bin/sh
# Builds the universal app, checks the signature survives zipping, and writes
# dist/Releases-<version>.zip for a GitHub release.
# Usage: ./Scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/^ *static let version = "\(.*\)"$/\1/p' Sources/ReleasesCLI/Commands.swift)
APP="$ROOT/dist/Releases.app"
ZIP="$ROOT/dist/Releases-$VERSION.zip"
CHECK=$(mktemp -d)

rm -f "$ZIP"
./Scripts/build-app.sh >/dev/null

lipo "$APP/Contents/MacOS/Releases" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/Releases.app"
rm -rf "$CHECK"

echo "$ZIP"
shasum -a 256 "$ZIP"
