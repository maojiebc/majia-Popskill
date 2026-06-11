#!/usr/bin/env bash
set -euo pipefail

# v2 开发构建：纯 Swift（skill-cli/cc-switch 已随 v1 移除）。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Building SwiftUI app"
"$ROOT_DIR/scripts/swiftpm.sh" build --package-path "$ROOT_DIR/swift-app"

echo "==> Running Swift tests"
"$ROOT_DIR/scripts/test.sh"

echo "==> Done"
