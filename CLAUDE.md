# Popskill — Project Notes for Claude

> 项目快照 — 让任何 Claude Code session 在这个目录下都能 5 秒 catch up。

## 是什么（v2，2026-06-10 推倒重来）

**Popskill v2** = 本地 AI 能力管理器。在 `~/.agents/` 维护一份能力仓库（store，按类型分 `skills/ agents/ mcp/ bin/`），通过 **symlink** 把每项能力挂载到多个 AI 工具（Claude Code `~/.claude/`、Codex CLI `~/.codex/`）。

核心场景一句话：**技能装一次，挂到多个 AI 工具上；坏了能修，旧了能升。**

产品刻意做小：**一个主屏（卡片矩阵）+ 三个弹层（添加 / 设置 / 定时任务）+ 行内修复弹层 + 详情 peek + 空态**。没有侧栏、没有路由。

- 设计真源：`docs/design/v2-handoff/`（原始包）+ `v2-handoff-patch-01/`（详情 peek）+ `v2-handoff-patch-02/`（**当前定稿**：绿激活色语义/默认折叠/键盘导航/套装 tokens/列对齐，SPEC.md 以此为准）
- v1（sidecar + cc-switch + 6 目的地账本）止于 tag `v1.1.0`，复盘见 `docs/history/PLAN-v1.md` 与 `PLAN-v2.md`

公开 repo：https://github.com/maojiebc/majia-Popskill

## v2 架构（纯 Swift，无 sidecar，无数据库）

```
swift-app/Sources/Popskill/
├── PopskillApp.swift   @main + RootView（窗口外壳/键盘监听/Sparkle）
├── Theme.swift         账本视觉令牌（暖纸 #fafaf8 / 墨黑 #111 / 电光蓝 #1f4ed8）
├── Models.swift        Entry/Capability/LinkStatus/Tool + 派生(stats/issues/updates)
├── StoreFS.swift       文件系统引擎：扫描/链接读写/安装/回收站（核心，全部单测覆盖）
├── AppModel.swift      @MainActor @Observable 单 store + 全部动作
├── ChromeViews.swift   标题栏/状态栏/tag/单元格/pill/toast
├── MainView.swift      主屏：hero/健康横幅/类型chip/卡片网格/空态
├── FixPopover.swift    行内修复弹层（锚定单元格）
├── DetailPeek.swift    详情 peek（PATCH-01：点能力名称，380 宽，与修复弹层互斥）
├── Sheets.swift        添加（URL→安装计划）+ 设置
├── Sched.swift         定时任务引擎（v2.9 引入 v2.10 重做：plist/cron 解析 + next-fire 计算 + 日志 mtime 推上次运行 + launchctl 操作）
├── SchedSheet.swift    定时任务弹层（◷ / ⌘J；行为分组/倒计时排序/人话备注；写操作 NSAlert 确认）
├── Localization.swift  L() 取词 + 显式语言协商 + l10nLocale（v2.12，详见「本地化」节）
├── Resources/          {zh-Hans,en}.lproj（gen-l10n.sh 从 l10n/ 目录预编译，提交进库）
└── Fixtures.swift      原型样例数据（POPSKILL_FAKE_DATA=1）
swift-app/l10n/Localizable.xcstrings     本地化权威源（人/AI 只编辑这一个文件）
Tests/PopskillTests/StoreFSTests.swift   引擎测试 + RealEnvSmoke 只读冒烟
Tests/PopskillTests/AppModelTests.swift  纯逻辑测试（修复推荐矩阵/键盘状态机）
Tests/PopskillTests/SchedTests.swift     定时任务解析测试（plist/cron/launchctl 全 fixture，不碰真系统）
```

### 关键架构事实

