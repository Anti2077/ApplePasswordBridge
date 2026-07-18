#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/Password Bridge.app"
STAGE="${TMPDIR:-/tmp}/password-bridge-build-$UID/Password Bridge.app"
CONTENTS="$STAGE/Contents"
BIN_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

cd "$ROOT"
swift build -c release --disable-sandbox
BIN_PATH="$(swift build -c release --disable-sandbox --show-bin-path)/ApplePasswordBridge"

rm -rf "${STAGE:h}"
mkdir -p "$BIN_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$BIN_DIR/ApplePasswordBridge"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

codesign --force --sign - --identifier com.anti.ApplePasswordBridge "$STAGE"
rm -rf "$APP"
mkdir -p "${APP:h}"
COPYFILE_DISABLE=1 cp -R "$STAGE" "$APP"
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
