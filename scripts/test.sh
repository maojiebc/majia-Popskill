#!/usr/bin/env bash
set -euo pipefail

# 跑全部 Swift 测试。CLT 工具链没有 XCTest（坑 #9），必须指向 Xcode——
# 这个前提封装在这里，别再在命令行里手敲 DEVELOPER_DIR。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode.app ]]; then
    DEVELOPER_DIR=/Applications/Xcode.app
  elif [[ -d /Applications/Xcode-beta.app ]]; then
    DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  else
    echo "error: 找不到 /Applications/Xcode.app（CLT 不能跑测试）" >&2
    exit 1
  fi
fi
export DEVELOPER_DIR

# 先编出测试包。Xcode 27 / SwiftPM 把 Sparkle 放到 Products/Debug/Sparkle.framework，
# 测试包 rpath 却指向 PackageFrameworks——不补软链会 dlopen 失败。
swift build --package-path "$ROOT_DIR/swift-app" --build-tests
for debug in \
  "$ROOT_DIR/swift-app/.build/out/Products/Debug" \
  "$ROOT_DIR/swift-app/.build/arm64-apple-macosx/debug"
do
  if [[ -d "$debug/Sparkle.framework" ]]; then
    mkdir -p "$debug/PackageFrameworks"
    ln -sfn ../Sparkle.framework "$debug/PackageFrameworks/Sparkle.framework"
  fi
done

swift test --package-path "$ROOT_DIR/swift-app" --skip-build "$@"
