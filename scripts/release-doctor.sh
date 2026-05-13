#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${POPSKILL_APP_PATH:-$ROOT_DIR/build/Popskill.app}}"
DMG_PATH="${POPSKILL_DMG_PATH:-$ROOT_DIR/build/Popskill.dmg}"
APPCAST_PATH="${POPSKILL_APPCAST_PATH:-$ROOT_DIR/build/appcast.xml}"
MANIFEST_PATH="${POPSKILL_RELEASE_MANIFEST_PATH:-$ROOT_DIR/build/release-manifest.json}"
SIGN_IDENTITY="${POPSKILL_DEVELOPER_ID_APPLICATION:-${POPSKILL_DEVELOPER_ID:-}}"
KEYCHAIN_PROFILE="${POPSKILL_NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${POPSKILL_APPLE_ID:-}"
TEAM_ID="${POPSKILL_TEAM_ID:-}"
NOTARY_PASSWORD="${POPSKILL_NOTARY_PASSWORD:-}"
EXPECTED_APP_VERSION="${POPSKILL_APP_VERSION:-}"
EXPECTED_APP_BUILD="${POPSKILL_APP_BUILD:-}"
EXPECTED_BUNDLE_IDENTIFIER="${POPSKILL_BUNDLE_IDENTIFIER:-}"
SPARKLE_FEED_URL="${POPSKILL_SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${POPSKILL_SPARKLE_PUBLIC_ED_KEY:-}"
APPCAST_DOWNLOAD_URL="${POPSKILL_APPCAST_DOWNLOAD_URL:-}"
RELEASE_BASE_URL="${POPSKILL_RELEASE_BASE_URL:-}"
ALLOW_PLACEHOLDER="${POPSKILL_ALLOW_PLACEHOLDER_APPCAST:-false}"
REQUIRE_SPARKLE="${POPSKILL_REQUIRE_SPARKLE:-false}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

failures=0
warnings=0

ok() {
  printf '[ok] %s\n' "$*"
}

warn() {
  warnings=$((warnings + 1))
  printf '[warn] %s\n' "$*"
}

fail() {
  failures=$((failures + 1))
  printf '[fail] %s\n' "$*"
}

warn_or_fail_sparkle() {
  if [[ "$REQUIRE_SPARKLE" == true ]]; then
    fail "$*"
  else
    warn "$*"
  fi
}

check_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "tool found: $1"
  else
    fail "missing required tool: $1"
  fi
}

check_xcrun_tool() {
  if xcrun --find "$1" >/dev/null 2>&1; then
    ok "Xcode tool found: $1"
  else
    fail "missing Xcode tool: $1"
  fi
}

check_placeholder_url() {
  local label="$1"
  local value="$2"

  if [[ -n "$value" && "$value" == *"example.com"* && "$ALLOW_PLACEHOLDER" != true ]]; then
    fail "$label contains placeholder example.com URL"
  fi
}

echo "==> Popskill release doctor"

check_tool codesign
check_tool security
check_tool ditto
check_tool hdiutil
check_tool install_name_tool
check_tool shasum
check_tool jq
check_tool otool
check_tool stat
[[ -x "$PLIST_BUDDY" ]] && ok "tool found: $PLIST_BUDDY" || fail "missing required tool: $PLIST_BUDDY"
check_xcrun_tool notarytool
check_xcrun_tool stapler

