#!/usr/bin/env bash
set -euo pipefail

# 一键发版（v2.8 起的唯一发版入口）。版本/build 单源在仓库根 VERSION 文件。
#
# 链路（任一步失败立即停，无静默步骤——坑 #16）：
#   预检 → 质量门（shell 语法 / l10n / 全部测试）→ package-dev-app
#   → Sparkle 版本断言 → bundle 冷启 smoke → notarize(app) → DMG 签名+公证
#   → 发版 commit（不含 appcast）→ push main → **等云 CI 绿**（发布门）
#   → tag → gh release（DMG 资产就位）→ appcast commit + push → 终检
#
# v2.18 改序（审查 P1-05）：资产公开以前必须本地测试全绿 + 云 CI 通过——
# 旧序「先 tag/Release 最后 push main」让 DMG 在 CI 结论之前就能被下载。
# appcast 仍最后上线：它由 Pages 从 main 服务，晚于 gh release 才能保证
# 用户看到新版的瞬间 DMG 一定可下（原坑 #16 的时序原则不变）。
#
# 发版步骤：
#   1. 编辑 VERSION（第一行版本号，第二行 build = 上一版 +1）
#   2. 写 docs/release/v<版本>.md（第一行 "# v<版本> — 标题"，后接若干段落）
#   3. scripts/release.sh —— VERSION 与发版说明不用先提交，脚本随发版 commit 一并提交
#
# 中途失败重跑：每段幂等——发版 commit 已在 HEAD 就不再构建/提交，
# tag/release/appcast 各自「已存在即跳过」，从断点续发。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# CLAUDE.md「凭证」表的终生值，env 可覆盖
export POPSKILL_DEVELOPER_ID_APPLICATION="${POPSKILL_DEVELOPER_ID_APPLICATION:-Developer ID Application: JIE MIAO (8KTT7H3QEH)}"
export POPSKILL_NOTARY_KEYCHAIN_PROFILE="${POPSKILL_NOTARY_KEYCHAIN_PROFILE:-popskill-notarize}"
# 打包内 Sparkle 的最低批准版本（低于它 = 带已知安全洞发布，直接失败）
MIN_SPARKLE="2.9.4"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { echo "release: $*" >&2; exit 1; }

# ── 预检 ────────────────────────────────────────────────

step "预检"
VERSION="$(sed -n '1p' VERSION)"
BUILD="$(sed -n '2p' VERSION)"
[[ -n "$VERSION" && -n "$BUILD" ]] || die "VERSION 文件不完整（第一行版本号，第二行 build）"
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "build 必须是纯数字，拿到 $BUILD"
NOTES_MD="docs/release/v$VERSION.md"
[[ -f "$NOTES_MD" ]] || die "缺少发版说明 ${NOTES_MD}（第一行 '# v$VERSION — 标题'）"

[[ "$(git branch --show-current)" == "main" ]] || die "必须在 main 分支发版"

# 幂等续发判定：发版 commit 已在 HEAD（上次跑到中途失败）就不再构建/提交
RELEASED_COMMIT=false
if [[ "$(git log -1 --format=%s)" == "v$VERSION release" ]]; then
  RELEASED_COMMIT=true
  echo "发版 commit 已在 HEAD：进入续发模式（跳过构建与提交，逐段补缺）"
fi
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  [[ "$(git rev-parse "v$VERSION")" == "$(git rev-parse HEAD)" ]] \
    || die "tag v$VERSION 已存在且不在 HEAD——这不是续发，检查版本号"
fi

