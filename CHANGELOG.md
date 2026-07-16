# Changelog

All notable changes to Cipherleaf will be documented here.

The project follows semantic versioning after the first public release.

## 1.0.0 - Unreleased

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