echo
echo "==> Artifacts"
if [[ -d "$APP_PATH" ]]; then
  ok "app bundle exists: $APP_PATH"
  app_bin="$APP_PATH/Contents/MacOS/Popskill"
  sparkle_bin="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"

  if [[ -x "$app_bin" ]]; then
    ok "app executable exists: $app_bin"

    if command -v otool >/dev/null 2>&1; then
      if otool -L "$app_bin" | grep -q "Sparkle.framework"; then
        ok "app executable links Sparkle.framework"

        if [[ -f "$sparkle_bin" ]]; then
          ok "bundled Sparkle framework exists"
        else
          fail "app links Sparkle but bundled framework is missing: $sparkle_bin"
        fi

        if otool -l "$app_bin" | grep -q "@executable_path/../Frameworks"; then
          ok "app executable has Frameworks rpath"
        else
          fail "app links Sparkle but is missing @executable_path/../Frameworks rpath"
        fi
      else
        fail "app executable does not link Sparkle.framework; rebuild with scripts/package-dev-app.sh"
      fi
    fi
  else
    fail "app executable missing or not executable: $app_bin"
  fi

  info_plist="$APP_PATH/Contents/Info.plist"
  if [[ -f "$info_plist" && -x "$PLIST_BUDDY" ]]; then
    app_version="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)"
    app_build="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null || true)"
    bundle_identifier="$("$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"
    bundle_feed_url="$("$PLIST_BUDDY" -c 'Print :SUFeedURL' "$info_plist" 2>/dev/null || true)"
    bundle_public_ed_key="$("$PLIST_BUDDY" -c 'Print :SUPublicEDKey' "$info_plist" 2>/dev/null || true)"

    if [[ -n "$EXPECTED_APP_VERSION" ]]; then
      if [[ "$app_version" == "$EXPECTED_APP_VERSION" ]]; then
        ok "app version matches POPSKILL_APP_VERSION: $app_version"
      else
        fail "app version mismatch: expected $EXPECTED_APP_VERSION, found ${app_version:-unknown}"
      fi
    elif [[ "$app_version" == *"-dev"* ]]; then
      warn "app version is a development version: $app_version"
    fi

    if [[ -n "$EXPECTED_APP_BUILD" ]]; then
      if [[ "$app_build" == "$EXPECTED_APP_BUILD" ]]; then
        ok "app build matches POPSKILL_APP_BUILD: $app_build"
      else
        fail "app build mismatch: expected $EXPECTED_APP_BUILD, found ${app_build:-unknown}"
      fi
    fi

    if [[ -n "$EXPECTED_BUNDLE_IDENTIFIER" ]]; then
      if [[ "$bundle_identifier" == "$EXPECTED_BUNDLE_IDENTIFIER" ]]; then
        ok "bundle identifier matches POPSKILL_BUNDLE_IDENTIFIER: $bundle_identifier"
      else
        fail "bundle identifier mismatch: expected $EXPECTED_BUNDLE_IDENTIFIER, found ${bundle_identifier:-unknown}"
      fi
    elif [[ "$bundle_identifier" == *".dev" ]]; then
      warn "bundle identifier is a development identifier: $bundle_identifier"
    fi

    check_placeholder_url "app bundle Sparkle feed URL" "$bundle_feed_url"

    if [[ -n "$SPARKLE_FEED_URL" ]]; then
      if [[ "$bundle_feed_url" == "$SPARKLE_FEED_URL" ]]; then
        ok "app bundle Sparkle feed URL matches POPSKILL_SPARKLE_FEED_URL"
      else
        fail "app bundle Sparkle feed URL mismatch; rebuild with scripts/package-dev-app.sh"
      fi
    elif [[ -n "$bundle_feed_url" ]]; then
      warn "app bundle has SUFeedURL but POPSKILL_SPARKLE_FEED_URL is unset, so release-doctor cannot verify it"
    fi

    if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
      if [[ "$bundle_public_ed_key" == "$SPARKLE_PUBLIC_ED_KEY" ]]; then
        ok "app bundle Sparkle public EdDSA key matches POPSKILL_SPARKLE_PUBLIC_ED_KEY"
      else
        fail "app bundle Sparkle public EdDSA key mismatch; rebuild with scripts/package-dev-app.sh"
      fi
    elif [[ -n "$bundle_public_ed_key" ]]; then
      warn "app bundle has SUPublicEDKey but POPSKILL_SPARKLE_PUBLIC_ED_KEY is unset, so release-doctor cannot verify it"
    fi
  else
    fail "Info.plist not found or PlistBuddy unavailable"
  fi
else
  warn "app bundle not found: $APP_PATH (run scripts/package-dev-app.sh)"
fi

if [[ -f "$DMG_PATH" ]]; then
  ok "DMG exists: $DMG_PATH"
