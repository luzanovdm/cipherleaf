# Changelog

All notable changes to Cipherleaf will be documented here.

The project follows semantic versioning after the first public release.

## 1.0.1 - 2026-07-17

### Fixed

- Accept native post-quantum hybrid age recipients and multi-identity files.
- Treat dotenv keys as flat names, including literal dots, and reject SOPS
  metadata paths before mutation.
- Safely handle SOPS path-syntax edge cases and keep unaddressable values
  read-only.
- Preserve array semantics when elements are removed and when arrays become
  empty.
- Clear stale save review and validation state after undo or redo.
- Derive package checks from project versions and verify universal release
  binaries.

## 1.0.0 - 2026-07-17

### Added

- Native macOS editor for existing SOPS documents encrypted with native age
  recipients.
- YAML, JSON, and dotenv support.
- Concealed scalar editing with automatic concealment on inactivity.
- Add, edit, rename, remove, undo, redo, reload, and redacted save review.
- Public recipient inspection and identity-match validation.
- Patch-based SOPS saves through stdin with full-document verification.
- Save-time warnings when SOPS may remove YAML or dotenv comments.
- External modification detection and atomic mode-`0600` installation.
- Tool diagnostics, recent documents, Keychain bookmarks, and secure file
  validation.
- Domain-oriented architecture, automated guardrails, tests, CI, and an Icon
  Composer app icon.
- Universal Developer ID-signed and Apple-notarized release archive.