if [[ "$RELEASED_COMMIT" == false ]]; then
  # 只允许 VERSION 与本版发版说明未提交（脚本会随发版 commit 一并提交）
  DIRTY="$(git status --porcelain | grep -vE ' (VERSION|docs/release/v[0-9.]+\.md)$' || true)"
  [[ -z "$DIRTY" ]] || die $'工作树有发版文件之外的改动：\n'"$DIRTY"
  grep -q "<title>v$VERSION</title>" docs/appcast.xml && die "appcast 已有 v${VERSION}（但发版 commit 不在 HEAD——状态不一致，人工检查）"
  TOP_BUILD="$(grep -o 'sparkle:version="[0-9]*"' docs/appcast.xml | head -1 | grep -o '[0-9]*')"
  [[ -n "$TOP_BUILD" && "$BUILD" -gt "$TOP_BUILD" ]] \
    || die "build $BUILD 必须严格大于 appcast 顶部的 $TOP_BUILD"
  echo "v$VERSION (build $BUILD) · 上一版 build $TOP_BUILD"
fi

command -v gh >/dev/null || die "需要 gh CLI"
gh auth status >/dev/null 2>&1 || die "gh 未登录"
# 坑 #6：notarytool profile 会被清掉，发版前必验
xcrun notarytool history --keychain-profile "$POPSKILL_NOTARY_KEYCHAIN_PROFILE" \
  >/dev/null 2>&1 || die "notarytool keychain profile 失效——重跑 store-credentials"
echo "凭证就绪"

# ── 质量门（v2.18：测试不绿，任何东西都不公开）─────────────

DMG="build/Popskill-$VERSION.dmg"
if [[ "$RELEASED_COMMIT" == true ]]; then
  [[ -f "$DMG" ]] || die "续发模式需要现成的 ${DMG}——没有就 git reset 掉发版 commit 重新全跑"
else

step "质量门：shell 语法 / l10n 漂移 / 全部单元测试"
for script in scripts/*.sh; do bash -n "$script"; done
echo "  ✓ scripts/*.sh 语法"
scripts/gen-l10n.sh --check
scripts/test.sh
echo "  ✓ 测试全绿"

# ── 构建 + 公证 + DMG ───────────────────────────────────

step "构建 .app（版本从 VERSION 注入）"
scripts/package-dev-app.sh
# 残留的 POPSKILL_APP_VERSION env 会让 package-dev-app 静默打出错版——产物复检
GOT_V="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Popskill.app/Contents/Info.plist)"
GOT_B="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/Popskill.app/Contents/Info.plist)"
[[ "$GOT_V" == "$VERSION" && "$GOT_B" == "$BUILD" ]] \
  || die "产物版本 $GOT_V/$GOT_B ≠ VERSION 文件 ${VERSION}/${BUILD}（环境里残留 POPSKILL_APP_VERSION/BUILD？）"

step "Sparkle 版本断言（≥ ${MIN_SPARKLE}，审查 P1-01）"
SPARKLE_V="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  build/Popskill.app/Contents/Frameworks/Sparkle.framework/Resources/Info.plist)"
[[ "$(printf '%s\n%s\n' "$MIN_SPARKLE" "$SPARKLE_V" | sort -V | head -1)" == "$MIN_SPARKLE" ]] \
  || die "打包内 Sparkle $SPARKLE_V 低于批准基线 ${MIN_SPARKLE}——先升级依赖再发版"
echo "  ✓ Sparkle $SPARKLE_V"

step "bundle 冷启动 smoke（干净机器复现，坑 #17）"
scripts/smoke-bundle.sh 2

step "公证 .app"
scripts/notarize.sh

step "打 DMG"
scripts/package-dmg.sh
mv -f build/Popskill.dmg "$DMG"

step "签名 + 公证 DMG"
codesign --force --sign "$POPSKILL_DEVELOPER_ID_APPLICATION" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$POPSKILL_NOTARY_KEYCHAIN_PROFILE" --wait \
  | tee /tmp/popskill-notary-dmg.log
grep -q "status: Accepted" /tmp/popskill-notary-dmg.log || die "DMG 公证未通过"
xcrun stapler staple "$DMG"

# ── README 直链跟版（坑：资产名随版本变，不跟会 404）────

step "同步双语 README 装机直链与当前版本"
DMG_LEN="$(stat -f%z "$DMG")"
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

step "发版 commit（appcast 刻意不在这次——DMG 就位后单独上线）"
git add VERSION README.md README.en.md "$NOTES_MD"
if git diff --cached --quiet; then
  # CI 门失败后追修复 commit 重跑的场景：发版文件上一轮已提交，构建照跑、commit 跳过
  echo "  发版文件无变化（此前已提交），跳过 commit"
else
  git commit -m "v$VERSION release"
fi

fi   # RELEASED_COMMIT 续发跳到这里

# ── 发布门：先 CI 绿，再公开任何资产（审查 P1-05）─────────

step "push main（触发云 CI；此刻无 tag/无 Release/appcast 未动）"
git push origin main

step "等待 GitHub CI 通过——绿了才公开资产"
HEAD_SHA="$(git rev-parse HEAD)"
RUN_ID=""
for i in $(seq 1 30); do
  RUN_ID="$(gh run list --workflow CI --branch main --limit 10 --json databaseId,headSha \
    --jq "[.[] | select(.headSha==\"$HEAD_SHA\")][0].databaseId" 2>/dev/null || true)"
  [[ -n "$RUN_ID" && "$RUN_ID" != "null" ]] && break
  RUN_ID=""
  echo "  等 CI run 出现（$i/30）…"
  sleep 5
done
[[ -n "$RUN_ID" ]] || die "push 后 150s 没等到 CI run——检查仓库 Actions 是否被禁用"
gh run watch "$RUN_ID" --exit-status \
  || die "云 CI 未通过——发布中止（tag/DMG/appcast 都还没公开，修好重跑即续发）"
echo "  ✓ CI run $RUN_ID 通过"

# ── 公开资产（幂等，可续发）────────────────────────────

step "tag + push tag"
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "  tag v$VERSION 已存在，跳过（续发）"
else
  git tag "v$VERSION"
fi
git push origin "v$VERSION"

step "gh release create"
if gh release view "v$VERSION" --repo maojiebc/majia-Popskill >/dev/null 2>&1; then
  echo "  release v$VERSION 已存在，跳过（续发）"
else
  TITLE="$(head -1 "$NOTES_MD" | sed 's/^# *//')"
  gh release create "v$VERSION" "$DMG" --title "$TITLE" --notes-file "$NOTES_MD"
