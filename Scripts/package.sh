#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT/.build/ReleaseDerivedData"
OUTPUT_DIRECTORY="$ROOT/.build/release"
PROJECT_VERSION="$(
  awk '/^[[:space:]]+MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' \
    "$ROOT/project.yml"
)"
PROJECT_BUILD="$(
  awk '/^[[:space:]]+CURRENT_PROJECT_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' \
    "$ROOT/project.yml"
)"
VERSION="${VERSION:-$PROJECT_VERSION}"

cd "$ROOT"

if [[ ! "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$ ]]; then
  echo "VERSION contains unsafe archive-name characters: $VERSION" >&2
  exit 1
fi

"$ROOT/Scripts/check-architecture.sh"
xcodegen generate
rm -rf "$DERIVED_DATA"
mkdir -p "$OUTPUT_DIRECTORY"

xcodebuild build \
  -quiet \
  -project Cipherleaf.xcodeproj \
  -scheme Cipherleaf \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO

APP="$DERIVED_DATA/Build/Products/Release/Cipherleaf.app"
ARCHIVE="$OUTPUT_DIRECTORY/Cipherleaf-$VERSION-unsigned.zip"
BINARY="$APP/Contents/MacOS/Cipherleaf"
ARCHITECTURES="$(lipo -archs "$BINARY")"

for architecture in arm64 x86_64; do
  if [[ " $ARCHITECTURES " != *" $architecture "* ]]; then
    echo "Release binary is missing the $architecture architecture" >&2
    exit 1
  fi
done

test -f "$APP/Contents/Resources/Cipherleaf.icns"
test -f "$APP/Contents/Resources/Assets.car"
test -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
test "$(plutil -extract CFBundleIconName raw "$APP/Contents/Info.plist")" = "Cipherleaf"
test "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" = "$PROJECT_VERSION"
test "$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")" = "$PROJECT_BUILD"
test "$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")" = "15.0"

rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
unzip -tq "$ARCHIVE"

echo "Created $ARCHIVE"
