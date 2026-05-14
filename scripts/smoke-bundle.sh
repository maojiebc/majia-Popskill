#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SECONDS="${1:-3}"
APP_DIR="$ROOT_DIR/build/Popskill.app"
APP_BIN="$APP_DIR/Contents/MacOS/Popskill"
BUNDLED_CLI="$APP_DIR/Contents/Resources/skill-cli"
BUNDLED_DOCS="$APP_DIR/Contents/Resources/ipc.md"
BUNDLED_SPARKLE="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
LOG_FILE="$(mktemp)"
WINDOW_CHECKER="$(mktemp "${TMPDIR:-/tmp}/popskill-window-check.XXXXXX.swift")"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2> /dev/null; then
    kill "$APP_PID" 2> /dev/null || true
    wait "$APP_PID" 2> /dev/null || true
  fi
  rm -f "$LOG_FILE" "$WINDOW_CHECKER"
}
trap cleanup EXIT

"$ROOT_DIR/scripts/package-dev-app.sh" > /dev/null

if [[ ! -x "$APP_BIN" ]]; then
  echo "missing bundled app executable: $APP_BIN" >&2
  exit 1
fi

if [[ ! -x "$BUNDLED_CLI" ]]; then
  echo "missing bundled skill-cli sidecar: $BUNDLED_CLI" >&2
  exit 1
fi

if [[ ! -f "$BUNDLED_DOCS" ]]; then
  echo "missing bundled IPC docs: $BUNDLED_DOCS" >&2
  exit 1
fi

if otool -L "$APP_BIN" | grep -q "Sparkle.framework"; then
  if [[ ! -f "$BUNDLED_SPARKLE" ]]; then
    echo "missing bundled Sparkle framework binary: $BUNDLED_SPARKLE" >&2
    exit 1
  fi

  if ! otool -l "$APP_BIN" | grep -q "@executable_path/../Frameworks"; then
    echo "missing app bundle Frameworks rpath for Sparkle" >&2
    exit 1
  fi
fi

cat > "$WINDOW_CHECKER" <<'SWIFT'
import CoreGraphics
import Foundation

func numericValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let double = value as? Double {
        return double
    }
    if let int = value as? Int {
        return Double(int)
    }
    return nil
}

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let hasMainWindow = windows.contains { window in
    guard
        (window[kCGWindowOwnerName as String] as? String) == "Popskill",
        let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let width = numericValue(bounds["Width"]),
        let height = numericValue(bounds["Height"])
    else {
        return false
    }

    return width >= 600 && height >= 400
}

exit(hasMainWindow ? 0 : 1)
SWIFT

env -u POPSKILL_CLI "$APP_BIN" > "$LOG_FILE" 2>&1 &
APP_PID="$!"

sleep "$RUN_SECONDS"

if ! kill -0 "$APP_PID" 2> /dev/null; then
  cat "$LOG_FILE" >&2
  echo "Popskill bundle exited during launch smoke" >&2
  exit 1
fi

if [[ -s "$LOG_FILE" ]] && grep -Eiq "fatal error|uncaught|crash" "$LOG_FILE"; then
  cat "$LOG_FILE" >&2
  echo "Popskill bundle launch log contains a crash signature" >&2
  exit 1
fi

if ! swift "$WINDOW_CHECKER"; then
  cat "$LOG_FILE" >&2
  echo "Popskill bundle did not create a visible main window" >&2
  exit 1
fi

echo "Popskill bundle smoke ok"