fi

# ── appcast 最后上线（此刻 DMG 一定可下，不留半发布态）───

step "appcast 置顶插入（带断言）+ 上线"
if grep -q "<title>v$VERSION</title>" docs/appcast.xml; then
  echo "  appcast 已含 v${VERSION}，跳过插入（续发）"
else
  SIGN_OUT="$(scripts/sparkle-sign-update.sh "$DMG")"
  echo "$SIGN_OUT"
  ED_SIG="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGN_OUT" | head -1)"
  [[ -n "$ED_SIG" ]] || die "没拿到 edSignature"
  DMG_LEN="$(stat -f%z "$DMG")"
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
  PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
  scripts/append-appcast.py --version "$VERSION" --build "$BUILD" \
    --sig "$ED_SIG" --length "$DMG_LEN" --pubdate "$PUBDATE" --html-notes - <<<"$HTML_NOTES"
fi
git add docs/appcast.xml
if git diff --cached --quiet; then
  echo "  appcast 无待提交变化（续发）"
else
  git commit -m "v$VERSION appcast 上线"
fi
git push origin main

# ── 终检（坑 #8/#16：Pages 可能被禁用 / CDN max-age=600）──

step "终检 appcast 与装机直链"
APPCAST_URL="https://maojiebc.github.io/majia-Popskill/appcast.xml"
ok=false
for i in $(seq 1 20); do
  # 不能用 grep -q：命中后它会提前关管道，curl 收到 SIGPIPE 返回 23；
  # 在本脚本的 pipefail 下反而被误判成失败，曾让每次终检都白等 10 分钟。
  if curl -sf "$APPCAST_URL" | grep -F "<title>v$VERSION</title>" >/dev/null; then
    ok=true; break
  fi
  echo "  appcast 还没刷新（第 $i/20 次），30s 后重试——Pages 构建 + CDN 缓存最长 ~10 分钟"
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
