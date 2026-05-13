#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/build/Popskill.app}"
DMG_PATH="${POPSKILL_DMG_PATH:-$ROOT_DIR/build/Popskill.dmg}"
VOLUME_NAME="${POPSKILL_DMG_VOLUME_NAME:-Popskill}"

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "package-dmg: hdiutil is required on macOS" >&2
  exit 127
fi

if ! command -v ditto >/dev/null 2>&1; then
  echo "package-dmg: ditto is required on macOS" >&2
  exit 127
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "==> App bundle not found, building development bundle"
  "$ROOT_DIR/scripts/package-dev-app.sh" >/dev/null
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "package-dmg: app bundle not found: $APP_PATH" >&2
  exit 1
fi

STAGING_PARENT="$(dirname "$DMG_PATH")"
mkdir -p "$STAGING_PARENT"
rm -f "$DMG_PATH"

STAGING_DIR="$(mktemp -d "$STAGING_PARENT/dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_NAME="$(basename "$APP_PATH")"

echo "==> Staging $APP_NAME"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "==> DMG: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
