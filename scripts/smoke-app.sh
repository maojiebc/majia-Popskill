#!/usr/bin/env bash
set -euo pipefail

# 启动冒烟（v2 纯 Swift）：debug 二进制起 N 秒，不退出、日志无崩溃签名即过。
# 用 FAKE_DATA 沙盘数据，绝不碰真实 ~/.agents。
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

"$ROOT_DIR/scripts/swiftpm.sh" build --package-path "$ROOT_DIR/swift-app"

POPSKILL_FAKE_DATA=1 POPSKILL_NO_AUTOCHECK=1 \
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
