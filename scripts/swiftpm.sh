#!/usr/bin/env bash
set -euo pipefail

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/popskill-swiftpm-home.XXXXXX")"

cleanup() {
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT

# CLT 不带完整 XCTest / SwiftUI macro 插件。发版和测试都必须默认走完整 Xcode，
# 不能依赖调用机器当时的全局 xcode-select 状态。
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode.app ]]; then
    DEVELOPER_DIR=/Applications/Xcode.app
  elif [[ -d /Applications/Xcode-beta.app ]]; then
    DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  else
    echo "error: 找不到 /Applications/Xcode.app（CLT 不能发版/构建）" >&2
    exit 1
  fi
fi
DEVELOPER_DIR="$DEVELOPER_DIR" \
HOME="$TMP_HOME" \
GIT_CONFIG_GLOBAL=/dev/null \
GIT_CONFIG_NOSYSTEM=1 \
GIT_TERMINAL_PROMPT=0 \
swift "$@"