else
  warn "DMG not found: $DMG_PATH (run scripts/package-dmg.sh)"
fi

if [[ -f "$MANIFEST_PATH" ]]; then
  ok "release manifest exists: $MANIFEST_PATH"

  if jq -e type "$MANIFEST_PATH" >/dev/null 2>&1; then
    manifest_version="$(jq -r '.version // ""' "$MANIFEST_PATH")"
    manifest_build="$(jq -r '.build // ""' "$MANIFEST_PATH")"
    manifest_artifact_name="$(jq -r '.artifactName // ""' "$MANIFEST_PATH")"
    manifest_artifact_path="$(jq -r '.artifactPath // ""' "$MANIFEST_PATH")"
    manifest_download_url="$(jq -r '.downloadUrl // ""' "$MANIFEST_PATH")"
    manifest_sha="$(jq -r '.sha256 // ""' "$MANIFEST_PATH")"
    manifest_bytes="$(jq -r '.bytes // ""' "$MANIFEST_PATH")"

    check_placeholder_url "release manifest downloadUrl" "$manifest_download_url"

    if [[ -n "${app_version:-}" && "$manifest_version" == "$app_version" ]]; then
      ok "release manifest version matches app bundle: $manifest_version"
    elif [[ -n "${app_version:-}" ]]; then
      fail "release manifest version mismatch: expected app bundle version ${app_version:-unknown}, found ${manifest_version:-unknown}"
    fi

    if [[ -n "${app_build:-}" && "$manifest_build" == "$app_build" ]]; then
      ok "release manifest build matches app bundle: $manifest_build"
    elif [[ -n "${app_build:-}" ]]; then
      fail "release manifest build mismatch: expected app bundle build ${app_build:-unknown}, found ${manifest_build:-unknown}"
    fi

    if [[ -n "$EXPECTED_APP_VERSION" && "$manifest_version" != "$EXPECTED_APP_VERSION" ]]; then
      fail "release manifest version mismatch: expected POPSKILL_APP_VERSION $EXPECTED_APP_VERSION, found ${manifest_version:-unknown}"
    fi

    if [[ -n "$EXPECTED_APP_BUILD" && "$manifest_build" != "$EXPECTED_APP_BUILD" ]]; then
      fail "release manifest build mismatch: expected POPSKILL_APP_BUILD $EXPECTED_APP_BUILD, found ${manifest_build:-unknown}"
    fi

    if [[ -f "$DMG_PATH" ]]; then
      expected_artifact_name="$(basename "$DMG_PATH")"
      if [[ "$manifest_artifact_name" == "$expected_artifact_name" ]]; then
        ok "release manifest artifactName matches DMG: $manifest_artifact_name"
      else
        fail "release manifest artifactName mismatch: expected $expected_artifact_name, found ${manifest_artifact_name:-unknown}"
      fi

      if [[ "$manifest_artifact_path" == "$DMG_PATH" ]]; then
        ok "release manifest artifactPath matches DMG path"
      else
        fail "release manifest artifactPath mismatch: expected $DMG_PATH, found ${manifest_artifact_path:-unknown}"
      fi

      actual_sha="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
      actual_bytes="$(stat -f '%z' "$DMG_PATH")"

      if [[ "$manifest_sha" == "$actual_sha" ]]; then
        ok "release manifest sha256 matches DMG"
      else
        fail "release manifest sha256 mismatch; rerun scripts/release-manifest.sh"
      fi

      if [[ "$manifest_bytes" == "$actual_bytes" ]]; then
        ok "release manifest byte size matches DMG"
      else
        fail "release manifest byte size mismatch; rerun scripts/release-manifest.sh"
      fi
    fi
  else
    fail "release manifest is not valid JSON: $MANIFEST_PATH"
  fi
else
  warn "release manifest not found: $MANIFEST_PATH (run scripts/release-manifest.sh)"
fi

echo
echo "==> Signing identity"
identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

