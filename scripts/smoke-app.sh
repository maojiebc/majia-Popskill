#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SECONDS="${1:-3}"
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

if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi

cargo build --manifest-path "$ROOT_DIR/skill-cli/Cargo.toml"
"$ROOT_DIR/scripts/swiftpm.sh" build --package-path "$ROOT_DIR/swift-app"

export POPSKILL_CLI="$ROOT_DIR/skill-cli/target/debug/skill-cli"
"$ROOT_DIR/swift-app/.build/debug/Popskill" > "$LOG_FILE" 2>&1 &
APP_PID="$!"

sleep "$RUN_SECONDS"

if ! kill -0 "$APP_PID" 2> /dev/null; then
  cat "$LOG_FILE" >&2
  echo "Popskill exited during launch smoke" >&2
  exit 1
fi

if [[ -s "$LOG_FILE" ]] && grep -Eiq "fatal error|uncaught|crash" "$LOG_FILE"; then
  cat "$LOG_FILE" >&2
  echo "Popskill launch log contains a crash signature" >&2
  exit 1
fi

echo "Popskill launch smoke ok"