- **文件系统就是数据库**。无 GRDB、无 sidecar、无 cc-switch submodule。唯一持久化元数据是 `~/.agents/.popskill.json`（源 URL / 自动更新 / 工具默认挂载），随 store 同步。
- **SSOT = `~/.agents/`**（v1 的 `~/.cc-switch/skills` 已废弃）。`~/.claude/skills`、`~/.codex/skills` 里是指向 store 的裸 symlink。
- **工具注册表**：唯一定义点 = `scanTools` 的 defs 数组 + `StoreEnv.real()` 的 toolRoots，UI 列全部数据驱动。曾实现过第三工具 CodeBuddy（腾讯，~/.codebuddy/skills，标准 Agent Skills）后按用户决定撤下（2026-06-13）——如重启：linkStatus 的 relativeTo 解析已兼容 skills.sh CLI 的相对 symlink；~/.local 前缀旧版 guancli 有 copyDirectory 写 ~/.codebuddy 的潜在污染源。
- **LinkStatus 四态**：`on`=symlink 有效 / `off`=未链接 / `stub`=**真实目录占位（本地副本，未托管）** / `broken`=symlink 目标丢失。注意 stub 的真实语义和原型（占位待校验）不同。
- **套装双形态**：工具侧既可能是「整套一条 symlink」（全部子项 on），也可能是「物化目录 + 逐子项 symlink」。单独关某个子项时 `setBundleChildLink` 自动物化。移除套装时物化目录会被清理。
- **防呆三条**：`removeLink` 只删 symlink、真实目录一律走 store 回收站（`~/.agents/.trash/`，带时间戳）、store 目录绝不被开关动到。改 StoreFS 必须跑测试。
- **本地化（v2.12）**：UI 全部用户可见字符串走 `L("中文原文")`（key=中文，插值留在里面，Int→%lld/String→%@，其它类型先转 String）。权威源 `swift-app/l10n/Localizable.xcstrings`（zh-Hans + en 双表），**改完必须跑 `scripts/gen-l10n.sh`** 重新编译 lproj（SPM 5.9 CLI 不编译 xcstrings，预编译产物提交进库）；ci-local 的 `--check` 会抓 catalog↔产物漂移和 L()↔key 双向覆盖（scripts/check-l10n-coverage.py）。语言协商在 Localization.swift 显式做（裸二进制没有 main bundle 语言声明，不自己协商会永远落 en）；不支持的系统语言一律英文。**刻意不本地化**：plog 日志、Fixtures、Catalog 精选目录数据。英文截图：启动参数 `-AppleLanguages "(en)"`（zsh 注意引号防分词）。
- **来源回填链（v2.1）**：`.popskill.json`（自装）→ `~/.agents/.skill-lock.json`（npx skills 生态，v3 schema，含 skillPath 子路径）→ 目录自带 `.git` remote → frontmatter homepage 正则。`normalizeSource` 统一成 `github.com/owner/repo` 小写。
- **键盘导航（v2.2/PATCH-02）**：AppModel.kb*（focusId/toolIdx/focusList/focusFrame），MainView syncKbList 按可见顺序回填，PopskillApp NSEvent 监听 ↑↓←→/空格/Esc；激活色=绿 #1a9a4e（蓝只做交互色）。
- **排序（v2.1.2）**：套装置顶（按名），独立项按 类型(Skill→Agent→MCP→CLI)→名称（`sortEntries`）。
- **类型推断（v2.1.2）**：frontmatter `type:` 显式优先，名称特征（-cli/-mcp）兜底；**展示 type 与链接布局 layoutKind 解耦**——guancli 显示 CLI 但 symlink 仍在 skills/。链接路径永远用 `cap.layoutKind`。
- **前缀族收编（v2.1.2）**：无来源散件（不在 lock、无 homepage，如 baoyu-diagram）按前缀族并入源式套装（≥5 成员共享前缀触发），repoSubdir 猜 skills/<name>，更新检查时核实。
- **源式套装（v2.1）**：同一 github 来源 ≥2 个平铺成员归拢成 `BundleKind.source` 套装（id `src:<repo>`），磁盘平铺、symlink 逐成员（与 `.directory` 形态的整链/物化区分，toggle/linkPath 按 bundleKind 路由）。实测：72 平铺 → 26 条目（baoyu 22 / lark 26 各一张卡）。store 内软链成员（私有开发）不归拢、更新跳过。
- **更新机制（v2.1，吸收 cc-switch）**：不靠 semver，对目录算 SHA-256 内容哈希（`computeDirHash`），`checkUpdate` 一次 clone 逐成员比对（lock 的 skillPath 定位 monorepo 子目录，兜底 skills/<name> 约定），还报告上游新增未安装项；`applyUpdate` 只换有变化的成员、原子换版（先拷隐藏临时名再换名，失败回滚）、每个先备份进回收站（保留 200 份，按入站时间 FIFO）。v2.8 起 `ls-remote` HEAD 短路：上游 commit 没动**且本地未漂移**（meta.localDigest 比对）**且没亮更新徽标**（meta.latest 为 nil）才跳过整仓 clone——只比 HEAD 会让终端里改坏的技能永远检不出；亮徽标的要完整比对才能解析上游版本号、或在手动同步后熄灭残留徽标（确认一致时 checkUpdate 自动清 latest）。回收站按 kind 分桶（.trash/skills|agents|mcp|bin/），恢复回原位。启动 2s 后后台自动检查，`autoUpdate=true` 的源直接更。
- **安全校验（v2.1）**：`sanitizeName` 拒绝空名 / `/` / `..` / 隐藏名，install 与导入都走它。
- **未托管导入（v2.1）**：设置 → Store「导入未托管目录」，把工具目录里的真实技能目录收编进 store 并换 symlink。
- **npm 源暂不支持**（resolve 抛错），GitHub = 浅 clone 到临时目录再扫描，local = 复制进 store。

