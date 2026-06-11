#!/usr/bin/env bash
set -euo pipefail

# 本地 CI（v2 纯 Swift 链）：语法 → 构建+测试 → 启动冒烟 → bundle 冒烟
# → 截图资产 → 发布工件冒烟。任何一步失败立即停。
# v1 的 cc-switch/skill-cli 预检已随架构删除。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      cat <<'USAGE'
Usage: scripts/ci-local.sh

Runs the local verification suite (v2, pure Swift):
  - shell script syntax check
  - Swift build + full test suite (scripts/test.sh)
  - native launch smoke (FAKE_DATA sandbox)
  - .app bundle launch smoke (asserts version == VERSION file)
  - screenshot asset smoke (assets actually referenced by README)
  - release artifact smoke (DMG + manifest)
USAGE
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 64
      ;;
  esac
done

echo "==> Local CI: shell script syntax"
for script in "$ROOT_DIR"/scripts/*.sh; do
  bash -n "$script"
done

echo "==> Local CI: build and tests"
"$ROOT_DIR/scripts/dev-build.sh"

echo "==> Local CI: native app launch smoke"
"$ROOT_DIR/scripts/smoke-app.sh" 2

echo "==> Local CI: bundled app launch smoke"
"$ROOT_DIR/scripts/smoke-bundle.sh" 2

echo "==> Local CI: screenshot asset smoke"
"$ROOT_DIR/scripts/smoke-screenshots.sh"

echo "==> Local CI: release artifact smoke"
"$ROOT_DIR/scripts/smoke-release.sh"

echo "==> Local CI: ok"
