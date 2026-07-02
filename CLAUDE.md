# Popskill — Project Notes for Claude

> 项目快照 — 让任何 Claude Code session 在这个目录下都能 5 秒 catch up。

## 是什么

**Popskill** = Mac 上 AI 能力的统一控制台。Skills × Tools 矩阵，把 Claude Code 和 Codex 的 skill / agent / CLI / MCP 摆成一张表，一键开关 + 链接健康 + iCloud sync + Sparkle 自动更新。

公开 repo：https://github.com/maojiebc/majia-Popskill

## 已发布版本

| 版本 | 日期 | 主线 |
|---|---|---|
| v1.0.0 | 2026-05-16 | 第一次签名 + 公证 DMG |
| v1.0.1 | 2026-05-16 | Sparkle 自动更新接通 |
| v1.0.2 | 2026-05-17 | SSOT 路径修复 + error toast + 30s TTL |
| v1.0.3 | 2026-05-17 | UI tokens + hover state + O(1) update lookup |
| v1.0.4 | 2026-05-17 | 跳转修复 + 删除确认 + Insights streaming + 6 新单测 |
| v1.0.5 | 2026-05-21 | Package 矩阵一等公民 + Inspector tabs(Overview/README/Usage/Version/Sync/Metadata) + Spotlight CJK 别名 + 用量指标铺满 |
| v1.1.0 | 2026-06-07 | **紧凑账本 redesign** — 全局暖纸色账本 UI + 整页 Inspector + 新建/组装/修复/源/设置全屏重做 + IA 收成 6 目的地 |

## 项目结构

```
popskill/
├── skill-cli/                            Rust sidecar (CC Switch as path dep, zero fork)
├── swift-app/Sources/Popskill/
│   ├── App/PopskillStore.swift           @MainActor @Observable, 单 store
│   ├── Models/                           Skill / MatrixCapability / SkillGrouping
│   ├── Views/                            Matrix(账本) / InspectorView(整页) / Fix / Sources / Create / Compose / Settings / LedgerChrome(标题栏+固定侧栏) / LedgerComponents(字形/彩标/覆盖条)
│   ├── Design/PopskillColors.swift       named tokens (popSurface / popControlFill / ...)
│   └── Resources/{AppIcon.icns, *.lproj/Localizable.strings}
├── cc-switch/                            submodule, sidecar 依赖
├── docs/
│   ├── appcast.xml                       Sparkle feed (GitHub Pages 服务)
│   ├── release/v{N}.md                   每版 release notes
│   └── screenshots/                      landing page 资源
├── scripts/
│   ├── package-dev-app.sh                .app bundle 组装 (含 Info.plist heredoc + Sparkle 烤入)
│   ├── notarize.sh                       sign + 深度签 Sparkle + notarize + staple
│   ├── package-dmg.sh                    hdiutil DMG
│   ├── sparkle-sign-update.sh            EdDSA 签名 wrapper
│   ├── ci-local.sh                       全 pipeline
│   └── ...
├── README.md / README.en.md              landing-page 形式
├── SECURITY.md / .ota-deny-list.txt
└── build/                                gitignored, 经常 rm
```

## 凭证 / 路径（设了一次终生有效）

| 项 | 值 |
|---|---|
| Apple Team ID | `8KTT7H3QEH` (JIE MIAO) |
| Apple ID | `306186636@qq.com` |
| Codesign identity | `Developer ID Application: JIE MIAO (8KTT7H3QEH)` |
| notarytool keychain profile | `popskill-notarize` |
| Bundle ID | `com.majia.popskill` |
| Sparkle 公钥 (Info.plist) | `h7HOqj21MlKe5UJFFa9GKBmV6MtdlcDSeJa9rmAguq8=` |
| Sparkle 私钥 | macOS Keychain (Sparkle Account) — **务必备份** |
| Developer ID 私钥 | `~/.popskill-signing/app.key` — **务必备份** |
| GitHub Pages | https://maojiebc.github.io/majia-Popskill/ |
| Appcast URL | https://maojiebc.github.io/majia-Popskill/appcast.xml |

## 关键架构事实

- **真实 SSOT** = `~/.cc-switch/skills/`，**不是** `~/.agents/skills/`。`.agents/skills` 是 v0.3 文档里画的迁移目标，sidecar 没动。v1.1.x 计划迁移。
- **store.skills vs store.capabilities** — `skills` 只是 Skill；`capabilities` = skills + localAgents，是矩阵真正消费的数据源。新代码默认用 `capabilities`。
- **store.hasPendingUpdate(for:)** 是 O(1) 用 `updateSkillIDs: Set<String>` cache，不要再写 `store.updates.contains` 扫描。
- **`@MainActor` 标在 PopskillStore 类上**，所有 mutating helpers / extensions / filters 必须显式 `@MainActor`。
- **errorMessage 现在被 RootView 全局 toast 读取**（v1.0.2 之前是写了没人看）。任何 sidecar 调用失败 set 这个就行。
- **refresh TTL = 30s**。Sources view 用 `store.refreshXXX(force: Bool)` helper；手动按钮 force=true，自动 .task force=false。

