# Popskill v0.1 Release Runbook

This runbook covers the path from the current development build to a notarized macOS v0.1 artifact. It intentionally keeps secrets out of the repo, argv, logs, and generated JSON.

## Current Expected State

Before Apple Developer Program credentials are available, this is expected:

```bash
./scripts/release-doctor.sh
```

- Tools should be present: `codesign`, `security`, `ditto`, `hdiutil`, `install_name_tool`, `otool`, `shasum`, `jq`, `notarytool`, `stapler`.
- Artifacts should exist after local CI: `build/Popskill.app`, `build/Popskill.dmg`.
- The app bundle should contain `Sparkle.framework`, and the app executable should have an `@executable_path/../Frameworks` rpath.
- Release doctor should fail on missing Developer ID identity and missing notary credentials.
- Sparkle is linked in the app. Sparkle warnings are expected until a public feed URL, public EdDSA key, download URL, and update signature are available.

## One-Time Apple Setup

1. Join Apple Developer Program.
2. Create or install a **Developer ID Application** certificate in Keychain Access.
3. Confirm the signing identity:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

4. Store notary credentials in the keychain:

```bash
xcrun notarytool store-credentials "popskill-notary" \
  --apple-id "<apple-id@example.com>" \
  --team-id "<TEAMID>" \
  --password "<app-specific-password>"
```

Prefer the keychain profile over raw notary environment variables.

## Environment

Set these in your shell for a public notarized build:

```bash
export POPSKILL_DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export POPSKILL_NOTARY_KEYCHAIN_PROFILE="popskill-notary"
```

For Sparkle-enabled builds, also set:

```bash
export POPSKILL_SPARKLE_FEED_URL="https://example.com/appcast.xml"
export POPSKILL_SPARKLE_PUBLIC_ED_KEY="<sparkle-public-eddsa-key>"
export POPSKILL_APPCAST_DOWNLOAD_URL="https://example.com/Popskill.dmg"
export POPSKILL_SPARKLE_ED_SIGNATURE="<sparkle-dmg-eddsa-signature>"
```

Do not commit these values. Do not paste passwords into command-line arguments except the one-time `notarytool store-credentials` flow.

Use Sparkle's bundled tools through the repo wrappers:

```bash
./scripts/sparkle-generate-keys.sh
./scripts/sparkle-generate-keys.sh -p
./scripts/sparkle-sign-update.sh build/Popskill.dmg
```

`sparkle-sign-update.sh` prints an `export POPSKILL_SPARKLE_ED_SIGNATURE=...` line when it can parse the generated signature. For automation, provide `POPSKILL_SPARKLE_ED_PRIVATE_KEY_FILE` or `POPSKILL_SPARKLE_ED_PRIVATE_KEY`; otherwise Sparkle reads the private key from Keychain.

## Build And Verify

Run the full local gate:

```bash
./scripts/ci-local.sh
```

The local scripts route SwiftPM through `scripts/swiftpm.sh`, which uses a temporary HOME and disables global Git configuration for each Swift invocation. This avoids macOS Keychain credential lookups hanging while downloading public binary artifacts such as Sparkle.

Then check release readiness:

```bash
./scripts/release-doctor.sh
```

With Developer ID and notary credentials present, release doctor should have zero failures. Sparkle warnings are allowed only for unsigned/manual distribution builds.

## Notarize

```bash
./scripts/notarize.sh
```

This script:

1. Builds `build/Popskill.app` if missing.
2. Signs nested frameworks, XPC services, the bundled `skill-cli`, the app executable, and the app bundle.
3. Verifies the signed app bundle.
4. Creates `build/Popskill-notary.zip`.
5. Submits to Apple notary service.
6. Staples and validates the notarization ticket.

## Package DMG And Appcast

After notarization succeeds:

```bash
./scripts/package-dmg.sh
./scripts/release-manifest.sh
./scripts/generate-appcast.sh
```

Verify the appcast smoke path:

```bash
POPSKILL_APPCAST_DOWNLOAD_URL="https://example.com/Popskill.dmg" \
  ./scripts/generate-appcast.sh
```

## Manual Gatekeeper Check

Run these before sharing with an external tester:

```bash
codesign --verify --deep --strict --verbose=2 build/Popskill.app
xcrun stapler validate build/Popskill.app
spctl --assess --type execute --verbose=4 build/Popskill.app
```

If the app is distributed as DMG, mount the DMG on a clean macOS user account and open the copied app from `/Applications`.

## Release Notes Checklist

- Mention this is v0.1 pre-alpha.
- Mention local-only transcript aggregation and no message-body upload.
- Mention WebDAV config is available, while manual Sync Now is still blocked by CC Switch private/Tauri boundaries.
- Mention Sparkle support is present only when feed/key/signature are configured.
- Mention Package abstraction is a v0.2 roadmap item, not a v0.1 behavior change.
