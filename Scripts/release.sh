#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-}"
TEAM_ID="${TEAM_ID:-}"
RELEASE_TAG="${TAG:-v$VERSION}"
NOTARY_TIMEOUT_SECONDS="${NOTARY_TIMEOUT_SECONDS:-1800}"
NOTARY_POLL_SECONDS="${NOTARY_POLL_SECONDS:-15}"
WORK_DIRECTORY="$ROOT/.build/public-release-$VERSION"
ARCHIVE="$WORK_DIRECTORY/Cipherleaf.xcarchive"
SIGNED_EXPORT="$WORK_DIRECTORY/signed"
OUTPUT_DIRECTORY="$ROOT/.build/release"
FINAL_ARCHIVE="$OUTPUT_DIRECTORY/Cipherleaf-$VERSION-macos.zip"
CHECKSUM="$FINAL_ARCHIVE.sha256"

if [[ -z "$VERSION" || -z "$TEAM_ID" ]]; then
  echo "Usage: VERSION=1.0.0 TEAM_ID=ABCDEFGHIJ Scripts/release.sh" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9._-]+)?$ ]]; then
  echo "VERSION must be a release version such as 1.0.0 or 1.0.0-rc.1" >&2
  exit 1
fi

if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "TEAM_ID must contain exactly 10 uppercase letters or digits" >&2
  exit 1
fi

if [[ ! "$NOTARY_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "NOTARY_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 1
fi

if [[ ! "$NOTARY_POLL_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "NOTARY_POLL_SECONDS must be a positive integer" >&2
  exit 1
fi

PROJECT_VERSION="$(
  awk '/^[[:space:]]+MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' \
    "$ROOT/project.yml"
)"

if [[ "$PROJECT_VERSION" != "$VERSION" ]]; then
  echo "VERSION $VERSION does not match project.yml MARKETING_VERSION $PROJECT_VERSION" >&2
  exit 1
fi

if [[ "${ALLOW_DIRTY:-0}" != "1" ]] && \
  [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "Refusing to release from a dirty worktree" >&2
  exit 1
fi

if [[ "${ALLOW_UNTAGGED:-0}" != "1" ]] && \
  ! git -C "$ROOT" tag --points-at HEAD | grep -Fxq "$RELEASE_TAG"; then
  echo "HEAD must have the release tag $RELEASE_TAG" >&2
  exit 1
fi

for tool in awk codesign ditto git grep plutil shasum sleep spctl unzip xcodebuild xcodegen xcrun; do
  if ! command -v "$tool" >/dev/null; then
    echo "Required tool is unavailable: $tool" >&2
    exit 1
  fi
done

create_export_options() {
  local destination="$1"
  local path="$2"

  plutil -create xml1 "$path"
  plutil -insert destination -string "$destination" "$path"
  plutil -insert method -string developer-id "$path"
  plutil -insert signingStyle -string automatic "$path"
  plutil -insert teamID -string "$TEAM_ID" "$path"
}

cd "$ROOT"

"$ROOT/Scripts/check-architecture.sh"
xcodegen generate

rm -rf "$WORK_DIRECTORY"
mkdir -p "$WORK_DIRECTORY" "$OUTPUT_DIRECTORY"

xcodebuild archive \
  -quiet \
  -project Cipherleaf.xcodeproj \
  -scheme Cipherleaf \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

EXPORT_OPTIONS="$WORK_DIRECTORY/export-options.plist"
UPLOAD_OPTIONS="$WORK_DIRECTORY/upload-options.plist"
create_export_options export "$EXPORT_OPTIONS"
create_export_options upload "$UPLOAD_OPTIONS"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$SIGNED_EXPORT" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

SIGNED_APP="$SIGNED_EXPORT/Cipherleaf.app"
codesign --verify --deep --strict --verbose=2 "$SIGNED_APP"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$WORK_DIRECTORY/notary-upload" \
  -exportOptionsPlist "$UPLOAD_OPTIONS" \
  -allowProvisioningUpdates

STAPLER_LOG="$WORK_DIRECTORY/stapler.log"
NOTARY_DEADLINE=$((SECONDS + NOTARY_TIMEOUT_SECONDS))
TICKET_READY=0

while ((SECONDS < NOTARY_DEADLINE)); do
  if xcrun stapler staple "$SIGNED_APP" >"$STAPLER_LOG" 2>&1; then
    TICKET_READY=1
    break
  fi

  sleep "$NOTARY_POLL_SECONDS"
done

if [[ "$TICKET_READY" != "1" ]]; then
  cat "$STAPLER_LOG" >&2
  echo "Notarization did not finish within $NOTARY_TIMEOUT_SECONDS seconds" >&2
  exit 1
fi

APP="$SIGNED_APP"
SIGNATURE="$(codesign -dv --verbose=4 "$APP" 2>&1)"

if [[ "$SIGNATURE" != *"Authority=Developer ID Application:"* ]]; then
  echo "Exported app is not signed with Developer ID Application" >&2
  exit 1
fi

if [[ "$SIGNATURE" != *"TeamIdentifier=$TEAM_ID"* ]]; then
  echo "Exported app was signed by an unexpected Apple team" >&2
  exit 1
fi

test "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" = "$VERSION"
test "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" = "app.cipherleaf.mac"
test "$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")" = "15.0"
test -f "$APP/Contents/Resources/Cipherleaf.icns"
test -f "$APP/Contents/Resources/Assets.car"
test -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

rm -f "$FINAL_ARCHIVE" "$CHECKSUM"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$FINAL_ARCHIVE"
unzip -tq "$FINAL_ARCHIVE"
shasum -a 256 "$FINAL_ARCHIVE" | \
  awk -v name="$(basename "$FINAL_ARCHIVE")" '{ print $1 "  " name }' \
    >"$CHECKSUM"

echo "Created $FINAL_ARCHIVE"
echo "Created $CHECKSUM"
