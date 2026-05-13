#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCREENSHOT_DIR="$ROOT_DIR/docs/assets/screenshots"
MIN_WIDTH=1200
MIN_HEIGHT=800
MIN_BYTES=100000

required=(
  "popskill-discover.png"
  "popskill-library.png"
  "popskill-usage.png"
  "popskill-idle-candidates.png"
)

if ! command -v sips >/dev/null 2>&1; then
  echo "sips is required for screenshot smoke tests" >&2
  exit 127
fi

for name in "${required[@]}"; do
  path="$SCREENSHOT_DIR/$name"
  if [[ ! -f "$path" ]]; then
    echo "missing screenshot: $path" >&2
    exit 1
  fi

  bytes="$(stat -f%z "$path")"
  if (( bytes < MIN_BYTES )); then
    echo "screenshot is unexpectedly small: $path ($bytes bytes)" >&2
    exit 1
  fi

  properties="$(sips -g format -g pixelWidth -g pixelHeight "$path" 2>/dev/null)"
  format="$(awk -F': ' '/format:/ {print $2}' <<<"$properties")"
  width="$(awk -F': ' '/pixelWidth:/ {print $2}' <<<"$properties")"
  height="$(awk -F': ' '/pixelHeight:/ {print $2}' <<<"$properties")"

  if [[ "$format" != "png" ]]; then
    echo "screenshot is not PNG: $path ($format)" >&2
    exit 1
  fi

  if (( width < MIN_WIDTH || height < MIN_HEIGHT )); then
    echo "screenshot is too small: $path (${width}x${height})" >&2
    exit 1
  fi
done

echo "screenshots ok"