### 调试钩子（截图自验用）

```bash
POPSKILL_FAKE_DATA=1            # 加载原型 fixture（3 套装 + 15 独立，全状态组合）
POPSKILL_EMPTY=1                # 空 store 态
POPSKILL_SHEET=add|settings|sched # 启动即开弹层
POPSKILL_ADD_URL=<url>          # 配合 SHEET=add 预填并自动解析
POPSKILL_FIXPOP=<capId>:<toolId># 启动即开修复弹层
POPSKILL_PEEK=<capId>           # 启动即开详情 peek
POPSKILL_STORE_ROOT=<path>      # 替换 store 根（沙盘）
POPSKILL_NO_AUTOCHECK=1         # 关掉启动自动检查更新
POPSKILL_KB_SIM=d,d,r,space     # 模拟键盘导航（E2E 截图）
POPSKILL_TOOLS_ROOT=<base>      # 工具根沙盘（<base>/.claude 等，新用户旅程）
POPSKILL_ONBOARD_SCAN=1         # 启动自动触发空态扫描
POPSKILL_AUTOCONFIRM=1          # 跳过确认弹窗（配合 E2E）
```

自截流程（v1 验证过，沿用）：启动 app → osascript 调窗口 1280×820 → `screencapture -x -R` → Read 截图。

## 构建 / 测试

