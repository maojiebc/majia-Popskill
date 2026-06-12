#!/bin/bash
# 本地化目录编译（v2.12）：
#   权威源 = swift-app/l10n/Localizable.xcstrings（人工/AI 编辑这一个文件）
#   产物   = swift-app/Sources/Popskill/Resources/{zh-Hans,en}.lproj/Localizable.strings
#
# 为什么预编译提交进库：SPM 5.9 纯命令行 swift build 不编译 .xcstrings
# （只会原样拷贝），lproj/.strings 是 5.3 起就稳定支持的经典路径——
# 预编译让 swift build / swift test / CI 全部零额外依赖。
#
# 用法：
#   scripts/gen-l10n.sh           # 重新编译（改完 xcstrings 后跑）
#   scripts/gen-l10n.sh --check   # 漂移检查（CI 用）：catalog 与产物不一致则失败
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT_DIR/swift-app/l10n/Localizable.xcstrings"
OUT_DIR="$ROOT_DIR/swift-app/Sources/Popskill/Resources"
XCRUN=(env DEVELOPER_DIR=/Applications/Xcode.app xcrun)   # CLT 没有 xcstringstool

die() { echo "error: $*" >&2; exit 1; }

[[ -f "$CATALOG" ]] || die "找不到 $CATALOG"

if [[ "${1:-}" == "--check" ]]; then
  TMP="$(mktemp -d /tmp/popskill-l10n-check.XXXXXX)"
  trap 'rm -rf "$TMP"' EXIT
  "${XCRUN[@]}" xcstringstool compile "$CATALOG" --output-directory "$TMP"
  for lproj in "$TMP"/*.lproj; do
    name="$(basename "$lproj")"
    cmp -s "$lproj/Localizable.strings" "$OUT_DIR/$name/Localizable.strings" \
      || die "本地化产物漂移：$name 与 catalog 不一致——跑 scripts/gen-l10n.sh 重新生成"
  done
  # 反向：产物里不许有 catalog 没有的语言
  for lproj in "$OUT_DIR"/*.lproj; do
    name="$(basename "$lproj")"
    [[ -d "$TMP/$name" ]] || die "产物有多余语言 $name（catalog 里没有）"
  done
  echo "l10n ok — catalog 与产物一致"
  exit 0
fi

"${XCRUN[@]}" xcstringstool compile "$CATALOG" --output-directory "$OUT_DIR"
echo "已生成："
ls "$OUT_DIR"/*.lproj/Localizable.strings
