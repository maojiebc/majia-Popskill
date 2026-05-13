#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SECONDS="${1:-3}"
APP_DIR="$ROOT_DIR/build/Popskill.app"
APP_BIN="$APP_DIR/Contents/MacOS/Popskill"
BUNDLED_CLI="$APP_DIR/Contents/Resources/skill-cli"
LOG_FILE="$(mktemp)"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2> /dev/null; then
    kill "$APP_PID" 2> /dev/null || true
    wait "$APP_PID" 2> /dev/null || true
  fi
  rm -f "$LOG_FILE"
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

env -u POPSKILL_CLI "$APP_BIN" > "$LOG_FILE" 2>&1 &
APP_PID="$!"

sleep "$RUN_SECONDS"

if ! kill -0 "$APP_PID" 2> /dev/null; then
  cat "$LOG_FILE" >&2
  echo "Popskill bundle exited during launch smoke" >&2
  exit 1
fi

if [[ -s "$LOG_FILE" ]] && rg -i "fatal error|uncaught|crash" "$LOG_FILE" > /dev/null; then
  cat "$LOG_FILE" >&2
  echo "Popskill bundle launch log contains a crash signature" >&2
  exit 1
fi

echo "Popskill bundle smoke ok"
