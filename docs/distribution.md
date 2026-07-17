# Distribution

## Local unsigned package

Run:

```sh
Scripts/package.sh
```

The script builds Release configuration, verifies the compiled Icon Composer
resources and privacy manifest, and creates:

```text
.build/release/Cipherleaf-<version>-unsigned.zip
```

Unsigned artifacts are suitable for local review and CI, not for a polished
public download. Gatekeeper will identify them as unnotarized.

## Developer ID release

A public binary should be signed with a **Developer ID Application**
certificate and notarized with Apple's notary service.

Sign in to the release Apple Developer team in Xcode. The account must be able
to use Developer ID distribution and notarization. Tag the exact commit, then
run:

```sh
git tag -a v1.0.0 -m "Cipherleaf 1.0.0"
VERSION=1.0.0 TEAM_ID=YOUR_TEAM_ID Scripts/release.sh
```

The script:

- checks that `VERSION` matches `MARKETING_VERSION`;
- refuses worktree changes and requires `v<VERSION>` at `HEAD` unless the
  corresponding `ALLOW_DIRTY=1` or `ALLOW_UNTAGGED=1` override is explicit;
- archives a universal Release build with Hardened Runtime;
- exports it with Developer ID automatic signing through Xcode;
- uploads the archive to Apple's notary service and waits for completion;
- exports the stapled app and verifies its signature, team, ticket, and
  Gatekeeper assessment;
- creates the final ZIP and SHA-256 checksum.

The output is:

```text
.build/release/Cipherleaf-<version>-macos.zip
.build/release/Cipherleaf-<version>-macos.zip.sha256
```

Publish the checked artifacts from the exact tagged commit:

```sh
git push origin v1.0.0
gh release create v1.0.0 \
  .build/release/Cipherleaf-1.0.0-macos.zip \
  .build/release/Cipherleaf-1.0.0-macos.zip.sha256 \
  --verify-tag \
  --title "Cipherleaf 1.0.0" \
  --notes-file CHANGELOG.md
```

Never commit signing certificates, private keys, app-specific passwords, or
notary API keys. `Scripts/release.sh` relies on the authenticated local Xcode
account and stores build products only under the ignored `.build` directory.

## Release checklist

1. Update `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and
   `CHANGELOG.md`.
2. Run `Scripts/test.sh`.
3. Run `Scripts/package.sh`.
4. Inspect the app icon at small and large sizes.
5. Test open, edit, save, external-modification rejection, identity mismatch,
   close, and quit behavior with synthetic material.
6. Run `Scripts/release.sh` from a clean tagged commit.
7. Verify the stapled app on a separate macOS account or machine.
8. Publish the archive and checksum in a GitHub Release.
