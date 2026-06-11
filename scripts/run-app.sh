#!/usr/bin/env bash
set -euo pipefail

# 构建并启动 debug 实例（v2 纯 Swift，无 sidecar）。
# 调试钩子（POPSKILL_FAKE_DATA=1 等）直接前缀在本脚本前即可。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/swiftpm.sh" build --package-path "$ROOT_DIR/swift-app"
exec "$ROOT_DIR/swift-app/.build/debug/Popskill"