### v1.1.0 紧凑账本重设计（关键变化，别按旧印象改）
- **全局暖纸色**：`PopskillColors` 的 `pop*` 令牌已从系统色**重指为固定亮色 hex**（暖纸 #fafaf8 / 墨黑 #111 / 电光蓝 #1f4ed8）；`PopskillApp` 加了 `.preferredColorScheme(.light)` + `.tint(.popAccent)`。**app 不再跟随系统深色**。
- **窗口外壳是自定义的，不是 NavigationSplitView**：`RootView` = `VStack{ LedgerTitlebar; HStack{ LedgerSidebar(固定 222); detailArea } }.ignoresSafeArea(.top)` + `PopskillApp` 的 `.windowStyle(.hiddenTitleBar)`。侧栏**纯文字、无折叠**（`LedgerSidebar` in `LedgerChrome.swift`）。
- **IA = 6 目的地**：`SidebarSelection` = matrix / fix / sources / create / compose / settings。`insights / backups / idle` 的 View 文件还在但**已从路由摘除**；`health` → `fix`，`updates` 并入 `sources`。
- **点行 → 整页 InspectorView**（`store.inspectorOpen` 时 `MatrixView.body` 整页切到 `InspectorView`），**不再是 `.inspector` 侧板**。
- **矩阵状态格是可点击的 `●—◐✕` 字形**（`LedgerStatusGlyph`），不是 `AppToggle` 开关；类型彩标 `LedgerTypeTag`、套装覆盖 `LedgerCoverageBar`、底部 `LedgerStatusBar` 都在 `Views/LedgerComponents.swift`。
- **后端缺口（UI 搭好但没接 sidecar）**：Sources 注册表在线浏览、Fix 修复执行、Settings 安装/配额、Inspector 的 tab 切换 —— 都是结构占位。

### v1.1.x 当前迭代（2026-07-02）
- **Settings 已从 mock 转成实况控制台**：Connect tab 使用 `ToolConnection` 合并 `TargetAppRegistry`、`agent-targets` 和本机路径 fallback，显示 Claude / Codex / Gemini / OpenCode / Hermes 的 Detected / Missing；Install / Quota 偏好写入 `UserDefaults`。
- **同步按钮已走真实 Store action**：Settings Sync tab 调 `store.runSync(...)`，会更新 `lastSyncResult`、`lastSyncAt`，并在 pull 成功后刷新核心 inventory。
- **About 诊断导出已落地**：`store.exportDiagnosticsReport()` 写 `~/Downloads/popskill-diagnostics-*.json`，导出 skills/packages/sources/sync/tool connections/link health/usage 状态，并把 home 路径脱敏成 `~`。
- **本轮测试基线**：Swift 全量测试已增至 **173/173**，在 `/tmp/popskill-swift-app-test` 无 Git 临时目录通过；原仓库目录里的 SwiftPM 会被内部 `git status -s` 偶发拖慢。

## Release Pipeline（重复一次背下来）

```bash
cd /Users/majia/Projects/popskill

# 0. Pre-flight: 验 notarytool profile 还活着 (会被 macOS 锁屏 / 升级 / 其他什么清掉)
xcrun notarytool history --keychain-profile popskill-notarize 2>&1 | head -2
# 看到 "Successfully received submission history" 才继续。
# 没有 → store-credentials 重存 (见 references/setup-notary.md)。

# 1. 写 docs/release/v1.0.X.md
# 2. 改 scripts/package-dev-app.sh 默认 fallback (可选)

export POPSKILL_APP_VERSION=1.0.X
export POPSKILL_APP_BUILD=10X
export POPSKILL_DEVELOPER_ID_APPLICATION="Developer ID Application: JIE MIAO (8KTT7H3QEH)"
export POPSKILL_TEAM_ID=8KTT7H3QEH
export POPSKILL_APPLE_ID=306186636@qq.com
export POPSKILL_NOTARY_KEYCHAIN_PROFILE=popskill-notarize
export POPSKILL_DMG_PATH="$PWD/build/Popskill-1.0.X.dmg"

rm -rf build/Popskill.app build/Popskill-notary.zip "$POPSKILL_DMG_PATH"
scripts/package-dev-app.sh                                       # .app
scripts/notarize.sh                                              # sign + notarize + staple
scripts/package-dmg.sh                                           # DMG
codesign --force --sign "$POPSKILL_DEVELOPER_ID_APPLICATION" --timestamp "$POPSKILL_DMG_PATH"
xcrun notarytool submit "$POPSKILL_DMG_PATH" --keychain-profile popskill-notarize --wait
xcrun stapler staple "$POPSKILL_DMG_PATH"

# Sparkle 签 + 拿到 sig + len
scripts/sparkle-sign-update.sh "$POPSKILL_DMG_PATH"
stat -f%z "$POPSKILL_DMG_PATH"

# 手动在 docs/appcast.xml 顶上加一个 <item>（newest first）— 用上面的 sig + len

git add docs/appcast.xml docs/release/v1.0.X.md scripts/package-dev-app.sh
git commit -m "v1.0.X release"
git push origin main
gh release create v1.0.X "$POPSKILL_DMG_PATH" --title "Popskill v1.0.X" --notes-file docs/release/v1.0.X.md --target main
```

