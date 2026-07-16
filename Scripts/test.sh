#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/Scripts/check-architecture.sh"
xcrun swift-format lint --strict --recursive Sources Tests
xcodegen generate
xcodebuild test \
  -quiet \
  -project Cipherleaf.xcodeproj \
  -scheme Cipherleaf \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO
