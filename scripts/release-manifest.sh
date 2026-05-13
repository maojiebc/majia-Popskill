#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${POPSKILL_APP_PATH:-$ROOT_DIR/build/Popskill.app}"
DMG_PATH="${1:-${POPSKILL_DMG_PATH:-$ROOT_DIR/build/Popskill.dmg}}"
MANIFEST_PATH="${POPSKILL_RELEASE_MANIFEST_PATH:-$ROOT_DIR/build/release-manifest.json}"
RELEASE_BASE_URL="${POPSKILL_RELEASE_BASE_URL:-}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

die() {
  echo "release-manifest: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

require_tool shasum
require_tool stat
[[ -x "$PLIST_BUDDY" ]] || die "missing required tool: $PLIST_BUDDY"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "==> DMG not found, packaging development DMG"
  POPSKILL_DMG_PATH="$DMG_PATH" "$ROOT_DIR/scripts/package-dmg.sh" "$APP_PATH" >/dev/null
fi

[[ -d "$APP_PATH" ]] || die "app bundle not found: $APP_PATH"
[[ -f "$DMG_PATH" ]] || die "DMG not found: $DMG_PATH"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]] || die "Info.plist not found: $INFO_PLIST"

VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$INFO_PLIST")"
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
BYTES="$(stat -f '%z' "$DMG_PATH")"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
ARTIFACT_NAME="$(basename "$DMG_PATH")"
DOWNLOAD_URL=""

if [[ -n "$RELEASE_BASE_URL" ]]; then
  DOWNLOAD_URL="${RELEASE_BASE_URL%/}/$ARTIFACT_NAME"
fi

mkdir -p "$(dirname "$MANIFEST_PATH")"
cat > "$MANIFEST_PATH" <<JSON
{
  "name": "Popskill",
  "version": "$VERSION",
  "build": "$BUILD",
  "artifactName": "$ARTIFACT_NAME",
  "artifactPath": "$DMG_PATH",
  "downloadUrl": "$DOWNLOAD_URL",
  "sha256": "$SHA256",
  "bytes": $BYTES,
  "generatedAt": "$GENERATED_AT"
}
JSON

echo "==> Release manifest: $MANIFEST_PATH"
cat "$MANIFEST_PATH"
