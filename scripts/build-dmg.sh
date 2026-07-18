#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="Password Bridge"
EXECUTABLE="ApplePasswordBridge"
INFO_PLIST="$ROOT/Resources/Info.plist"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
BUILD_ROOT="${TMPDIR:-/tmp}/password-bridge-release-$UID"
DMG="$ROOT/dist/$APP_NAME-$VERSION-universal.dmg"
STAGE="$BUILD_ROOT/stage/$APP_NAME.app"
DMG_ROOT="$BUILD_ROOT/dmg"

build_arch() {
    local arch="$1"
    local scratch="$BUILD_ROOT/$arch"
    swift build \
        -c release \
        --triple "$arch-apple-macosx14.0" \
        --scratch-path "$scratch" \
        --disable-sandbox
}

cd "$ROOT"
build_arch arm64
build_arch x86_64

rm -rf "$BUILD_ROOT/stage" "$BUILD_ROOT/dmg" "$DMG"
mkdir -p "$STAGE/Contents/MacOS" "$DMG_ROOT"
cp "$INFO_PLIST" "$STAGE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$STAGE/Contents/Info.plist"

lipo -create \
    "$BUILD_ROOT/arm64/arm64-apple-macosx/release/$EXECUTABLE" \
    "$BUILD_ROOT/x86_64/x86_64-apple-macosx/release/$EXECUTABLE" \
    -output "$STAGE/Contents/MacOS/$EXECUTABLE"
xattr -cr "$STAGE"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "warning: Developer ID not configured; using ad-hoc signing"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$STAGE"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGN_IDENTITY" \
        --identifier "$BUNDLE_ID" \
        "$STAGE"
fi

codesign --verify --deep --strict --verbose=2 "$STAGE"
COPYFILE_DISABLE=1 cp -R "$STAGE" "$DMG_ROOT/$APP_NAME.app"
xattr -cr "$DMG_ROOT/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        echo "error: notarization requires DEVELOPER_ID_APPLICATION" >&2
        exit 1
    fi
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

echo "$DMG"
