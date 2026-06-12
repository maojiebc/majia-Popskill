# Popskill — Project Notes for Claude

> 项目快照 — 让任何 Claude Code session 在这个目录下都能 5 秒 catch up。

## 是什么（v2，2026-06-10 推倒重来）

**Popskill v2** = 本地 AI 能力管理器。在 `~/.agents/` 维护一份能力仓库（store，按类型分 `skills/ agents/ mcp/ bin/`），通过 **symlink** 把每项能力挂载到多个 AI 工具（Claude Code `~/.claude/`、Codex CLI `~/.codex/`）。

核心场景一句话：**技能装一次，挂到多个 AI 工具上；坏了能修，旧了能升。**

产品刻意做小：**一个主屏（卡片矩阵）+ 两个弹层（添加 / 设置）+ 行内修复弹层 + 详情 peek + 空态**。没有侧栏、没有路由。

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
└── Fixtures.swift      原型样例数据（POPSKILL_FAKE_DATA=1）
Tests/PopskillTests/StoreFSTests.swift   引擎测试 + RealEnvSmoke 只读冒烟
Tests/PopskillTests/AppModelTests.swift  纯逻辑测试（修复推荐矩阵/键盘状态机）
```

### 关键架构事实

- **文件系统就是数据库**。无 GRDB、无 sidecar、无 cc-switch submodule。唯一持久化元数据是 `~/.agents/.popskill.json`（源 URL / 自动更新 / 工具默认挂载），随 store 同步。
- **SSOT = `~/.agents/`**（v1 的 `~/.cc-switch/skills` 已废弃）。`~/.claude/skills`、`~/.codex/skills` 里是指向 store 的裸 symlink。
- **LinkStatus 四态**：`on`=symlink 有效 / `off`=未链接 / `stub`=**真实目录占位（本地副本，未托管）** / `broken`=symlink 目标丢失。注意 stub 的真实语义和原型（占位待校验）不同。
- **套装双形态**：工具侧既可能是「整套一条 symlink」（全部子项 on），也可能是「物化目录 + 逐子项 symlink」。单独关某个子项时 `setBundleChildLink` 自动物化。移除套装时物化目录会被清理。
- **防呆三条**：`removeLink` 只删 symlink、真实目录一律走 store 回收站（`~/.agents/.trash/`，带时间戳）、store 目录绝不被开关动到。改 StoreFS 必须跑测试。
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
POPSKILL_SHEET=add|settings     # 启动即开弹层
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
# 基线：66 个测试（StoreFSTests + AppModelTests）+ 真实环境只读冒烟 POPSKILL_REAL_SMOKE=1
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

## 当前状态（2026-06-11）

- 线上 **v2.7.1**（v2.0–v2.7.1 共 13 个版本已发，tag 全在远端，本地已 fetch --tags）。
- **v2.8.0 成熟度大版**在 `v2.8-maturity` 分支：按「成熟 Mac app」标准做的 41 条审计修复（8 维度多 agent 审计 + 逐条复核）。五大簇：① 引擎数据安全（回收站 FIFO/原子更新/run 超时/哈希防 symlink/repo 命名）② 反馈链诚实化（真实计数/repull 异步/错误分级/os.Logger）③ 平台惯例（⌘,/⌘R/⌘F/Help/单窗口/统一亮色）④ 可见可控（回收站 UI/npm 清理/a11y/LazyVStack/Sparkle 开关/报告问题）⑤ 基建（release.sh 一键发版/VERSION 单源/ci-local v2 重写/v1 文档归档）。
- 测试 34 → 60（StoreFSTests + AppModelTests），smoke 群全部可跑。

## 下一步候选

1. **v2.8.0 发布**：合回 main 跑 `scripts/release.sh`（VERSION 已备 2.8.0/272）
2. **本地化**：String Catalog 全量改造（英文 README 在引流但 app 纯中文，audit 遗留的唯一 L 级项）
3. **npm 源支持**
4. **store 目录 FSEvents 实时刷新**（现为 ⌘R + 前台激活自动重扫）

## 沟通偏好（来自 user memory）

- 用中文沟通；direct + 具体数字；大改前先列计划，用户说"做"再开干
