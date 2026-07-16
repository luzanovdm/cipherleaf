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

Build the app first, then sign:

```sh
APP=".build/ReleaseDerivedData/Build/Products/Release/Cipherleaf.app"
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"
```

Store notary credentials in the login Keychain once:

```sh
xcrun notarytool store-credentials "cipherleaf-notary"
```

Create a submission archive and notarize it:

```sh
ditto -c -k --sequesterRsrc --keepParent \
  "$APP" \
  ".build/release/Cipherleaf-notary.zip"
xcrun notarytool submit \
  ".build/release/Cipherleaf-notary.zip" \
  --keychain-profile "cipherleaf-notary" \
  --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
```

Create the final zip only after stapling:

```sh
ditto -c -k --sequesterRsrc --keepParent \
  "$APP" \
  ".build/release/Cipherleaf.zip"
```

Never commit signing certificates, private keys, app-specific passwords, or
notary API keys. A future automated release workflow should use protected
repository environments and short-lived Keychain imports.

## Release checklist

1. Update `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and
   `CHANGELOG.md`.
2. Run `Scripts/test.sh`.
3. Run `Scripts/package.sh`.
4. Inspect the app icon at small and large sizes.
5. Test open, edit, save, external-modification rejection, identity mismatch,
   close, and quit behavior with synthetic material.
6. Sign and notarize the app.
7. Verify the stapled app on a separate macOS account or machine.
8. Publish checksums beside the release.
