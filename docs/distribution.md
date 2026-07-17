# Distribution

## Local unsigned package

Run:

```sh
Scripts/package.sh
```

The script builds Release configuration, verifies the app version, universal
`arm64`/`x86_64` binary, compiled Icon Composer resources, and privacy
manifest, then creates:

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
VERSION=1.0.1
git tag -a "v$VERSION" -m "Cipherleaf $VERSION"
VERSION="$VERSION" TEAM_ID=YOUR_TEAM_ID Scripts/release.sh
```

The script:

- checks that `VERSION` matches `MARKETING_VERSION`;
- refuses worktree changes and requires `v<VERSION>` at `HEAD` unless the
  corresponding `ALLOW_DIRTY=1` or `ALLOW_UNTAGGED=1` override is explicit;
- archives a Release build with Hardened Runtime and verifies both `arm64` and
  `x86_64` slices;
- exports it with Developer ID automatic signing through Xcode;
- uploads the archive to Apple's notary service and waits for completion;
- staples the accepted Apple ticket to the signed app and verifies its
  signature, team, ticket, and Gatekeeper assessment;
- creates the final ZIP and SHA-256 checksum.

The output is:

```text
.build/release/Cipherleaf-<version>-macos.zip
.build/release/Cipherleaf-<version>-macos.zip.sha256
```

Publish the checked artifacts from the exact tagged commit:

```sh
git push origin "v$VERSION"
gh release create "v$VERSION" \
  ".build/release/Cipherleaf-$VERSION-macos.zip" \
  ".build/release/Cipherleaf-$VERSION-macos.zip.sha256" \
  --verify-tag \
  --title "Cipherleaf $VERSION" \
  --generate-notes
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