```bash
swift build --package-path swift-app
scripts/test.sh        # 封装了 DEVELOPER_DIR=/Applications/Xcode.app（CLT 没有 XCTest）
scripts/ci-local.sh    # 全链本地 CI：语法/构建/测试/启动冒烟/bundle 冒烟/截图/发布工件
# 基线：88 个测试（StoreFSTests + AppModelTests + SchedTests）+ 真实环境只读冒烟 POPSKILL_REAL_SMOKE=1
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

## Release Pipeline（v2.8 起一键化）

```bash
# 1. 编辑 VERSION：第一行版本号，第二行 build（上一版 +1，与版本号解耦的单调整数）
# 2. 写 docs/release/v<版本>.md（第一行 "# v<版本> — 标题"）
# 3. 在 main 上跑：
scripts/release.sh
```

`release.sh` 串完整链：预检（notary profile / 干净工作树 / build 严格递增）→ package-dev-app（版本从 VERSION 注入）→ notarize → DMG 签名公证 → sparkle 签名 → `append-appcast.py`（断言：重复版本拒绝/build 必须 > 顶部 item/写后校验）→ 双语 README 直链与版本行 sed 跟版 → commit+tag+push → `gh release create` → 终检 appcast 与直链。每步失败即停，无静默步骤（坑 #16）。

**build number 规则（v2.8 起）**：与版本号解耦、单调递增整数（v2.8.0=272，此后每版 +1）。旧的「版本号去点」方案在 x.y.10 出现时会让 Sparkle 比较 2710 > 280 直接断更新链。

**发版后注意**：appcast 走 Pages CDN（max-age=600），release.sh 终检会轮询 10 分钟；仍未刷新就查 Settings → Pages 是否被静默禁用（坑 #8/#10）。

## 已知坑（不要再踩）

1. **PKCS12 import "MAC verification failed"** — OpenSSL 3.x 导入 .p12 必须加 `-legacy -keypbe PBE-SHA1-3DES -macalg SHA1`
2. **`security find-identity` 0 valid** — 缺 Developer ID G2 intermediate，`curl https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer | security import -`
3. **Notary Invalid → Sparkle nested binary** — Updater.app/Autoupdate 必须深度优先单独 codesign，`scripts/notarize.sh` 已做
4. **GitHub Pages 首次 build 1-2 min**
5. **磁盘满** — `swift-app/.build/` 经常 1GB+，改大代码前清理
6. **notarytool profile 会被清掉** — 发版前必跑 `xcrun notarytool history --keychain-profile popskill-notarize`
7. **外部 patch 用 `git apply --3way`**
8. **GitHub Pages 会被禁用 → Sparkle 静默失效** — 每次发版后必 curl 验证
9. **CLT 工具链没有 XCTest** — 跑测试必须 `DEVELOPER_DIR=/Applications/Xcode.app`
10. **zsh 不对 `$1` 分词** — 脚本里给 env 传多个变量用 `${=1}`
11. **裸 debug 二进制下 Sparkle 会弹错** — 已用 `SUFeedURL 存在才 startingUpdater` 规避
12. **截图必须按 PID 选窗口** — 用户装的正式版和 debug 实例同名 "Popskill"，按面积选窗会抓错；winid 脚本要 `kCGWindowOwnerPID == 启动的 pid`
13. **app 图标要留 Apple 网格边距** — 满幅 1024 在 Dock 里显得比别的 app 大；内容缩到 824 居中 + 投影（scripts 见 git 历史 /tmp/pad-icon.swift 模式）
14. **状态栏版本号读 Bundle** — `popskillVersion` 从 CFBundleShortVersionString 读，裸二进制才退常量；发版只 bump 常量会漏
15. **容器 .shadow 会传染子视图** — SwiftUI 给带子背景的容器加 .shadow，每个子行各自投影把底色糊灰（v2.3.1 用户实机发现）；浮层/弹层投影前必须 `compositingGroup()`
16. **发版链禁静默步骤** — v2.5.0 事故：appcast 注入静默 no-op，DMG/Release 都成了、更新源没更，用户看到「最新 2.4.2/正跑 2.5.0」倒挂。appcast 一律走 `scripts/append-appcast.py`（断言：重复版本拒绝/锚点必中/写后校验）；另注意 Pages CDN max-age=600，发版后 10 分钟内手动检查可能命中旧缓存

## 当前状态（2026-06-16）

- 线上 **v2.13.0「设计稿 uplift + 新手体检」**：按 claude.ai/design 交接稿账本版最终态补齐三块（皮肤不变）——① 顶部类型统计条（`Stats.byType`/`inactiveByTool` 派生，glyph ◈◉▣⌨▦；未安装工具显示「未安装」）② 断链整卡红（任一工具 broken ⇒ 整卡红边 + 淡红底 + `BrokenBadge`）③ 卡片/表格双视图（`ViewMode`，过滤行右端分段切换 + 状态图例；表格 8 列 + 套装可展开表头行 + `FractionCell` + 子项 │ 缩进 + `StatusCell` 状态符号矩阵，复用现成组件，两视图共享 `kbFocusList`）。调试钩子新增 `POPSKILL_VIEW=list`。**外加 8 角色团队体检（34 确认）修的 6 拦路石**：github 解析前 `ensureGit` 预检 + `humanGitError` 人话错误；未安装工具挂载前 NSAlert 确认（不再静默建 ~/.codex）；导入未托管加确认弹窗（`confirmImport` 共用）；卡片/表格右键 `contextMenu`；统计条未挂载对比度提到 AA；install copyItem 失败回滚、moveToTrash 同秒补后缀。设计稿原包不入库；完整报告见 /tmp（一次性）。
- v2.12.0「双语」：UI 全量本地化（简中 + 英文）——**新增用户可见字符串必须 `L()` + 进 catalog + 跑 gen-l10n.sh**，ci-local 会拦漏网的（见「关键架构事实 → 本地化」节）。
- v2.11/2.10/2.9：激活 pill 压缩靠右、定时任务面板（launchd/crontab）；v2.8.0 成熟度大版见 docs/release/v2.8.0.md。
- 测试 93 个（StoreFSTests 61+1 冒烟 skip + AppModelTests 8 + SchedTests 23），smoke 群全部可跑。

## 下一步候选（设计稿里刻意没做的）

1. **白卡 SaaS 皮肤**（设计 chat 里「保留观望」的另一版方向，账本皮肤的替代选项；做的话是全局换色大改，单独立项）
2. **npm 源支持**
3. **store 目录 FSEvents 实时刷新**（现为 ⌘R + 前台激活自动重扫）
4. **精选目录英文化**（Catalog.swift ~80 条中文简介对英文用户仍直出中文——本地化刻意排除项）

## 沟通偏好（来自 user memory）

- 用中文沟通；direct + 具体数字；大改前先列计划，用户说"做"再开干
