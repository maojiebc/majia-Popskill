#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for release smoke tests. Install it with: brew install jq" >&2
  exit 127
fi

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "==> Smoke testing release artifacts"

"$ROOT_DIR/scripts/package-dmg.sh" > "$TMP_DIR/package-dmg.out"
"$ROOT_DIR/scripts/release-manifest.sh" > "$TMP_DIR/release-manifest.out"

MANIFEST="$ROOT_DIR/build/release-manifest.json"
APPCAST="$ROOT_DIR/build/appcast.xml"

jq -e '
  .name == "Popskill"
  and (.version | length > 0)
  and (.build | length > 0)
  and (.artifactName | endswith(".dmg"))
  and (.sha256 | test("^[0-9a-f]{64}$"))
  and (.bytes > 0)
' "$MANIFEST" > /dev/null

POPSKILL_APPCAST_DOWNLOAD_URL="https://example.com/Popskill.dmg" \
  "$ROOT_DIR/scripts/generate-appcast.sh" > "$TMP_DIR/generate-appcast.out"

grep -q '<rss version="2.0"' "$APPCAST"
grep -q 'xmlns:sparkle=' "$APPCAST"
grep -q '<sparkle:version>' "$APPCAST"
grep -q 'https://example.com/Popskill.dmg' "$APPCAST"

echo "release-artifacts ok"
