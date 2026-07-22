#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP="$DERIVED_DATA/Build/Products/Release/DogDesktopPet.app"

xcodebuild \
  -project "$ROOT/DogDesktopPet.xcodeproj" \
  -scheme DogDesktopPet \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build

ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/DogDesktopPet.zip"

echo "Built: $APP"
echo "Zip:   $BUILD_DIR/DogDesktopPet.zip"
