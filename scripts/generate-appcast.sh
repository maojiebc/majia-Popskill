#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="${1:-${POPSKILL_RELEASE_MANIFEST_PATH:-$ROOT_DIR/build/release-manifest.json}}"
APPCAST_PATH="${POPSKILL_APPCAST_PATH:-$ROOT_DIR/build/appcast.xml}"
DOWNLOAD_URL_OVERRIDE="${POPSKILL_APPCAST_DOWNLOAD_URL:-}"
ED_SIGNATURE="${POPSKILL_SPARKLE_ED_SIGNATURE:-}"
MINIMUM_SYSTEM_VERSION="${POPSKILL_MINIMUM_SYSTEM_VERSION:-14.0}"

die() {
  echo "generate-appcast: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g'
}

require_tool jq

[[ -f "$MANIFEST_PATH" ]] || die "manifest not found: $MANIFEST_PATH"

VERSION="$(jq -r '.version' "$MANIFEST_PATH")"
BUILD="$(jq -r '.build' "$MANIFEST_PATH")"
ARTIFACT_NAME="$(jq -r '.artifactName' "$MANIFEST_PATH")"
DOWNLOAD_URL="$(jq -r '.downloadUrl // ""' "$MANIFEST_PATH")"
SHA256="$(jq -r '.sha256' "$MANIFEST_PATH")"
BYTES="$(jq -r '.bytes' "$MANIFEST_PATH")"
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"

if [[ -n "$DOWNLOAD_URL_OVERRIDE" ]]; then
  DOWNLOAD_URL="$DOWNLOAD_URL_OVERRIDE"
fi

[[ -n "$DOWNLOAD_URL" ]] || die "set POPSKILL_APPCAST_DOWNLOAD_URL or generate the manifest with POPSKILL_RELEASE_BASE_URL"

VERSION_XML="$(printf '%s' "$VERSION" | xml_escape)"
BUILD_XML="$(printf '%s' "$BUILD" | xml_escape)"
ARTIFACT_NAME_XML="$(printf '%s' "$ARTIFACT_NAME" | xml_escape)"
DOWNLOAD_URL_XML="$(printf '%s' "$DOWNLOAD_URL" | xml_escape)"
SHA256_XML="$(printf '%s' "$SHA256" | xml_escape)"
PUB_DATE_XML="$(printf '%s' "$PUB_DATE" | xml_escape)"
MINIMUM_SYSTEM_VERSION_XML="$(printf '%s' "$MINIMUM_SYSTEM_VERSION" | xml_escape)"
SIGNATURE_ATTR=""

if [[ -n "$ED_SIGNATURE" ]]; then
  ED_SIGNATURE_XML="$(printf '%s' "$ED_SIGNATURE" | xml_escape)"
  SIGNATURE_ATTR=" sparkle:edSignature=\"$ED_SIGNATURE_XML\""
fi

mkdir -p "$(dirname "$APPCAST_PATH")"
cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Popskill Updates</title>
    <item>
      <title>Popskill $VERSION_XML</title>
      <pubDate>$PUB_DATE_XML</pubDate>
      <sparkle:version>$BUILD_XML</sparkle:version>
      <sparkle:shortVersionString>$VERSION_XML</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM_VERSION_XML</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <p>$ARTIFACT_NAME_XML</p>
        <p>SHA-256: $SHA256_XML</p>
      ]]></description>
      <enclosure
        url="$DOWNLOAD_URL_XML"
        sparkle:version="$BUILD_XML"
        sparkle:shortVersionString="$VERSION_XML"
        length="$BYTES"
        type="application/octet-stream"$SIGNATURE_ATTR />
    </item>
  </channel>
</rss>
XML

echo "==> Appcast: $APPCAST_PATH"
cat "$APPCAST_PATH"
