#!/usr/bin/env bash
set -euo pipefail

# 一键发版（v2.8 起的唯一发版入口）。版本/build 单源在仓库根 VERSION 文件。
#
# 链路（任一步失败立即停，无静默步骤——坑 #16）：
#   预检 → package-dev-app → notarize(app) → package-dmg → 签名+公证 DMG
#   → sparkle 签名 → append-appcast.py（带断言）→ 同步双语 README
#   → git commit + tag + push → gh release create → 终检 appcast/直链
#
# 发版步骤：
#   1. 编辑 VERSION（第一行版本号，第二行 build = 上一版 +1）
#   2. 写 docs/release/v<版本>.md（第一行 "# v<版本> — 标题"，后接若干段落）
#   3. scripts/release.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# CLAUDE.md「凭证」表的终生值，env 可覆盖
export POPSKILL_DEVELOPER_ID_APPLICATION="${POPSKILL_DEVELOPER_ID_APPLICATION:-Developer ID Application: JIE MIAO (8KTT7H3QEH)}"
export POPSKILL_NOTARY_KEYCHAIN_PROFILE="${POPSKILL_NOTARY_KEYCHAIN_PROFILE:-popskill-notarize}"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { echo "release: $*" >&2; exit 1; }

# ── 预检 ────────────────────────────────────────────────

step "预检"
VERSION="$(sed -n '1p' VERSION)"
BUILD="$(sed -n '2p' VERSION)"
[[ -n "$VERSION" && -n "$BUILD" ]] || die "VERSION 文件不完整（第一行版本号，第二行 build）"
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "build 必须是纯数字，拿到 $BUILD"
NOTES_MD="docs/release/v$VERSION.md"
[[ -f "$NOTES_MD" ]] || die "缺少发版说明 $NOTES_MD（第一行 '# v$VERSION — 标题'）"

[[ "$(git branch --show-current)" == "main" ]] || die "必须在 main 分支发版"
[[ -z "$(git status --porcelain)" ]] || die "工作树不干净，先提交或 stash"
git tag | grep -qx "v$VERSION" && die "tag v$VERSION 已存在"
grep -q "<title>v$VERSION</title>" docs/appcast.xml && die "appcast 已有 v$VERSION"

TOP_BUILD="$(grep -o 'sparkle:version="[0-9]*"' docs/appcast.xml | head -1 | grep -o '[0-9]*')"
[[ -n "$TOP_BUILD" && "$BUILD" -gt "$TOP_BUILD" ]] \
  || die "build $BUILD 必须严格大于 appcast 顶部的 $TOP_BUILD"

command -v gh >/dev/null || die "需要 gh CLI"
gh auth status >/dev/null 2>&1 || die "gh 未登录"
# 坑 #6：notarytool profile 会被清掉，发版前必验
xcrun notarytool history --keychain-profile "$POPSKILL_NOTARY_KEYCHAIN_PROFILE" \
  >/dev/null 2>&1 || die "notarytool keychain profile 失效——重跑 store-credentials"
echo "v$VERSION (build $BUILD) · 上一版 build $TOP_BUILD · 凭证就绪"

# ── 构建 + 公证 + DMG ───────────────────────────────────

step "构建 .app（版本从 VERSION 注入）"
scripts/package-dev-app.sh

step "公证 .app"
scripts/notarize.sh

step "打 DMG"
scripts/package-dmg.sh
DMG="build/Popskill-$VERSION.dmg"
mv -f build/Popskill.dmg "$DMG"

step "签名 + 公证 DMG"
codesign --force --sign "$POPSKILL_DEVELOPER_ID_APPLICATION" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$POPSKILL_NOTARY_KEYCHAIN_PROFILE" --wait \
  | tee /tmp/popskill-notary-dmg.log
grep -q "status: Accepted" /tmp/popskill-notary-dmg.log || die "DMG 公证未通过"
xcrun stapler staple "$DMG"

# ── Sparkle 签名 + appcast ──────────────────────────────

