#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${POPSKILL_APP_PATH:-$ROOT_DIR/build/Popskill.app}}"
DMG_PATH="${POPSKILL_DMG_PATH:-$ROOT_DIR/build/Popskill.dmg}"
APPCAST_PATH="${POPSKILL_APPCAST_PATH:-$ROOT_DIR/build/appcast.xml}"
SIGN_IDENTITY="${POPSKILL_DEVELOPER_ID_APPLICATION:-${POPSKILL_DEVELOPER_ID:-}}"
KEYCHAIN_PROFILE="${POPSKILL_NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${POPSKILL_APPLE_ID:-}"
TEAM_ID="${POPSKILL_TEAM_ID:-}"
NOTARY_PASSWORD="${POPSKILL_NOTARY_PASSWORD:-}"

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

echo "==> Popskill release doctor"

check_tool codesign
check_tool security
check_tool ditto
check_tool hdiutil
check_tool install_name_tool
check_tool shasum
check_tool jq
check_tool otool
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
else
  warn "app bundle not found: $APP_PATH (run scripts/package-dev-app.sh)"
fi

if [[ -f "$DMG_PATH" ]]; then
  ok "DMG exists: $DMG_PATH"
else
  warn "DMG not found: $DMG_PATH (run scripts/package-dmg.sh)"
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
else
  warn "appcast not found: $APPCAST_PATH (run scripts/generate-appcast.sh for public releases)"
fi

if [[ -n "${POPSKILL_SPARKLE_FEED_URL:-}" ]]; then
  ok "Sparkle feed URL is set for the app bundle"
else
  warn "set POPSKILL_SPARKLE_FEED_URL before packaging a public Sparkle-enabled app"
fi

if [[ -n "${POPSKILL_SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  ok "Sparkle public EdDSA key is set for the app bundle"
else
  warn "set POPSKILL_SPARKLE_PUBLIC_ED_KEY before packaging a public Sparkle-enabled app"
fi

if [[ -n "${POPSKILL_APPCAST_DOWNLOAD_URL:-}" || -n "${POPSKILL_RELEASE_BASE_URL:-}" ]]; then
  ok "appcast download URL source is set"
else
  warn "set POPSKILL_APPCAST_DOWNLOAD_URL or POPSKILL_RELEASE_BASE_URL before generating a public appcast"
fi

if [[ -n "${POPSKILL_SPARKLE_ED_SIGNATURE:-}" ]]; then
  ok "Sparkle EdDSA signature is set"
else
  warn "POPSKILL_SPARKLE_ED_SIGNATURE is not set; public Sparkle appcasts need a real signature"
fi

echo
if [[ "$failures" -gt 0 ]]; then
  echo "release-doctor: not ready ($failures failure(s), $warnings warning(s))"
  echo "release-doctor: see docs/release-runbook.md for credential and notarization setup"
  exit 1
fi

echo "release-doctor: ready ($warnings warning(s))"
echo "release-doctor: see docs/release-runbook.md for the notarization and appcast release flow"
