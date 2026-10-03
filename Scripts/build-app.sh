#!/bin/sh
# Builds a universal (Apple silicon and Intel) dist/Releases.app.
# Signs with Flavio's Developer ID when the certificate is in the keychain, ad-hoc everywhere else.
# The version comes from Commands.version in Sources/ReleasesCLI/Commands.swift.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/Releases.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_SOURCE="$ROOT/Assets/AppIcon.png"
ICONSET="$ROOT/.build/AppIcon.iconset"

cd "$ROOT"
VERSION=$(sed -n 's/^ *static let version = "\(.*\)"$/\1/p' Sources/ReleasesCLI/Commands.swift)
swift build -c release --arch arm64 --arch x86_64 --product ReleasesApp

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp ".build/apple/Products/Release/ReleasesApp" "$MACOS/Releases"

ICON_KEY=""
if [ -f "$ICON_SOURCE" ]; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
  ICON_KEY="<key>CFBundleIconFile</key>
  <string>AppIcon</string>"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Releases</string>
  <key>CFBundleExecutable</key>
  <string>Releases</string>
  <key>CFBundleIdentifier</key>
  <string>com.flaviocopes.releases</string>
  $ICON_KEY
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Releases</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>com.flaviocopes.releases</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>releases</string>
      </array>
    </dict>
  </array>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

IDENTITY=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: Flavio Copes \(DGFKNTAG99\)"/ { print $2; exit }')
if [ -n "$IDENTITY" ]; then
  SIGNATURE="Developer ID"
  find "$APP" -type f | while IFS= read -r file; do
    case $(file -b "$file") in
      *Mach-O*) codesign --force --options runtime --timestamp --sign "$IDENTITY" "$file" ;;
    esac
  done
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  SIGNATURE="ad-hoc"
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

# Registers the releases:// links, so 'releases open' works before the app is ever opened.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built $APP $VERSION for $(lipo -archs "$MACOS/Releases"), $SIGNATURE signed"
echo "$APP"
