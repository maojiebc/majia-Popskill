#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SECONDS="${1:-3}"
APP_DIR="$ROOT_DIR/build/Popskill.app"
APP_BIN="$APP_DIR/Contents/MacOS/Popskill"
BUNDLED_SPARKLE="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
WINDOW_CHECKER="$(mktemp "${TMPDIR:-/tmp}/popskill-window-check.XXXXXX.swift")"
APP_PID=""

running_app_pids() {
  # 带 /build/ 段的后缀匹配：避开 APFS 大小写漂移（Projects ↔ projects 全路径
  # pgrep 会漏），同时绝不命中 /Applications 里用户正在跑的正式版
  pgrep -f "/build/Popskill.app/Contents/MacOS/Popskill" 2> /dev/null || true
}

# v2.13.1 起：冷启前把 .build 里的 release 资源 bundle 移开，逼打包的 .app 只能用
# 自己 Contents/Resources 的副本——精确复现「别人干净机器」的环境。否则像 v2.13.0
# 那样，Bundle.module 的 .build 绝对路径兜底会在本机掩盖「.app 内找不到资源」的崩溃。
HIDDEN_BUNDLES=()
hide_build_bundles() {
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    mv "$b" "$b.smoke-hidden" && HIDDEN_BUNDLES+=("$b")
  done < <(find "$ROOT_DIR/swift-app/.build" -name "Popskill_Popskill.bundle" -path "*release*" -maxdepth 4 2> /dev/null || true)
}
restore_build_bundles() {
  for b in "${HIDDEN_BUNDLES[@]:-}"; do
    [[ -n "$b" && -d "$b.smoke-hidden" ]] && mv "$b.smoke-hidden" "$b"
  done
}

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2> /dev/null; then
    kill "$APP_PID" 2> /dev/null || true
    wait "$APP_PID" 2> /dev/null || true
  fi
  restore_build_bundles
  rm -f "$WINDOW_CHECKER"
}
trap cleanup EXIT

for existing_pid in $(running_app_pids); do
  kill "$existing_pid" 2> /dev/null || true
done

"$ROOT_DIR/scripts/package-dev-app.sh" > /dev/null

if [[ ! -x "$APP_BIN" ]]; then
  echo "missing bundled app executable: $APP_BIN" >&2
  exit 1
fi

# v2 断言：Info.plist 版本必须与 VERSION 单源一致（曾人肉同步 6+ 处）
EXPECTED_VERSION="$(sed -n '1p' "$ROOT_DIR/VERSION")"
EXPECTED_BUILD="$(sed -n '2p' "$ROOT_DIR/VERSION")"
PLIST="$APP_DIR/Contents/Info.plist"
GOT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
GOT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
if [[ "$GOT_VERSION" != "$EXPECTED_VERSION" || "$GOT_BUILD" != "$EXPECTED_BUILD" ]]; then
  echo "bundle 版本 ($GOT_VERSION/$GOT_BUILD) 与 VERSION 文件 ($EXPECTED_VERSION/$EXPECTED_BUILD) 不一致" >&2
  exit 1
fi

if otool -L "$APP_BIN" | grep -q "Sparkle.framework"; then
  if [[ ! -f "$BUNDLED_SPARKLE" ]]; then
    echo "missing bundled Sparkle framework binary: $BUNDLED_SPARKLE" >&2
    exit 1
  fi

  if ! otool -l "$APP_BIN" | grep -q "@executable_path/../Frameworks"; then
    echo "missing app bundle Frameworks rpath for Sparkle" >&2
    exit 1
  fi
fi

cat > "$WINDOW_CHECKER" <<'SWIFT'
import CoreGraphics
import Foundation

func numericValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let double = value as? Double {
        return double
    }
    if let int = value as? Int {
        return Double(int)
    }
    return nil
}

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let hasMainWindow = windows.contains { window in
    guard
        (window[kCGWindowOwnerName as String] as? String) == "Popskill",
        let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let width = numericValue(bounds["Width"]),
        let height = numericValue(bounds["Height"])
    else {
        return false
    }

    return width >= 600 && height >= 400
}

exit(hasMainWindow ? 0 : 1)
SWIFT

hide_build_bundles   # 复现干净机器：.app 不能靠 .build 绝对路径找资源
open -n "$APP_DIR"

for _ in {1..50}; do
  APP_PID="$(running_app_pids | head -n 1)"
  if [[ -n "$APP_PID" ]]; then
    break
  fi
  sleep 0.1
done

if [[ -z "$APP_PID" ]]; then
  echo "Popskill bundle did not start through LaunchServices" >&2
  exit 1
fi

sleep "$RUN_SECONDS"

if ! kill -0 "$APP_PID" 2> /dev/null; then
  echo "Popskill bundle exited during launch smoke" >&2
  exit 1
fi

if ! swift "$WINDOW_CHECKER"; then
  echo "Popskill bundle did not create a visible main window" >&2
  exit 1
fi

echo "Popskill bundle smoke ok"
