#!/usr/bin/env bash
set -euo pipefail

# 跑全部 Swift 测试。CLT 工具链没有 XCTest（坑 #9），必须指向 Xcode——
# 这个前提封装在这里，别再在命令行里手敲 DEVELOPER_DIR。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app}" \
  swift test --package-path "$ROOT_DIR/swift-app" "$@"
