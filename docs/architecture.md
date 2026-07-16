# Architecture

Cipherleaf uses domain-driven source placement without forcing UI concepts
into a generic presentation folder. The design keeps cryptographic process
execution and filesystem mutation behind application ports.

## Framework boundaries

### `CipherleafDomain`

Pure document and encryption concepts:

- secret values and paths;
- document mutations and deterministic patches;
- SOPS file formats;
- public native age recipients.

The domain layer does not know about SwiftUI, AppKit, Keychain, subprocesses,
or filesystems.

### `CipherleafApplication`

Use-case orchestration:

- `DocumentSession`;
- open and save request/result types;
- the `EncryptedFileClient` port;
- undo, redo, validation-independent edit history;
- redacted change preparation.

The application layer depends only on the domain layer and system-neutral
Foundation/Observation APIs.

### `CipherleafInfrastructure`

Adapters for the outside world:

- SOPS and age subprocess execution;
- tool discovery and validation;
- bounded pipe capture and cancellation;
- SOPS metadata parsing;
- Keychain bookmarks;
- filesystem inspection, revisions, and atomic installation.

Infrastructure implements the application port and contains no UI.

### `Cipherleaf`

The executable composes the frameworks and owns native macOS interaction.

- `App` creates dependencies, commands, scenes, and quit handling.
- `Core` contains app-wide platform and feedback services.
- `Domains` contains feature-owned facades and views.
- `Pages` contains window-level composition only.

## UI domains

### Workspace

Owns document and identity selection, recent documents, reload and close
coordination, and security-scoped access lifetime.

### Secrets

Owns scalar editing, selection, validation messages, redacted save review, and
edit commands.

### Security

Presents public recipient metadata, identity match status, format, and policy
discovery. It never exposes private identity contents.

### Diagnostics

Owns tool settings, tool availability, and editing preferences.

## State ownership

`DocumentSession` is the application state machine. It is private inside the
facades that expose only the capability each domain needs. SwiftUI views read
facades through Observation and do not mutate infrastructure objects.

The session keeps:

- the baseline decrypted tree;
- the current working tree;
- deterministic derived entries and patches;
- bounded undo and redo history;
- encrypted-file revision and public recipient metadata.

Closing a document clears document values, paths, recipient arrays, revisions,
and identity references held by the session.

## Save flow

```text
SwiftUI edit
    ↓
SecretsFacade
    ↓
DocumentSession creates deterministic patch
    ↓
EncryptedFileClient port
    ↓
SOPSCLIClient stages ciphertext, applies patch, verifies, installs
```

The UI never constructs SOPS commands. Infrastructure never decides how a
document edit should appear to the user.

## Automated boundaries

`Scripts/check-architecture.sh` rejects:

- generic `Views` directories;
- reversed framework imports;
- subprocess creation outside the process adapter;
- force operations and direct console logging;
- programmatic clipboard access, network clients, and application logging;
- public `DocumentSession` storage in app domains;
- oversized Swift files;
- legacy asset-catalog app icons;
- private age identity markers in tests;
- fixtures that are not visibly synthetic.
