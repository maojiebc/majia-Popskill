#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/build/Popskill.app}"
ZIP_PATH="${POPSKILL_NOTARY_ZIP_PATH:-$ROOT_DIR/build/Popskill-notary.zip}"
SIGN_IDENTITY="${POPSKILL_DEVELOPER_ID_APPLICATION:-${POPSKILL_DEVELOPER_ID:-}}"
KEYCHAIN_PROFILE="${POPSKILL_NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${POPSKILL_APPLE_ID:-}"
TEAM_ID="${POPSKILL_TEAM_ID:-}"
NOTARY_PASSWORD="${POPSKILL_NOTARY_PASSWORD:-}"

die() {
  echo "notarize: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

require_xcrun_tool() {
  xcrun --find "$1" >/dev/null 2>&1 || die "missing Xcode tool: $1"
}

require_tool codesign
require_tool ditto
require_xcrun_tool notarytool
require_xcrun_tool stapler

sign_component() {
  local path="$1"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$path"
}

if [[ ! -d "$APP_PATH" ]]; then
  echo "==> App bundle not found, building development bundle"
  "$ROOT_DIR/scripts/package-dev-app.sh" >/dev/null
fi

[[ -d "$APP_PATH" ]] || die "app bundle not found: $APP_PATH"
[[ -n "$SIGN_IDENTITY" ]] || die "set POPSKILL_DEVELOPER_ID_APPLICATION to your Developer ID Application identity"

if [[ -z "$KEYCHAIN_PROFILE" ]]; then
  [[ -n "$APPLE_ID" ]] || die "set POPSKILL_APPLE_ID or POPSKILL_NOTARY_KEYCHAIN_PROFILE"
  [[ -n "$TEAM_ID" ]] || die "set POPSKILL_TEAM_ID or POPSKILL_NOTARY_KEYCHAIN_PROFILE"
  [[ -n "$NOTARY_PASSWORD" ]] || die "set POPSKILL_NOTARY_PASSWORD or POPSKILL_NOTARY_KEYCHAIN_PROFILE"
fi

echo "==> Signing nested frameworks and XPC services"
# Sparkle ships a nested Updater.app + Autoupdate Mach-O binary that the
# Apple notary service insists on being signed individually with Developer
# ID + secure timestamp. Generic `find -name "*.framework"` is not enough
# because it doesn't descend into framework Versions/.../Updater.app or
# pick up the Mach-O Autoupdate helper. Sign the deepest first so the
# parent container's seal covers everything.
SPARKLE_FRAMEWORK_PATH="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK_PATH" ]]; then
  SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK_PATH/Versions/B"
  if [[ -d "$SPARKLE_VERSION_DIR" ]]; then
    if [[ -f "$SPARKLE_VERSION_DIR/Updater.app/Contents/MacOS/Updater" ]]; then
      sign_component "$SPARKLE_VERSION_DIR/Updater.app/Contents/MacOS/Updater"
    fi
    if [[ -d "$SPARKLE_VERSION_DIR/Updater.app" ]]; then
      sign_component "$SPARKLE_VERSION_DIR/Updater.app"
    fi
    if [[ -f "$SPARKLE_VERSION_DIR/Autoupdate" ]]; then
      sign_component "$SPARKLE_VERSION_DIR/Autoupdate"
    fi
    while IFS= read -r -d '' xpc; do
      sign_component "$xpc"
    done < <(find "$SPARKLE_VERSION_DIR/XPCServices" -name "*.xpc" -type d -print0 2>/dev/null | sort -z)
  fi
  sign_component "$SPARKLE_FRAMEWORK_PATH"
fi

if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' xpc; do
    # Already covered above for Sparkle; skip to avoid double-signing churn.
    [[ "$xpc" == "$SPARKLE_FRAMEWORK_PATH"* ]] && continue
    sign_component "$xpc"
  done < <(find "$APP_PATH/Contents/Frameworks" -name "*.xpc" -type d -print0 | sort -z)

  while IFS= read -r -d '' framework; do
    [[ "$framework" == "$SPARKLE_FRAMEWORK_PATH" ]] && continue
    sign_component "$framework"
  done < <(find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d -print0 | sort -z)
fi

echo "==> Signing nested executables"
if [[ -f "$APP_PATH/Contents/Resources/skill-cli" ]]; then
  sign_component "$APP_PATH/Contents/Resources/skill-cli"
fi

if [[ -f "$APP_PATH/Contents/MacOS/Popskill" ]]; then
  sign_component "$APP_PATH/Contents/MacOS/Popskill"
fi

echo "==> Signing app bundle"
sign_component "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Creating notarization zip"
rm -f "$ZIP_PATH"
mkdir -p "$(dirname "$ZIP_PATH")"
APP_PARENT="$(cd "$(dirname "$APP_PATH")" && pwd)"
APP_NAME="$(basename "$APP_PATH")"
(cd "$APP_PARENT" && ditto -c -k --keepParent "$APP_NAME" "$ZIP_PATH")

echo "==> Submitting to Apple notary service"
if [[ -n "$KEYCHAIN_PROFILE" ]]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
else
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait
fi

echo "==> Stapling ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Notarized app: $APP_PATH"
