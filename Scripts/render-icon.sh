#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_TOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
OUTPUT="${1:-$ROOT/.build/icon-preview.png}"

if [[ ! -x "$ICON_TOOL" ]]; then
  echo "Icon Composer is not installed in /Applications." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
"$ICON_TOOL" "$ROOT/Resources/Cipherleaf.icon" \
  --export-image \
  --output-file "$OUTPUT" \
  --platform macOS \
  --rendition Default \
  --width 1024 \
  --height 1024 \
  --scale 1 \
  --design-generation 26

echo "Rendered $OUTPUT"
