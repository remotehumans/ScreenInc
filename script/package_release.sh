#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# SIGNING_IDENTITY must be a Developer ID Application identity for distribution.
IDENTITY="${SIGNING_IDENTITY:--}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Assets/Info.plist)
APP="$PWD/dist/ScreenInc.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in arm64 x86_64; do
  swift build --build-system native --scratch-path ".build/release-$ARCH" -c release --triple "$ARCH-apple-macosx14.0" --disable-sandbox
 done
ARM=$(swift build --build-system native --scratch-path .build/release-arm64 -c release --triple arm64-apple-macosx14.0 --show-bin-path)
INTEL=$(swift build --build-system native --scratch-path .build/release-x86_64 -c release --triple x86_64-apple-macosx14.0 --show-bin-path)
lipo -create "$ARM/ScreenInk" "$INTEL/ScreenInk" -output "$APP/Contents/MacOS/ScreenInk"
cp Assets/Info.plist "$APP/Contents/Info.plist"
cp Assets/ScreenInc.icns "$APP/Contents/Resources/ScreenInc.icns"
if [[ "$IDENTITY" == '-' ]]; then
  codesign --force --sign - "$APP"
  SUFFIX=preview
else
  codesign --force --options runtime --timestamp --entitlements Assets/Release.entitlements --sign "$IDENTITY" "$APP"
  SUFFIX=signed
fi
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
lipo "$APP/Contents/MacOS/ScreenInk" -verify_arch arm64 x86_64
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/ScreenInc.app"
ln -s /Applications "$STAGE/Applications"
cp docs/INSTALL.md "$STAGE/Installation.txt"
DMG="$PWD/dist/ScreenInc-$VERSION-universal-$SUFFIX.dmg"
hdiutil create -volname ScreenInc -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [[ "$IDENTITY" != '-' ]]; then
  codesign --timestamp --sign "$IDENTITY" "$DMG"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
  fi
fi
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
printf 'Packaged: %s\n' "$DMG"
