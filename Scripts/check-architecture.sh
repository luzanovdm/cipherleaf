#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "Architecture check failed: $1" >&2
  exit 1
}

if find Sources -type d -name Views -print -quit | grep -q .; then
  fail "generic Views directories are forbidden; place UI in its owning domain or page"
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
  'Process\(' \
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
  '\b(NSPasteboard|URLSession|NWConnection|Logger|OSLog|os_log)\b' \
  Sources \
  --glob '*.swift'
then
  fail "clipboard writes, network clients, and application logging are forbidden"
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