if [[ -z "$SIGN_IDENTITY" ]]; then
  fail "set POPSKILL_DEVELOPER_ID_APPLICATION to a Developer ID Application identity"
  developer_id_hint="$(printf '%s\n' "$identities" | grep 'Developer ID Application' | head -n 1 || true)"
  if [[ -n "$developer_id_hint" ]]; then
    warn "available Developer ID identity: $developer_id_hint"
  else
    warn "no Developer ID Application identity was found in the keychain"
  fi
else
  if printf '%s\n' "$identities" | grep -F "$SIGN_IDENTITY" >/dev/null 2>&1; then
    ok "Developer ID identity found: $SIGN_IDENTITY"
  else
    fail "Developer ID identity not found in keychain: $SIGN_IDENTITY"
  fi
fi

echo
echo "==> Notary credentials"
if [[ -n "$KEYCHAIN_PROFILE" ]]; then
  ok "using notarytool keychain profile: $KEYCHAIN_PROFILE"
else
  missing=()
  [[ -n "$APPLE_ID" ]] || missing+=("POPSKILL_APPLE_ID")
  [[ -n "$TEAM_ID" ]] || missing+=("POPSKILL_TEAM_ID")
  [[ -n "$NOTARY_PASSWORD" ]] || missing+=("POPSKILL_NOTARY_PASSWORD")

  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "Apple ID notary environment variables are set"
  else
    fail "set POPSKILL_NOTARY_KEYCHAIN_PROFILE or missing vars: ${missing[*]}"
  fi
fi

echo
echo "==> Sparkle appcast"
if [[ -f "$APPCAST_PATH" ]]; then
  ok "appcast exists: $APPCAST_PATH"
  if grep -q 'example.com' "$APPCAST_PATH"; then
    fail "appcast contains placeholder example.com URL: $APPCAST_PATH"
  fi
  if [[ "$REQUIRE_SPARKLE" == true ]]; then
    if grep -q 'sparkle:edSignature=' "$APPCAST_PATH"; then
      ok "appcast contains Sparkle EdDSA signature"
    else
      fail "appcast is missing sparkle:edSignature; rerun scripts/generate-appcast.sh with POPSKILL_SPARKLE_ED_SIGNATURE"
    fi
  fi
else
  warn_or_fail_sparkle "appcast not found: $APPCAST_PATH (run scripts/generate-appcast.sh for public releases)"
fi

if [[ -n "$SPARKLE_FEED_URL" ]]; then
  check_placeholder_url "POPSKILL_SPARKLE_FEED_URL" "$SPARKLE_FEED_URL"
  ok "Sparkle feed URL is set for the app bundle"
else
  warn_or_fail_sparkle "set POPSKILL_SPARKLE_FEED_URL before packaging a public Sparkle-enabled app"
fi

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  ok "Sparkle public EdDSA key is set for the app bundle"
else
  warn_or_fail_sparkle "set POPSKILL_SPARKLE_PUBLIC_ED_KEY before packaging a public Sparkle-enabled app"
fi

check_placeholder_url "POPSKILL_APPCAST_DOWNLOAD_URL" "$APPCAST_DOWNLOAD_URL"
check_placeholder_url "POPSKILL_RELEASE_BASE_URL" "$RELEASE_BASE_URL"

if [[ -n "$APPCAST_DOWNLOAD_URL" || -n "$RELEASE_BASE_URL" ]]; then
  ok "appcast download URL source is set"
else
  warn_or_fail_sparkle "set POPSKILL_APPCAST_DOWNLOAD_URL or POPSKILL_RELEASE_BASE_URL before generating a public appcast"
fi

if [[ -n "${POPSKILL_SPARKLE_ED_SIGNATURE:-}" ]]; then
  ok "Sparkle EdDSA signature is set"
else
  warn_or_fail_sparkle "POPSKILL_SPARKLE_ED_SIGNATURE is not set; public Sparkle appcasts need a real signature"
fi

echo
if [[ "$failures" -gt 0 ]]; then
  echo "release-doctor: not ready ($failures failure(s), $warnings warning(s))"
  echo "release-doctor: see docs/release-runbook.md for credential and notarization setup"
  exit 1
fi

echo "release-doctor: ready ($warnings warning(s))"
echo "release-doctor: see docs/release-runbook.md for the notarization and appcast release flow"