step "Sparkle 签名"
SIGN_OUT="$(scripts/sparkle-sign-update.sh "$DMG")"
echo "$SIGN_OUT"
ED_SIG="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGN_OUT" | head -1)"
[[ -n "$ED_SIG" ]] || die "没拿到 edSignature"
DMG_LEN="$(stat -f%z "$DMG")"

step "生成 HTML 发版说明（从 $NOTES_MD）"
HTML_NOTES="$(python3 - "$NOTES_MD" <<'PY'
import html, re, sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text().strip().split("\n")
out = []
para = []
def flush():
    if para:
        t = html.escape(" ".join(para))
        t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
        out.append(f"        <p>{t}</p>")
        para.clear()
for ln in lines:
    s = ln.strip()
    if s.startswith("#"):
        flush()
        out.append(f"        <h2>{html.escape(s.lstrip('# '))}</h2>")
    elif not s:
        flush()
    else:
        para.append(s.lstrip("- "))
flush()
print("\n".join(out))
PY
)"
echo "$HTML_NOTES"

step "appcast 置顶插入（带断言）"
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
scripts/append-appcast.py --version "$VERSION" --build "$BUILD" \
  --sig "$ED_SIG" --length "$DMG_LEN" --pubdate "$PUBDATE" --html-notes - <<<"$HTML_NOTES"

# ── README 直链跟版（坑：资产名随版本变，不跟会 404）────

step "同步双语 README 装机直链与当前版本"
DMG_MB="$(python3 -c "print(f'{$DMG_LEN/1024/1024:.1f}')")"
python3 - "$VERSION" "$DMG_MB" <<'PY'
import re, sys, pathlib
version, mb = sys.argv[1], sys.argv[2]
for name in ("README.md", "README.en.md"):
    p = pathlib.Path(name)
    s = p.read_text()
    s = re.sub(r"Popskill-[0-9.]+\.dmg", f"Popskill-{version}.dmg", s)
    s = re.sub(r"releases/tag/v[0-9.]+", f"releases/tag/v{version}", s)
    s = re.sub(r"\[v[0-9.]+\]\(https://github\.com/maojiebc/majia-Popskill/releases/tag",
               f"[v{version}](https://github.com/maojiebc/majia-Popskill/releases/tag", s)
    s = re.sub(r"（[0-9.]+ MB，", f"（{mb} MB，", s)
    s = re.sub(r"\([0-9.]+ MB, ", f"({mb} MB, ", s)
    p.write_text(s)
    print(f"  {name} → v{version} / {mb} MB")
PY

# ── git + GitHub Release ────────────────────────────────

step "commit + tag + push"
git add VERSION docs/appcast.xml README.md README.en.md "$NOTES_MD"
git commit -m "v$VERSION release"
git tag "v$VERSION"
git push origin main
git push origin "v$VERSION"

step "gh release create"
TITLE="$(head -1 "$NOTES_MD" | sed 's/^# *//')"
gh release create "v$VERSION" "$DMG" --title "$TITLE" --notes-file "$NOTES_MD"

# ── 终检（坑 #8/#16：Pages 可能被禁用 / CDN max-age=600）──

step "终检 appcast 与装机直链"
APPCAST_URL="https://maojiebc.github.io/majia-Popskill/appcast.xml"
ok=false
for i in $(seq 1 12); do
  if curl -sf "$APPCAST_URL" | grep -q "<title>v$VERSION</title>"; then
    ok=true; break
  fi
  echo "  appcast 还没刷新（第 $i/12 次），30s 后重试——Pages 构建 + CDN 缓存最长 ~10 分钟"
  sleep 30
done
if [[ "$ok" == true ]]; then
  echo "  ✓ appcast 已含 v$VERSION"
else
  echo "  ⚠ appcast 10 分钟内未刷新——手动验证：curl -s $APPCAST_URL | grep v$VERSION" >&2
  echo "    若 30 分钟后仍无：检查 repo Settings → Pages 是否被禁用（坑 #8）" >&2
fi
DL="https://github.com/maojiebc/majia-Popskill/releases/latest/download/Popskill-$VERSION.dmg"
curl -sfIL "$DL" >/dev/null && echo "  ✓ README 装机直链可达" || die "装机直链 404：$DL"

step "v$VERSION 发版完成"
