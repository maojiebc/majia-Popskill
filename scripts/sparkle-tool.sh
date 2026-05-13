#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
  echo "sparkle-tool: $*" >&2
  exit 1
}

[[ $# -ge 1 ]] || die "usage: scripts/sparkle-tool.sh <tool-name> [args...]"

TOOL_NAME="$1"
shift

find_tool() {
  find "$ROOT_DIR/swift-app/.build/artifacts" \
    -path "*/bin/$TOOL_NAME" \
    -type f \
    -perm -111 \
    2>/dev/null | sort | head -n 1
}

TOOL_PATH="$(find_tool)"

if [[ -z "$TOOL_PATH" ]]; then
  "$ROOT_DIR/scripts/swiftpm.sh" build --package-path "$ROOT_DIR/swift-app" >/dev/null
  TOOL_PATH="$(find_tool)"
fi

[[ -n "$TOOL_PATH" ]] || die "Sparkle tool not found after Swift build: $TOOL_NAME"

if [[ $# -eq 0 ]]; then
  echo "$TOOL_PATH"
else
  exec "$TOOL_PATH" "$@"
fi
