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

HAS_PILLOW=false
if command -v python3 >/dev/null 2>&1 \
  && python3 -c 'from PIL import Image, ImageStat' >/dev/null 2>&1; then
  HAS_PILLOW=true
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

  if [[ "$HAS_PILLOW" == true ]]; then
    python3 - "$path" <<'PY'
import sys
from PIL import Image, ImageStat

path = sys.argv[1]
image = Image.open(path).convert("RGB")
image.thumbnail((320, 200))
stats = ImageStat.Stat(image)
channel_span = max(high for _, high in stats.extrema) - min(low for low, _ in stats.extrema)
average_stddev = sum(stats.stddev) / len(stats.stddev)

if channel_span < 64 or average_stddev < 10:
    raise SystemExit(
        f"screenshot appears blank or too low-variance: {path} "
        f"(span={channel_span:.1f}, stddev={average_stddev:.1f})"
    )
PY
  fi
done

echo "screenshots ok"
