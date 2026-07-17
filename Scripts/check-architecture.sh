#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "Architecture check failed: $1" >&2
  exit 1
}

if find Sources -type d \
  \( -name Views -o -name Helpers -o -name Utils -o -name Managers \) \
  -print -quit |
  grep -q .
then
  fail "generic Views, Helpers, Utils, and Managers directories are forbidden"
fi

for directory in Sources/Cipherleaf/*/; do
  name="$(basename "$directory")"
  case "$name" in
    App | Core | Domains | Pages) ;;
    *) fail "unexpected app-layer directory Sources/Cipherleaf/$name" ;;
  esac
done

if rg -n \
  '^import (AppKit|Security|SwiftUI|CipherleafApplication|CipherleafInfrastructure)$' \
  Sources/CipherleafDomain
then
  fail "the domain layer imports UI, platform security, application, or infrastructure"
fi

if rg -n \
  '^import (AppKit|Security|SwiftUI|CipherleafInfrastructure)$' \
  Sources/CipherleafApplication
then
  fail "the application layer imports UI or infrastructure"
fi

if rg -n '^import (AppKit|SwiftUI)$' Sources/CipherleafInfrastructure; then
  fail "the infrastructure layer imports UI frameworks"
fi

if rg -n \
  '\b(Process|posix_spawn|fork|exec[lv][a-z]*|system|popen)\s*\(' \
  Sources \
  --glob '*.swift' \
  --glob '!Sources/CipherleafInfrastructure/Process/**'
then
  fail "subprocess creation must stay inside CipherleafInfrastructure/Process"
fi

if rg -n \
  '\b(fatalError|preconditionFailure|print|debugPrint|NSLog)\s*\(|try\s*!|as\s*!' \
  Sources \
  --glob '*.swift'
then
  fail "unsafe termination, force operations, or direct console logging found"
fi

if rg -n '\b(ObservableObject|@Published)\b' Sources --glob '*.swift'; then
  fail "legacy observation APIs found; use Observation"
fi

if rg -n \
  '\b(NSPasteboard|URLSession|NSURLConnection|NWConnection|NWListener|Logger|OSLog|os_log)\b' \
  Sources \
  --glob '*.swift'
then
  fail "clipboard writes, network clients, and application logging are forbidden"
fi

if rg -n \
  '\b(NSTemporaryDirectory|mkstemp|mkdtemp|tmpfile)\b|\.temporaryDirectory\b' \
  Sources \
  --glob '*.swift'
then
  fail "temporary-file APIs are forbidden in product code"
fi

session_leaks="$(
  rg -n '^[[:space:]]*(weak[[:space:]]+)?(let|var)[[:space:]]+session:[[:space:]]+DocumentSession' \
    Sources/Cipherleaf \
    --glob '*.swift' |
    rg -v 'private' || true
)"
if [[ -n "$session_leaks" ]]; then
  echo "$session_leaks" >&2
  fail "DocumentSession must remain private behind domain facades"
fi

while IFS= read -r file; do
  line_count="$(wc -l < "$file" | tr -d ' ')"
  if ((line_count > 400)); then
    fail "$file has $line_count lines; split it along domain responsibilities"
  fi
done < <(rg --files Sources Tests -g '*.swift')

if [[ ! -f Resources/Cipherleaf.icon/icon.json ]]; then
  fail "the Icon Composer document is missing"
fi

icon_group_count="$(
  plutil -extract groups raw -o - Resources/Cipherleaf.icon/icon.json 2>/dev/null
)" || fail "the Icon Composer manifest is not valid"

if ! [[ "$icon_group_count" =~ ^[0-9]+$ ]] || ((icon_group_count == 0)); then
  fail "the Icon Composer manifest must contain at least one layer group"
fi

declare -a icon_assets=()

for ((group_index = 0; group_index < icon_group_count; group_index += 1)); do
  layer_count="$(
    plutil \
      -extract "groups.${group_index}.layers" \
      raw \
      -o - \
      Resources/Cipherleaf.icon/icon.json \
      2>/dev/null
  )" || fail "Icon Composer group $group_index has no valid layers"

  if ! [[ "$layer_count" =~ ^[0-9]+$ ]] || ((layer_count == 0)); then
    fail "Icon Composer group $group_index must contain at least one layer"
  fi

  for ((layer_index = 0; layer_index < layer_count; layer_index += 1)); do
    image_name="$(
      plutil \
        -extract "groups.${group_index}.layers.${layer_index}.image-name" \
        raw \
        -o - \
        Resources/Cipherleaf.icon/icon.json \
        2>/dev/null
    )" || fail "Icon Composer layer $group_index/$layer_index has no image-name"

    if [[ ! "$image_name" =~ ^[A-Za-z0-9._-]+[.]svg$ ]]; then
      fail "Icon Composer layer $group_index/$layer_index has an unsafe SVG name"
    fi

    asset_path="Resources/Cipherleaf.icon/Assets/$image_name"
    if [[ ! -f "$asset_path" ]]; then
      fail "Icon Composer layer asset is missing: $asset_path"
    fi

    if ! xmllint --noout "$asset_path" 2>/dev/null; then
      fail "Icon Composer layer asset is not valid XML: $asset_path"
    fi

    if rg -q '<text([[:space:]>])' "$asset_path"; then
      fail "Icon Composer text must be converted to vector outlines: $asset_path"
    fi

    for existing_asset in "${icon_assets[@]-}"; do
      if [[ "$existing_asset" == "$image_name" ]]; then
        fail "Icon Composer layer asset is referenced more than once: $image_name"
      fi
    done
    icon_assets+=("$image_name")
  done
done

while IFS= read -r asset_path; do
  asset_name="$(basename "$asset_path")"
  asset_is_referenced=false

  for referenced_asset in "${icon_assets[@]}"; do
    if [[ "$referenced_asset" == "$asset_name" ]]; then
      asset_is_referenced=true
      break
    fi
  done

  if [[ "$asset_is_referenced" == false ]]; then
    fail "unreferenced Icon Composer layer asset found: $asset_path"
  fi
done < <(find Resources/Cipherleaf.icon/Assets -type f -name '*.svg' | sort)

if find Resources -type d -name '*.xcassets' -print -quit | grep -q .; then
  fail "legacy asset-catalog app icons are forbidden; use the Icon Composer document"
fi

if ! rg -q 'Resources/Cipherleaf\.icon' project.yml; then
  fail "the Icon Composer document is not included in project.yml"
fi

if rg -n 'AGE-SECRET-KEY-' Tests --glob '!ProcessExecutorTests.swift'; then
  fail "a private age identity marker is present in tests"
fi

while IFS= read -r fixture; do
  if ! rg -qi 'synthetic|fixture|example' "$fixture"; then
    fail "$fixture is not clearly marked as synthetic"
  fi
done < <(find Tests/Fixtures -type f)

echo "Architecture and security guardrails passed."
