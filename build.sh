#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/DogDesktopPet.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
MODULE_CACHE="$BUILD_DIR/module-cache"

mkdir -p "$MACOS" "$RESOURCES" "$MODULE_CACHE"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT"/Resources/* "$RESOURCES"/

swiftc \
  -parse-as-library \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "$MODULE_CACHE" \
  -O \
  -framework Cocoa \
  -framework QuartzCore \
  "$ROOT/Sources/DogDesktopPet.swift" \
  -o "$MACOS/DogDesktopPet"

codesign --force --deep --sign - "$APP"
xattr -cr "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/DogDesktopPet.zip"

echo "Built: $APP"
echo "Zip:   $BUILD_DIR/DogDesktopPet.zip"
