# User guide

## Before the first edit

Install SOPS and age:

```sh
brew install age sops
```

An age identity is the private key file created by `age-keygen`. It authorizes
decryption for its matching public X25519 (`age1…`) or post-quantum hybrid
(`age1pq1…`) recipient. The filename often ends in `.agekey`, but the name
itself is not proof that the file is an identity. Do not choose the encrypted
SOPS document, `.sops.yaml`, or another YAML file.

Use an existing native age identity. Cipherleaf does not generate, import, or
copy one. Keep the identity outside source repositories and restrict it:

```sh
chmod 600 /path/to/identity.txt
```

The identity must match at least one public native age recipient in the
encrypted document. Age plugin recipients are not currently supported.

## Open a document

1. Launch Cipherleaf.
2. Choose **Choose identity** and select the native age identity file.
3. Choose **Open document** and select an encrypted YAML, JSON, or dotenv
   document.
4. Check the Security inspector:
   - the identity says **Matches document**;
   - the expected public recipients are present;
   - the format is correct;
   - the expected `.sops.yaml` is shown when the repository has one.

The right-hand Security inspector is deliberately separate from the value
editor. It is the safety check that answers “can this identity decrypt this
document?” without revealing any secret values. Before a document is open, it
confirms that the selected file is a valid native age identity and shows the
derived public recipient. After opening a document, it also shows the format,
nearest `.sops.yaml`, document recipients, and whether the identity matches
them. Use the trailing-sidebar toolbar button to hide or show it.

The app stores a device-only security-scoped bookmark for the selected
identity and up to eight recent document paths in local preferences. It does
not copy the identity or document contents into its own storage. Remove a
recent path from its context menu when you no longer want it listed. After
closing the document, use the identity row's context menu to remove its
bookmark.

If you choose a different identity while a clean document is open, Cipherleaf
reopens and validates the document with that identity. If unsaved edits exist,
it asks before discarding them.

## Edit values

Select a path in the middle column. Values are concealed by default.

- Use **Reveal** only while you need to inspect or edit a value.
- Change the scalar type from the type picker when necessary.
- Use **Add value** to add a scalar at a new path.
- Use the editor actions below the value to rename or remove it.
- Use standard **Undo** and **Redo** commands.

Revealed values conceal themselves after the interval selected in Settings and
immediately when the app becomes inactive. Cipherleaf intentionally has no
copy-secret button and never writes a value to the clipboard automatically.
Standard macOS editing commands remain available while a value is explicitly
revealed.

Only scalar leaves are editable. Objects and arrays are represented through
their child paths.

YAML and JSON use dots to separate nested object keys when adding a value.
Dotenv documents are always flat: `SERVICE.TOKEN` is one key whose name
contains a dot. SOPS metadata names are reserved and cannot be added or
renamed from Cipherleaf.

SOPS cannot safely address every possible YAML or JSON key through its
`set`/`unset` path syntax. If an existing key contains an opening bracket, or
contains both single and double quotes, Cipherleaf keeps the value readable
but disables mutation controls for that path instead of risking an edit to a
different key.

## Save

1. Choose **Save**.
2. Review the path-only change list. Values are never shown in this sheet.
3. Confirm the encrypted save.

If the encrypted YAML or dotenv source contains comment lines, the review
shows a warning. SOPS may remove those comments while applying `set`/`unset`;
move operational notes to documentation before continuing.

Cipherleaf checks that the encrypted file has not changed since it was opened,
patches a ciphertext staging copy, decrypts the staging copy, compares the
whole result, checks recipients again, and installs the ciphertext atomically.

Commit the resulting encrypted file through the repository's normal review
process.

## Reload or discard

Use **Reload from Disk** to pick up external ciphertext changes. If in-memory
edits exist, Cipherleaf asks before discarding them.

Closing the last window does not quit Cipherleaf or discard the in-memory
session; reopen it from the Dock or use **Window → Cipherleaf**. Quitting the
app with unsaved edits requires an explicit discard decision.

## Settings and diagnostics

Cipherleaf checks common Homebrew locations automatically. If SOPS or
`age-keygen` is elsewhere, choose the executable in Settings. Diagnostics show
the resolved public path and version.

Cipherleaf rejects executable files that are writable by a group or other
users, or owned by an unrelated account.

## Common errors

### Identity permissions are too broad

Run:

```sh
chmod 600 /path/to/identity.txt
```

Then select the identity again.

### Selected file is not an identity

Choose the private key file created by `age-keygen`, not the SOPS document or
its `.sops.yaml` policy. Cipherleaf verifies the file before remembering it.

### Identity does not match

The chosen private identity does not correspond to any native age recipient
in the document. Select the correct identity. Recipient administration is an
explicit SOPS operation outside Cipherleaf.

### File changed on disk

Another process changed the ciphertext after it was opened. Reload, repeat the
edit, and save again.

### Recipient metadata changed unexpectedly

Stop and inspect the ciphertext and repository diff with SOPS tooling. The
original target was not replaced.

### Installed but directory synchronization failed

The new encrypted file was renamed into place, but macOS did not confirm
directory durability. Do not repeat the save blindly. Reload the document and
inspect the ciphertext diff before continuing.