整条 pipeline 5-10 分钟，瓶颈是 Apple notary（每次 1-3 min）。

## 已知坑（不要再踩）

1. **PKCS12 import "MAC verification failed"** — OpenSSL 3.x 默认不行,导入 .p12 必须加 `-legacy -keypbe PBE-SHA1-3DES -macalg SHA1`
2. **`security find-identity` 显示 0 valid** — 缺 Developer ID G2 intermediate，`curl https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer | security import -`
3. **Notary Invalid → Sparkle nested binary** — `Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater` 和 `Autoupdate` 必须单独 codesign `--options runtime --timestamp`，**深度优先**，再签外层 framework。`scripts/notarize.sh` 已做。
4. **GitHub Pages 首次 build 1-2 min** — `gh api .../pages/builds/latest` status 看到 "built" 再 curl
5. **磁盘满 / ENOSPC** — `swift-app/.build/` 经常 1.2GB，`skill-cli/target/` 200MB+，`build/` 累计 100MB+。改大代码前用 `rm -rf swift-app/.build/ skill-cli/target/ build/` 留 ≥2GB
6. **v1.0.0 用户没 Sparkle** — 第一次升级必须手动下 v1.0.1+，从 v1.0.1 开始才用 Sparkle
7. **外部 patch 大概率 base 不在 HEAD** — `git apply --3way` 而不是 `git apply --check`
8. **notarytool keychain profile 会被清掉** — 大概率是锁屏 / macOS 升级 / 重启时被某个 helper 进程清掉。每次发版前必先跑 `xcrun notarytool history --keychain-profile popskill-notarize`,失败就 store-credentials 重存。Developer ID cert 和 Sparkle 私钥不受影响,只是 notary 凭证。
9. **同名分支 push -u 直接复用** — PR #2 / PR #3 都用了 `agent-optimize-popskill-20260517` 分支名,合并完没删,下次推同名分支 git 会附加 commit 而不是新建。Codex / 其他外部 agent 似乎默认复用这个名字,正常合并就行,不必非要 unique。
10. **GitHub Pages 会被禁用 → Sparkle 自动更新静默失效** — v1.1.0 发版时发现 Pages 是 **disabled**（`gh api repos/maojiebc/majia-Popskill/pages` 返回 404）,而 app 的 `SUFeedURL` 指向 `maojiebc.github.io/.../appcast.xml`,等于自动更新一直是哑的(之前 v1.0.x 用户只能手动下)。**每次发版后必 `curl -sI https://maojiebc.github.io/majia-Popskill/appcast.xml` 确认非 404 且含新版 enclosure**。Pages 没开就重新启用:`echo '{"source":{"branch":"main","path":"/docs"}}' | gh api -X POST repos/maojiebc/majia-Popskill/pages --input -`,等 1-2 min build 完再验。
11. **工作区 Git 扫描偶发卡顿** — `git status --short` / 全仓 `git diff` 有时会卡在 SwiftPM/Sparkle framework symlink 或工作区扫描上。验证 Swift 时可先 `rsync -a --exclude '.build' swift-app/ /tmp/popskill-swift-app-test/`，再 `swift test --package-path /tmp/popskill-swift-app-test`；提交前用显式文件路径 `git add <files...>`，不要依赖 `git add -A`。

## 测试基线

- `swift test --package-path /tmp/popskill-swift-app-test` = **173/173**（2026-07-02；原仓库 Git 扫描偶发拖慢时使用临时目录）
- `swift test --package-path swift-app` = **150/150** (v1.1.0 发布时)
- `cargo test --manifest-path skill-cli/Cargo.toml` = 47/47 (Rust sidecar v1.1.0 未动)
- `scripts/ci-local.sh` = 全绿（含 native/bundled/screenshot/release artifact smoke）
- 实测机：majia 自己 Mac，61 capability / 71 active toggle / 13 GitHub sources

