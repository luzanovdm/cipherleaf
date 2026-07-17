# Security model

Cipherleaf is a local GUI around trusted, user-installed SOPS and age tools.
SOPS remains responsible for cryptography and encrypted file compatibility.
Cipherleaf is responsible for limiting plaintext exposure, validating the
selected identity and recipient metadata, and replacing ciphertext safely.

## What Cipherleaf protects

- It does not write a decrypted working file.
- It does not place secret values in process arguments.
- It does not display identity contents, provide a secret-copy action, or write
  secret values to the clipboard automatically. A user can still invoke
  standard macOS editing commands while a value is explicitly revealed.
- It does not include values in alerts, save reviews, diagnostics, or logs.
- It checks the encrypted file revision before saving.
- It checks that the public age recipients are unchanged by the edit.
- It verifies the complete decrypted staging document before installation.
- It installs ciphertext with mode `0600` using a same-directory rename.

## What Cipherleaf does not protect

Cipherleaf cannot make a compromised Mac safe. A process with access to the
user session may inspect memory, input events, the selected identity file, or
the external tools. Swift and Foundation do not guarantee zeroization of
copied strings and collection storage. Closing a document drops app
references, but it cannot promise forensic erasure from RAM, swap, crash
reports, accessibility tools, or operating-system text input state.

Do not use Cipherleaf in a recorded, remotely shared, or untrusted desktop
session. Rotate affected material if plaintext or a private identity may have
been exposed.

## Plaintext flow

Opening a document runs SOPS with an explicit executable path and a restricted
environment. Cipherleaf reads a bounded, no-follow ciphertext snapshot and
sends those exact bytes to SOPS through standard input. SOPS writes JSON to a
pipe, and Cipherleaf decodes that stream into an in-memory document tree.

During a save, each changed value is encoded in memory and sent to
`sops set --value-stdin`. Removed paths use `sops unset`. A value is never
placed in the argument vector. Command stdout and stderr are captured, bounded,
and not logged. Expected diagnostic stderr is sanitized; secret-processing
commands use redacted failures. Each invocation runs in its own process group,
so cancellation and timeout termination also cover descendants that retain a
pipe. SOPS version checks are disabled to keep diagnostics local.

SOPS may normalize YAML and dotenv while applying these operations, including
removing comments. Cipherleaf conservatively detects comment markers and warns
before the save; it does not attempt to parse and reconstruct comments around
encrypted nodes.

## Identity handling

Cipherleaf stores a security-scoped identity bookmark in the login Keychain.
The bookmark is device-only and available only while the device is unlocked.
The identity itself is not imported or copied. Up to eight recent encrypted
document paths are stored in local preferences; file contents are not.

Before use, the identity must be:

- a regular file rather than a symbolic link;
- at most 1 MB;
- inaccessible to group and other users, normally mode `0600`.

Cipherleaf resolves and validates `age-keygen`, invokes `age-keygen -y`, and
compares the derived public recipients with SOPS metadata. Identity derivation
errors are redacted.

For SOPS decryption and editing, Cipherleaf sets `SOPS_AGE_KEY_FILE` to the
selected path and `SOPS_DECRYPTION_ORDER=age`. It does not inherit the user's
`PATH` or existing SOPS key environment variables into the child process.

## Tool trust

Configured tools are resolved to their real path. Cipherleaf rejects a tool
that is not executable, is owned by an unrelated account, or is writable by a
group or other users. Auto-detection checks common package-manager locations
before other directories from the parent app's `PATH`.

These checks reduce accidental execution of a replaced binary. They do not
verify a binary signature or package provenance. Install SOPS and age from a
source you trust.

## Save transaction

1. Re-read the encrypted target and compare its SHA-256 revision with the
   revision opened by the user.
2. Parse and compare its current public recipients with the original set.
3. Create a unique same-directory staging file with `O_EXCL`, `O_CLOEXEC`, and
   mode `0600`.
4. Apply only the requested set and unset operations to the ciphertext staging
   file.
5. Decrypt the staging file through a pipe.
6. Compare the complete decrypted tree with the intended in-memory tree.
7. Parse the staging metadata and verify that the recipients are unchanged.
8. Re-read the target and compare its SHA-256 revision again, narrowing the
   window for concurrent external edits during the SOPS operations.
9. Re-open the staging file without following links, compare it with the
   verified ciphertext, reassert mode `0600`, and `fsync` it.
10. Rename the staging file over the target and `fsync` the directory.

Before the rename, any failure leaves the original target in place. If the
rename succeeds but directory synchronization fails, the new encrypted file
has already been installed but its crash durability is uncertain. Cipherleaf
reports this case explicitly and requires a reload before further edits.

Cipherleaf does not keep an application-level backup beside the encrypted
file. Source control or another ciphertext backup remains the recovery
mechanism.

## `.sops.yaml`

The Security inspector reports the nearest ancestor `.sops.yaml` when one
exists. Cipherleaf does not use it to recreate or rotate recipients during a
normal save. The existing encrypted document's metadata is authoritative.

Recipient changes remain an explicit SOPS administration task outside the
editor.

## App Sandbox and network access

App Sandbox is disabled because Cipherleaf executes user-installed command-line
tools and opens user-selected files outside its container. Hardened Runtime is
enabled for signed builds.

Cipherleaf contains no network client. SOPS may support remote key services,
but Cipherleaf restricts decryption order to native age, accepts only
documents whose metadata contains native age recipients exclusively, and
disables SOPS version checks.
