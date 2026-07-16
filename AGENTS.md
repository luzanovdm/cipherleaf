# Repository instructions

## Product boundary

Cipherleaf is a standalone, public, product-neutral macOS application. Do not
add organization-specific names, paths, hosts, secrets, policies, examples, or
deployment assumptions.

## Architecture

- Preserve one-way dependencies:
  `Domain ← Application ← Infrastructure`.
- The app target may compose all frameworks but must not move domain or
  infrastructure logic into SwiftUI views.
- Place feature UI and facades in `Sources/Cipherleaf/Domains/<Domain>`.
- Place window-level composition in `Sources/Cipherleaf/Pages`.
- Do not create generic `Views`, `Helpers`, `Utils`, or `Managers`
  directories.
- Keep `DocumentSession` private behind domain facades.
- Keep subprocess construction inside
  `Sources/CipherleafInfrastructure/Process`.

## Security

- Never write decrypted temporary files.
- Never place secret values in command arguments, logs, alerts, diagnostics,
  snapshots, or test output.
- Never add clipboard integration for secret values.
- Keep native age identities outside the app and repository.
- Preserve existing SOPS recipient metadata during normal saves.
- Keep encrypted installation same-directory, atomic, and mode `0600`.
- Use synthetic values only in tests, screenshots, issues, and documentation.

## UI

- Use native SwiftUI and AppKit conventions.
- Cover empty, loading, error, and success states.
- Keep keyboard commands and accessibility labels intact.
- Use Observation rather than `ObservableObject` and `@Published`.
- The Icon Composer document is the only app-icon source.

## Validation

Run before every pull request:

```sh
Scripts/test.sh
shellcheck Scripts/*.sh
actionlint .github/workflows/*.yml
```

Do not commit the generated Xcode project or build products.