## majia-ota-app skill（这次会话沉淀出来的）

- 位置：`~/.claude/skills/majia-ota-app/` (canonical) + 3 镜像
- 伞形：`maojiebc/majia-private-skills/skills/majia-ota-app/`
- 范围：Mac app 发布全链 — 一次性 setup (cert / notary / Sparkle / icon) + 每版 cut + Phase 3 public launch (landing-page README / author block / PII scan / big-launch 渠道)
- 触发：发布 mac app / Sparkle 自动更新 / 签名公证 / appcast 等
- v0.2.0 已经把 Popskill 实战学费（PKCS12 / G2 / Sparkle deep-sign 三大坑）记进 `references/troubleshooting.md`

下次发其他 Mac app 直接 invoke 这个 skill。

## 当前状态（2026-07-02）

- **v1.1.0 是 Latest**（2026-06-07 发布）—— 紧凑账本全屏重设计,signed+notarized DMG + GitHub Release + appcast 上线。main 干净。
- 重设计 commit `bc06f1f`,发布物料 `91b97a6`,截图刷新 `592bc8b`（hero=矩阵,grid=Inspector/新建/组装/设置）
- **GitHub Pages 发版时发现是 disabled,已重新启用（main /docs）** —— Sparkle 自动更新从这版起才真的通（见已知坑 #10）
- 当前迭代分支：`codex/continue-popskill-prototype`。最近推进：Sources/Matrix bulk 流、Settings 真实工具连接、sync action 结果反馈、About 匿名诊断 JSON 导出。
- 测试 173/173（临时目录 SwiftPM 全量）；README 已刷到 1.1.0 + 新 UI 截图

## 下一步候选（v1.1.x 范围）

按优先级，每条都是独立 sprint：

1. **Matrix Gemini 第三列** — `TargetApp.quickToggleSupported` 已列 .gemini，但 sidecar 只接 Claude / Codex；需要 sidecar 加 .gemini/skills 扫描 + Swift 端动态 ForEach 列头
2. **SSOT 路径迁移 .cc-switch/skills → .agents/skills** — sidecar 要做平滑迁移逻辑（rsync + symlink），Swift 端只要改 ssotPath 字符串
3. **WebDAV sync 真接** — sidecar 复用 cc-switch 已有 webdav 命令；Settings 去 SOON 标签
4. **AgentShield 安全扫描复接** — sidecar `security-scan` 命令已存在，Swift 端要做 UI（应该是矩阵行旁的 badge + 详情）
5. **给 v1.1.0 的 UI 占位接真后端** — Sources 注册表在线浏览 / Inspector tab 切换仍待接；Fix 修复、Settings 同步/安装/配额/诊断已开始有真实闭环，继续补完剩余按钮

## 常用命令速查

```bash
# 跑应用看效果
export POPSKILL_CLI=/Users/majia/Projects/popskill/skill-cli/target/debug/skill-cli
/Users/majia/Projects/popskill/swift-app/.build/debug/Popskill

# 跑特定 view（截图调试）
export POPSKILL_DEFAULT_VIEW=matrix           # matrix / fix / sources / create / compose / settings
export POPSKILL_DEFAULT_OVERLAY=spotlight     # 或 onboarding

# 自己截图验证(不用让用户截)：启动 app → 调窗口 → screencapture 窗口矩形 → Read /tmp/shot.png
osascript -e 'tell application "System Events" to tell process "Popskill" to set size of front window to {1480,920}'
read X Y W H < <(osascript -e 'tell application "System Events" to tell process "Popskill" to get {position, size} of front window' | tr ',' ' ')
screencapture -x -R"$X,$Y,$W,$H" /tmp/shot.png   # 显示器睡了先 caffeinate -u -t 3;Quartz/cliclick 不可用,点击靠 store env hook

# 看 sidecar 状态
$POPSKILL_CLI health --json
$POPSKILL_CLI list --json | head -20

# PII 扫描
python3 ~/.claude/skills/majia-ota-app/scripts/audit-mac-app-release.py .

# 更新 GitHub About
~/.claude/skills/majia-ota-app/scripts/update-github-about.sh \
  --repo maojiebc/majia-Popskill --description "..." --homepage "..." --topics "..."
```

## 沟通偏好（来自 user memory）

- 用中文沟通
- 默认产物输出 `~/Downloads/{项目-slug}/`
- 不要做 "summary + emoji 满天飞" 风格；direct + 具体数字
- 大改前先列计划，用户说"做"再开干

---

最后更新：2026-07-02，v1.1.x 迭代中（Settings 实况化 + 匿名诊断导出 + 173 tests）
