# Popskill v0.1 Release Runbook

This runbook covers the path from the current development build to a notarized macOS v0.1 artifact. It intentionally keeps secrets out of the repo, argv, logs, and generated JSON.

## Current Expected State

Before Apple Developer Program credentials are available, this is expected:

```bash
./scripts/release-doctor.sh
```

- Tools should be present: `codesign`, `security`, `ditto`, `hdiutil`, `install_name_tool`, `otool`, `shasum`, `jq`, `stat`, `/usr/libexec/PlistBuddy`, `notarytool`, `stapler`.
- Artifacts should exist after local CI: `build/Popskill.app`, `build/Popskill.dmg`.
- The app bundle should contain `Sparkle.framework`, and the app executable should have an `@executable_path/../Frameworks` rpath.
- For public releases, the app bundle version and bundle identifier should match `POPSKILL_APP_VERSION` and `POPSKILL_BUNDLE_IDENTIFIER`.
- If `build/release-manifest.json` exists, release doctor should confirm its version/build, artifact path/name, SHA-256, and byte size match the current app bundle and DMG.
- Release doctor should fail on missing Developer ID identity and missing notary credentials.
- Release doctor should fail if the Sparkle feed, download URL, app bundle metadata, or existing appcast still contains a placeholder `example.com` URL.
- When Sparkle env vars are set, release doctor should confirm the `.app` bundle's `SUFeedURL` and `SUPublicEDKey` match those env vars. If they mismatch, rebuild with `scripts/package-dev-app.sh`.
- Set `POPSKILL_REQUIRE_SPARKLE=true` for public Sparkle-enabled releases so missing feed/key/download/signature/appcast metadata are failures, not warnings.
- Sparkle is linked in the app. Sparkle warnings are expected until a public feed URL, public EdDSA key, download URL, and update signature are available.

The latest local dry-run snapshot is tracked in [v0.1-release-readiness.md](./v0.1-release-readiness.md).

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
export POPSKILL_APP_VERSION="0.1.0"
export POPSKILL_APP_BUILD="1"
export POPSKILL_BUNDLE_IDENTIFIER="com.maojiebc.popskill"
```

For Sparkle-enabled builds, also set:

```bash
export POPSKILL_SPARKLE_FEED_URL="<public-appcast-url>"
export POPSKILL_SPARKLE_PUBLIC_ED_KEY="<sparkle-public-eddsa-key>"
export POPSKILL_APPCAST_DOWNLOAD_URL="<public-dmg-download-url>"
export POPSKILL_SPARKLE_ED_SIGNATURE="<sparkle-dmg-eddsa-signature>"
export POPSKILL_REQUIRE_SPARKLE=true
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

With Developer ID, notary credentials, and public Sparkle metadata present, release doctor should have zero failures. Sparkle warnings are allowed only for unsigned/manual distribution builds; use `POPSKILL_REQUIRE_SPARKLE=true` for public Sparkle-enabled releases.

If you change `POPSKILL_SPARKLE_FEED_URL`, `POPSKILL_SPARKLE_PUBLIC_ED_KEY`, `POPSKILL_APP_VERSION`, `POPSKILL_APP_BUILD`, or `POPSKILL_BUNDLE_IDENTIFIER`, rebuild the app bundle and regenerate release artifacts before trusting release doctor:

```bash
./scripts/package-dev-app.sh
./scripts/package-dmg.sh
./scripts/release-manifest.sh
```

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

Verify the appcast smoke path without writing a public appcast:

```bash
./scripts/smoke-release.sh
```

`generate-appcast.sh` refuses `example.com` placeholder URLs unless `POPSKILL_ALLOW_PLACEHOLDER_APPCAST=true` is set by smoke tests.

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
