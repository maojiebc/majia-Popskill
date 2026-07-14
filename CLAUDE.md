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
├── StoreWatch.swift    FSEvents 监听器（v2.15：store/工具目录外部变更秒级自动重扫）
├── Resources/          {zh-Hans,en}.lproj（gen-l10n.sh 从 l10n/ 目录预编译，提交进库）
└── Fixtures.swift      原型样例数据（POPSKILL_FAKE_DATA=1）
swift-app/l10n/Localizable.xcstrings     本地化权威源（人/AI 只编辑这一个文件）
Tests/PopskillTests/StoreFSTests.swift   引擎测试 + RealEnvSmoke 只读冒烟
Tests/PopskillTests/AppModelTests.swift  纯逻辑测试（修复推荐矩阵/键盘状态机）
Tests/PopskillTests/SchedTests.swift     定时任务解析测试（plist/cron/launchctl 全 fixture，不碰真系统）
Tests/PopskillTests/StoreWatchTests.swift FSEvents 触发/幂等 + AppModel 全链集成（外部进程写）
```

### 关键架构事实

- **文件系统就是数据库**。无 GRDB、无 sidecar、无 cc-switch submodule。唯一持久化元数据是 `~/.agents/.popskill.json`（源 URL / 自动更新 / 工具默认挂载），随 store 同步。
- **SSOT = `~/.agents/`**（v1 的 `~/.cc-switch/skills` 已废弃）。`~/.claude/skills`、`~/.codex/skills` 里是指向 store 的裸 symlink。
- **工具注册表**：唯一定义点 = `scanTools` 的 defs 数组 + `StoreEnv.real()` 的 toolRoots，UI 列全部数据驱动。曾实现过第三工具 CodeBuddy（腾讯，~/.codebuddy/skills，标准 Agent Skills）后按用户决定撤下（2026-06-13）——如重启：linkStatus 的 relativeTo 解析已兼容 skills.sh CLI 的相对 symlink；~/.local 前缀旧版 guancli 有 copyDirectory 写 ~/.codebuddy 的潜在污染源。
- **LinkStatus 四态**：`on`=symlink 有效 / `off`=未链接 / `stub`=**真实目录占位（本地副本，未托管）** / `broken`=symlink 目标丢失。注意 stub 的真实语义和原型（占位待校验）不同。
- **套装双形态**：工具侧既可能是「整套一条 symlink」（全部子项 on），也可能是「物化目录 + 逐子项 symlink」。单独关某个子项时 `setBundleChildLink` 自动物化。移除套装时物化目录会被清理。
- **防呆三条**：`removeLink` 只删 symlink、真实目录一律走 store 回收站（`~/.agents/.trash/`，带时间戳）、store 目录绝不被开关动到。改 StoreFS 必须跑测试。
- **本地化（v2.12）**：UI 全部用户可见字符串走 `L("中文原文")`（key=中文，插值留在里面，Int→%lld/String→%@，其它类型先转 String）。权威源 `swift-app/l10n/Localizable.xcstrings`（zh-Hans + en 双表），**改完必须跑 `scripts/gen-l10n.sh`** 重新编译 lproj（SPM 5.9 CLI 不编译 xcstrings，预编译产物提交进库）；ci-local 的 `--check` 会抓 catalog↔产物漂移和 L()↔key 双向覆盖（scripts/check-l10n-coverage.py）。语言协商在 Localization.swift 显式做（裸二进制没有 main bundle 语言声明，不自己协商会永远落 en）；不支持的系统语言一律英文。**刻意不本地化**：plog 日志、Fixtures、调试 env 钩子。英文截图：启动参数 `-AppleLanguages "(en)"`（zsh 注意引号防分词）。
- **精选目录双语（v2.14，推翻 v2.12 的「Catalog 不本地化」）**：CatalogEntry 带 desc(中)/en(英)，`localizedDesc` 按 `l10nIsChinese` 挑面（内容级数据不进 xcstrings——几百条会把 catalog 变垃圾场），缺英文落回中文。热门扩容在 **CatalogHot.swift（脚本生成勿手改）**：`scripts/gen-catalog-hot.py <hot-skills.json>` 全文件重生成，411 条覆盖 skills.sh 榜前 400+/anthropics 官方/awesome 精选；查找顺序 `Catalog.entry()` = 手工段优先 → 热门段兜底。
- **来源回填链（v2.1）**：`.popskill.json`（自装）→ `~/.agents/.skill-lock.json`（npx skills 生态，v3 schema，含 skillPath 子路径）→ 目录自带 `.git` remote → frontmatter homepage 正则。`normalizeSource` 统一成 `github.com/owner/repo` 小写。
- **键盘导航（v2.2/PATCH-02）**：AppModel.kb*（focusId/toolIdx/focusList/focusFrame），MainView syncKbList 按可见顺序回填，PopskillApp NSEvent 监听 ↑↓←→/空格/Esc；激活色=绿 #1a9a4e（蓝只做交互色）。
- **排序（v2.1.2）**：套装置顶（按名），独立项按 类型(Skill→Agent→MCP→CLI)→名称（`sortEntries`）。
- **类型推断（v2.1.2）**：frontmatter `type:` 显式优先，名称特征（-cli/-mcp）兜底；**展示 type 与链接布局 layoutKind 解耦**——guancli 显示 CLI 但 symlink 仍在 skills/。链接路径永远用 `cap.layoutKind`。
- **前缀族收编（v2.1.2）**：无来源散件（不在 lock、无 homepage，如 baoyu-diagram）按前缀族并入源式套装（≥5 成员共享前缀触发），repoSubdir 猜 skills/<name>，更新检查时核实。
- **源式套装（v2.1）**：同一 github 来源 ≥2 个平铺成员归拢成 `BundleKind.source` 套装（id `src:<repo>`），磁盘平铺、symlink 逐成员（与 `.directory` 形态的整链/物化区分，toggle/linkPath 按 bundleKind 路由）。实测：72 平铺 → 26 条目（baoyu 22 / lark 26 各一张卡）。store 内软链成员（私有开发）不归拢、更新跳过。
- **更新机制（v2.1，吸收 cc-switch）**：不靠 semver，对目录算 SHA-256 内容哈希（`computeDirHash`），`checkUpdate` 一次 clone 逐成员比对（lock 的 skillPath 定位 monorepo 子目录，兜底 skills/<name> 约定），还报告上游新增未安装项；`applyUpdate` 只换有变化的成员、原子换版（先拷隐藏临时名再换名，失败回滚）、每个先备份进回收站（保留 200 份，按入站时间 FIFO）。v2.8 起 `ls-remote` HEAD 短路：上游 commit 没动**且本地未漂移**（meta.localDigest 比对）**且没亮更新徽标**（meta.latest 为 nil）才跳过整仓 clone——只比 HEAD 会让终端里改坏的技能永远检不出；亮徽标的要完整比对才能解析上游版本号、或在手动同步后熄灭残留徽标（确认一致时 checkUpdate 自动清 latest）。回收站按 kind 分桶（.trash/skills|agents|mcp|bin/），恢复回原位。启动 2s 后后台自动检查，`autoUpdate=true` 的源直接更。
- **更新计数语义（v2.14）**：横幅/按钮计数一律 `Entry.updateCount`（套装按 changedMembers 逐成员计，独立项 1）——用户视角是「几个技能」不是「几个源」。横幅「N 个技能可更新」可点击：`jumpToNextUpdate()` 循环跳转+展开套装+闪烁，跳转优先于过滤（清 query/typeFilter）。hero 右侧常驻手动「检查更新」按钮。表格视图三种行都有更新徽标（v2.13 引入表格时漏了整套）。
- **npm 源（v2.14，NpmSource.swift）**：npm 包发布的是 CLI 本体（tarball 里没有 SKILL.md，技能目录是 CLI 的 install-skill 生成的），所以更新语义 = registry `/latest` vs `npm ls -g` 已装版，`applyNpmUpdate` = `npm i -g`，**绝不碰 store 技能目录**。npm 探测走 `zsh -lc`（GUI app 的 PATH 没有 ~/.local/nvm）缓存在 NpmEnv；「添加」流程仍拒绝 npm 源（装不出技能）。**全局 CLI 巡检**：`checkCliUpdates()` 对 npm -g 全部包逐个比 registry（排除 entries 里 npm 源对应的包防双计），CliSheet 版本矩阵一键升级，入口=横幅「⌨」+设置页+应用菜单。
- **well-known 源（v2.14，WellKnownSource.swift）**：skills.sh 生态的单文件分发协议（lark 系 24+ 技能 2026-06 起 lock 全改写成 `open.feishu.cn/.well-known/skills/<名>/SKILL.md`）。归拢键 = `wk:<host>`（曾被 prefix(3) 截成 `.well-known/skills` 当 github 源，套装名难看+checkUpdate 去 clone 必失败）；检查=逐成员 GET SKILL.md 比哈希，更新=原子换 SKILL.md 保留 references/（协议只分发单文件，附属文件变化检不出是已知局限）；「添加」框粘 well-known 地址可直装。
- **实时刷新（v2.15）**：`StoreWatcher` 封装 FSEventStream（IgnoreSelf + 1s 合并窗口），监听 store 根 + connected 工具的 skills/agents/mcp/bin；**刻意不监听 ~/.claude 整棵树**（projects/ 每个 Claude 会话都在写，噪音百倍）。AppModel.startWatching（RootView onAppear 调）→ 回调 350ms 尾去抖 → refresh；updatingIds 非空时让位（换版收尾自带 refresh）。refresh() 末尾 `syncWatchPaths` 幂等对齐监听集（工具目录挂载后才出现）。⌘R/切前台重扫保留兜底；`POPSKILL_NO_WATCH=1` 关闭。测试写文件必须走外部进程（/usr/bin/touch）——本进程的写被 IgnoreSelf 滤掉。
- **跳过此版本（v2.15，吸收 cc-switch dismissedVersion）**：`UpdateCheck.fingerprint` = 上游状态指纹（github=HEAD sha / npm=registry 版本号 / well-known 与本地路径=变化成员内容组合哈希）；meta 存 `latestFingerprint`（亮徽标时随 saveLatest 落）与 `skipped`（skipLatest 时拷入）。checkUpdate 三条路径返回前 `skipSuppressed`：同指纹→按无更新返回 nil，新指纹→自动清 skipped 重新亮。**unskipLatest 必须连 lastHead/localDigest 检查点一起清**——跳过期间被抑制的检查照常落了检查点，不清的话 HEAD 短路会把「最新」钉死；恢复后走 `checkUpdates(only:)` 定向重查。UI 入口=卡片/表格右键菜单（跳过此版本/恢复更新提醒），套装挂头行不挂子项。
- **挂载确认「不再询问」（v2.15）**：未装工具的挂载确认 NSAlert 加系统原生 suppression，UserDefaults `suppressMountConfirm`；只在点了「仍然挂载」时才记住勾选（勾了又取消 ≠ 以后默认挂）。v2.16 起抽成 `confirmMountUnconnected`，添加流程 install 前同样走它（曾绕过防线静默建出 ~/.codex）。
- **meta 防护（v2.16）**：①loadMeta 解码失败先备份 `.popskill.json.corrupt` 留第一现场（refresh 告警一次），绝不静默让空表覆写落盘 ②refresh 后台 `gcMeta(keep:)` 清孤儿键——终端删掉的条目残留 sourceUrl/autoUpdate 会让重装的同名技能继承前世（最坏被旧仓库静默覆写）③**meta 键一律 entry.name**：toggleAutoUpdate 曾写 entry.id（源式套装 = "src:…"）读却按 repoName，主力套装自动更新从来没生效过（P0）。
- **linkStatus 指对才算 on（v2.16）**：resolved 与 expectedTarget 双方 `resolvingSymlinksInPath` 后不分大小写比对（`samePath`），不一致 = broken「指向别处」；store 内软链成员两侧解析到真身仍判相等，skills.sh 相对链兼容（真实环境 156 链接零误判验证过）。
- **物化收敛（v2.16）**：setBundleChildLink 全 on 且目录内容可证明只有自建子项 symlink（至多混 .DS_Store）时收敛回整套一条链——永久物化会让上游新增子项默认漏挂；有任何真实文件保持物化绝不删。removeEntry 侧「只剩 .DS_Store」也算空目录可删（防幽灵目录）。
- **批量动作收工账本（v2.16）**：updateAll 记 `UpdateBatch`、CLI 升级走串行队列（并发 npm i -g 互咬全局目录）+ `cliBatch` 记账，收尾聚合 toast「N 成 M 败点名」；npm 源更新成功文案不谎称回收站；unskip 在全量检查中排 `pendingRecheck` 收尾追跑。多成员 applyUpdate 中途失败用 `partialFailure` 把已完成数写进错误。
- **回收站命名（v2.16）**：同秒撞名后缀改在名字段（`name~xxxx-stamp`，戳保持结尾）；listTrash 兼容三代形状（含 v2.8-2.15 的 `name-stamp-xxxx` 旧撞名）；`emptyTrash()` + 设置页「清空…」按钮（NSAlert 确认）；回收站区随 entries 变化重读。
- **sched 真停用（v2.16）**：setLoaded off = `bootout + disable`（写 override），on = `enable + bootstrap`——旧 `unload` 无 override，plist 留在 LaunchAgents 下次登录自动复活。
- **添加流程（v2.16）**：install 后台 Task + `installing` 忙态（曾主线程同步 copy 卡死 UI）+ `installError` 驻留计划页 + alreadyExists 给出路；resolve 持 Task 句柄可取消，取消后落地的 staging 立即清（github+wellKnown 都清）；挂载行「未安装」标注。
- **Esc 分层退（v2.16）**：keyMonitor 里 firstResponder 是 NSTextView 时第一下 Esc 只 resign 编辑，第二下才走 peek→fix→sheet→焦点的关闭链。修复弹层内 ↑↓/回车/1-4 键盘可选（`fixKbIdx`，openFix 落在推荐项）。
- **上游新增一键装（v2.17）**：`UpdateCheck.contentUnchanged` 区分「内容更新」与「仅上游新增」；upstreamNew 持久化进 meta 并透传 Entry；`installUpstreamMembers`（限 github/local、sanitizeName、半拷贝清理、meta 写 sourceUrl 自动归拢回源套装、剩余名单扣账）；UI = 卡片/表格「+N 未装」徽标 + 横幅「上游新增 N 个未装」（jumpToNextUpstreamNew 循环定位）+「全部安装」+ 右键菜单；checkUpdates 文案分流（「内容已是最新；上游新增 N 个」）。
- **深链接（v2.17）**：`popskill://install?src=…`（也认 url/source 参数），AppDelegate `application(open:)` + SwiftUI `onOpenURL` 双入口 → `handleDeepLink` → `pendingAddURL` → AddSheet onAppear 预填自动解析（优先于 POPSKILL_ADD_URL）；scheme 由 package-dev-app.sh 注入 CFBundleURLTypes——**裸 debug 二进制不注册 scheme，实测须走打包 app + `open`**。
- **环境探测（v2.17）**：`launchEnvProbeOnce`（RootView onAppear 调，**进程级单飞**，见坑 #20）detached 后台探测 git/npm → `applyEnvProbe` 主线程装配 → envBanner 横幅可关闭（UserDefaults `dismissedEnvWarning.<id>`）。
- **恢复回填 meta（v2.17）**：moveToTrash 可带 metaSnapshot（写进目录内 `.popskill-meta.json`）；restoreFromTrash 回填 sourceUrl/autoUpdate（不覆盖已有键，清 latest/检查点防误亮徽标）——恢复的技能更新链不再断。
- **未托管收编四 kind（v2.17）**：scanUnmanaged 扫 skills/agents/mcp/bin（skill 须有 manifest；agent 目录或单文件 .md；bin 全收），UnmanagedDir 带 kind，导入按 kind 进对应 store 子目录。
- **watcher 根降级（v2.17）**：store 根被删 → syncWatchPaths 改听父目录等重建（事件量大但去抖+幂等扛得住），重建后自动换回。
- **类型化身份（v2.18）**：`Entry.id`/`Capability.id`/meta 键统一 `typedId(磁盘kind, name)`（`skill:`/`agent:`/`mcp:`/`cli:` 前缀，与 `src:`/`plugin:` 共存）——跨类型同名（skills/shared vs agents/shared）不再串号。**kind 取磁盘位置（layoutKind），绝不取展示类型**（frontmatter 会漂移）。旧裸名键两阶段自动迁移：①refresh 开头 `migrateMetaKeys()`（磁盘 kind 定位 > `/`=github 头键 > `.`=wk 头键，孤儿留给 gcMeta）②扫描归拢后 `adoptLegacyHeadKeys`（npm 头键如 "guanskill" 无形状特征，只能按 entry.name→id 补搬，搬完重扫回位）。meta 键歧义（v2.16 的写 id 读 repoName）从根上消灭：唯一读写键就是 entry.id。
- **安装/重拉事务（v2.18，审查 P1-03）**：install = 预检全部链接位（真实目录冲突动盘前报错）→ 同卷 `.popskill-incoming-*` → 原子 rename（并发同名靠 rename 竞争，输家绝不删赢家）→ 记账建链（失败只撤本次对象）；`repullSwap` 取代 removeEntry+install 裸序，撤链/让位/换名/建链四段全记账可回滚——任一步失败磁盘回到操作前。故障注入测试盯着（testInstall*/testRepullSwap*）。
- **meta 写盘可见（v2.18）**：saveMeta/mutateMeta 返回 Bool；自动更新/默认挂载/跳过/恢复提醒/任务备注五个用户动作写失败必须回滚内存态 + sayError，不许谎报「已保存」。
- **CLI 巡检开关（v2.18，审查 P1-04）**：`autoCliPatrol`（UserDefaults，默认关）——启动/手动检查更新不再静默把全局 npm 包名喂给 registry；打开 CLI 面板（⌨）始终巡检。联网披露单一真相源在 SECURITY.md「Network access (complete list)」。
- **严格并发零警告（v2.18）**：同步桥（httpGet/runProcess 管道）一律走带锁 `ResultBox`（semaphore 超时后迟到回调只写盒子）；StoreFS/SchedEngine 标 `@unchecked Sendable`（唯一非值成员 FileManager.default 官方线程安全）；NpmEnv.cached 用 `nonisolated(unsafe)`+既有锁。CI 的 release build 是严格并发模式且零 warning 门，别引入新警告。
- **安全校验（v2.1）**：`sanitizeName` 拒绝空名 / `/` / `..` / 隐藏名，install 与导入都走它。
- **未托管导入（v2.1）**：设置 → Store「导入未托管目录」，把工具目录里的真实技能目录收编进 store 并换 symlink。
- **源解析**：GitHub = 浅 clone 到临时目录再扫描；local = 复制进 store；well-known = GET 单文件建 staging（v2.14）；npm 的「添加」仍拒绝（包里没有 SKILL.md 装不出技能），但更新链全通（见上）。

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
POPSKILL_NO_WATCH=1             # 关闭 FSEvents 实时监听（v2.15）
POPSKILL_L10N_PROBE=1           # 打印真实语言协商结果后退出（v2.18.1，坑 #22 自检）
                                # 必须在**打包 .app** 上跑——测试/裸二进制找不到资源 bundle 会走兜底 lang
```

自截流程（v1 验证过，沿用）：启动 app → osascript 调窗口 1280×820 → `screencapture -x -R` → Read 截图。

## 构建 / 测试

```bash
swift build --package-path swift-app
scripts/test.sh        # 封装了 DEVELOPER_DIR=/Applications/Xcode.app（CLT 没有 XCTest）
scripts/ci-local.sh    # 全链本地 CI：语法/构建/测试/启动冒烟/bundle 冒烟/截图/发布工件
# 基线：134 个测试（StoreFSTests + AppModelTests + SchedTests + StoreWatchTests）+ 真实环境只读冒烟 POPSKILL_REAL_SMOKE=1（v2.16 起带链接状态分布，验 linkStatus 零误判）
# 云 CI（v2.18 起）：shell 语法 + l10n 漂移 + 严格并发 release build（零 warning 门）+ 测试
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

`release.sh` 串完整链（v2.18 改序，审查 P1-05）：预检（notary profile / 干净工作树 / build 严格递增）→ **质量门**（shell 语法 / l10n / 全部测试）→ package-dev-app → **Sparkle ≥ 2.9.4 断言** → bundle 冷启 smoke → notarize → DMG 签名公证 → README 跟版 → 发版 commit（**不含 appcast**）→ push main → **gh run watch 等云 CI 绿（发布门）** → tag → `gh release create` → sparkle 签名 + `append-appcast.py` + appcast commit + push（DMG 就位后 appcast 才上线，保住「用户看到新版必可下」）→ 终检。每步失败即停、全段幂等可续发（发版 commit 已在 HEAD 即跳过构建，逐段补缺）。

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
8. **GitHub Pages 会被禁用 → Sparkle 静默失效** — 每次发版后必 curl 验证。第二形态（2026-07-05 v2.14 实撞）：Pages 没禁但**构建卡死**（builds/latest 状态 building 且 created==updated 十几分钟不动）——处方 `gh api -X POST repos/maojiebc/majia-Popskill/pages/builds` 请求重建，30 秒即好
9. **CLT 工具链没有 XCTest** — 跑测试必须 `DEVELOPER_DIR=/Applications/Xcode.app`
10. **zsh 不对 `$1` 分词** — 脚本里给 env 传多个变量用 `${=1}`
11. **裸 debug 二进制下 Sparkle 会弹错** — 已用 `SUFeedURL 存在才 startingUpdater` 规避
12. **截图必须按 PID 选窗口** — 用户装的正式版和 debug 实例同名 "Popskill"，按面积选窗会抓错；winid 脚本要 `kCGWindowOwnerPID == 启动的 pid`
13. **app 图标要留 Apple 网格边距** — 满幅 1024 在 Dock 里显得比别的 app 大；内容缩到 824 居中 + 投影（scripts 见 git 历史 /tmp/pad-icon.swift 模式）
14. **状态栏版本号读 Bundle** — `popskillVersion` 从 CFBundleShortVersionString 读，裸二进制才退常量；发版只 bump 常量会漏
15. **容器 .shadow 会传染子视图** — SwiftUI 给带子背景的容器加 .shadow，每个子行各自投影把底色糊灰（v2.3.1 用户实机发现）；浮层/弹层投影前必须 `compositingGroup()`
16. **发版链禁静默步骤** — v2.5.0 事故：appcast 注入静默 no-op，DMG/Release 都成了、更新源没更，用户看到「最新 2.4.2/正跑 2.5.0」倒挂。appcast 一律走 `scripts/append-appcast.py`（断言：重复版本拒绝/锚点必中/写后校验）；另注意 Pages CDN max-age=600，发版后 10 分钟内手动检查可能命中旧缓存
17. **`Bundle.module` 在打包 .app 里会崩** — v2.13.0 事故：SPM 生成的 `Bundle.module` 访问器写死去「.app 顶层」和「**打包机的 .build 绝对路径**」找资源 bundle，资源实际在 `Contents/Resources/`，对不上即 `fatalError`，**别人电脑一开就崩**；dev 与本机 smoke 因那条绝对路径恰存在而全程掩盖。教训：①本地化资源查找**自己写**（多候选位置 + 找不到退回 `.main` 绝不 crash，见 Localization.swift `resourceBundle`），不用 `Bundle.module`；②**发版前必须冷启打包的 .app**（不能只跑 dev binary）——`smoke-bundle.sh` 已加固：冷启前把 `.build/*release*/Popskill_Popskill.bundle` 移开，逼 .app 只用自己 `Contents/Resources` 副本，复现干净机器
18. **notarytool 403 "required agreement is missing or has expired"** — 不是坑 #6（那是 profile 被清，报 401/找不到钥匙串项）！这是 Apple 更新了开发者协议：登录 developer.apple.com/account 用户本人勾选同意即恢复，别浪费时间重存 App 专用密码（2026-07-05 v2.14 发版实撞）
19. **截图只截到壁纸 = shell 宿主没有屏幕录制权限** — `screencapture -R` 无权限时**不报错**，静默输出一张只有桌面壁纸的图（所有窗口被剥掉）；`-l<windowid>` 则直接报 "could not create image from window"。别浪费时间调窗口坐标——这是 TCC 权限问题，换有权限的宿主或改用日志验证（`/usr/bin/log stream --level info --predicate 'subsystem == "com.majia.popskill"'` 抓 plog 行）。另注意 **`log` 是 zsh 内置命令**（登录监视用），脚本里查 unified log 必须写全 `/usr/bin/log`，否则报 "too many arguments"（2026-07-07 v2.15 验证实撞）
20. **Task.detached 并行阻塞同一把 NSLock = 协作线程池饥饿** — Swift 协作线程池宽度 ≈ CPU 核数且**不因阻塞扩容**；十几个 detached task 同时 `NSLock.lock()`（如 NpmEnv 的进程级缓存锁）会把池占满，其它一切 async 工作（含 MainActor 调度、FSEvents 回调起的 Task）全部饿死。症状：单跑绿、全套件挂、耗时暴涨。处方：机器级探测做**进程级单飞**（static 标志），或改 async 化的互斥。测试套件构造 N 个 AppModel 是天然放大器（2026-07-09 v2.17 收编实撞，watcher 集成测试被饿挂）
21. **SwiftPM 把 lproj 目录名小写化 → 别拿协商结果跟 "zh-Hans" 裸比** — 仓库源是 `zh-Hans.lproj`，**SwiftPM 复制进 `Popskill_Popskill.bundle` 时小写成 `zh-hans.lproj`**（打包只是 ditto 忠实搬运）。`Bundle.localizations` 返回磁盘真实名 → 协商结果 = `"zh-hans"` → `l10nIsChinese = (lang == "zh-Hans")` 判 **false**，中文界面下 Catalog 精选目录（80+411 条）整片走英文面。**v2.14 潜伏到 v2.18.0 三个版本**没被发现，因为 macOS 文件系统大小写不敏感（`path(forResource:)` 照样命中 → L() 全中文）——**「界面是中文」永远不能证明协商正确**：key 就是中文原文，协商彻底失败退回 main bundle 也照样显示中文。处方：判定走 `l10nLangIsChinese()`（大小写/后缀无关），`POPSKILL_L10N_PROBE=1` 在打包 .app 上自检。**测试陷阱**：测试进程里 resourceBundle 找不到资源会走兜底 `return ("zh-Hans", module)`，断言全局 `l10nIsChinese` 是**结构性假绿**（拿 bug 版代码也照过）——只有喂真实形态（`available: ["zh-hans","en"]`）的纯函数测试抓得住，写完必须做变异验证（注入 bug 版确认测试会红）
22. **CI 编译器小版本 ≠ 本地——零警告门可能拦到本地不报的警告** — v2.18.0 首轮发版实撞：runner 的 Xcode 16 旧小版本对 `attr[range].backgroundColor =`（AttributedString 动态成员）报「cannot form key path…non-sendable」`<unknown>:0` 两条，本地新编译器零警告。处方：`gh run view <id> --log-failed | grep warning:` 定位 → 改等价写法规避（显式 attribute 类型下标 `attr[range][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] =`，不构造 keypath）。发布门此刻的价值：CI 红时 tag/DMG/appcast 零泄漏，修好重跑即续发

## 当前状态（2026-07-14）

- **Latest = v2.18.1「中文界面精选目录显英文」已发版上线**（2026-07-14，build 284；CI 门一次过 run 29316233382；appcast 又是轮询超时后 CDN 自刷（第三次，同 v2.15/2.16，非坑 #8）；**实下载正式包验收**：codesign/spctl/staple/2.18.1·284/Sparkle 2.9.4 + `POPSKILL_L10N_PROBE=1` 实证 `l10nLang=zh-hans isChinese=true locale=zh_CN catalog[guancli]=观远 BI 全能查询…` + 沙盘冷启存活）：用户实机截图发现 guanskill/lark 套装子项简介全英文。根因=**SwiftPM 把 `zh-Hans.lproj` 小写成 `zh-hans`** → 协商结果 "zh-hans" → `l10nIsChinese` 裸比 "zh-Hans" 判 false → Catalog 双语整片走英文面（**v2.14 潜伏三版**，坑 #21 详录）。修：`l10nLangIsChinese()` 大小写/后缀无关 + `l10nLocale` 跟同一判断 + 协商抽纯函数 `l10nLangCandidates()`。**验证三层**：①纯函数回归测试（喂真实形态 `["zh-hans","en"]`）+ **变异验证**（注入 bug 版确认测试真会红——第一版测试断言全局 l10nIsChinese 是结构性假绿，bug 版照过，已废弃重写）②CatalogEntry.localizedDesc(chinese:) 注入式挑面测试 ③`POPSKILL_L10N_PROBE=1` 打包 .app 实测：`l10nLang=zh-hans isChinese=true locale=zh_CN catalog[guancli]=观远 BI 全能查询…`。测试 134→137。
- **v2.18.0「审查修复」已发版上线**（2026-07-14，build 283；**发布门首轮实战拦截**：云 CI 零警告门抓到 runner 旧编译器对 AttributedString 动态成员 keypath 的 2 条 `<unknown>:0` 误报（本地新编译器不报）——按新序 tag/DMG/appcast 全未公开，改显式 attribute 下标后续发全绿，坑 #21；appcast 又是轮询超时后 CDN 自刷（同 v2.15/16，非坑 #8，Pages status=built）；实下载 DMG 五连验证：codesign/spctl/staple/2.18.0·283/**Sparkle 2.9.4 实证** + 沙盘冷启存活）：外部代码审查（基线 v2.17.0@1241146，报告存 ~/Downloads/majia-Popskill-代码审查报告-2026-07-14.md）5 项 P1 全收口 + 4 项 P2 + 1 项 P3——①Sparkle 2.9.1→2.9.4 安全热修（发版链加版本断言）②类型化身份 kind:name + meta 两阶段迁移（真实 meta 影子验证过：14 磁盘键/2 形状头键/1 npm 头键 guanskill 全有归宿）③install/repullSwap 事务化 + 批量同名竞态 ④联网披露对齐 + CLI 巡检默认关 ⑤发布门改序（CI 绿才公开资产）⑥meta 写失败可见 ⑦严格并发 17→0 warning + CI 零警告门 ⑧云 CI 扩容 ⑨GitHub 仓库开 Dependabot/secret scanning/push protection + protect-main ruleset（禁 force-push/删除；刻意不开 required PR——会挡死单人 direct-push 发版流）。测试 126→134；真实环境冒烟 94on/70on/0broken 零误判；打包 .app 内 Sparkle 2.9.4 实证 + bundle 冷启 smoke 过。**升级兼容**：老 meta 首启自动迁移；回退旧版 app 会读不到新键（表现为来源/自动更新需重配，数据本体无损）。
- **Latest = v2.17.0「上游新增一键装 + 深链接」已发版上线**（2026-07-11，build 282；appcast/GitHub Release/实下载 DMG 冷启全过，正式发布包上实测深链接全链路：CFBundleURLTypes 注入确认 + LaunchServices 路由 + 日志证据）：主体收编自 `~/Documents/majia-Popskill` 独立预研工作区（一份带未提交 735 行改动的 checkout，patch 经 `git apply --3way` 搬入）。内容 = v2.16 裁掉的 roadmap 欠账全部还清：①upstreamNew 一键装（徽标+横幅+全部安装）②popskill:// 深链接（LaunchServices 实测过）③回收站恢复回填 meta ④scanUnmanaged 四 kind ⑤watcher 根降级听父目录 ⑥git/npm 环境自检横幅。收编时修三处：探测主线程 login shell 冻窗口→后台单飞；detached 并行阻塞 NSLock 饿死协作线程池（坑 #20，watcher 集成测试实测复现）；installUpstreamNew 死代码。l10n +35 key（408 总）。测试 116→126。**注意：~/Documents/majia-Popskill 副本已收编完毕可废弃**（其 skill-cli/ 只剩 Rust 构建缓存无源码、cc-switch/ 是参考 clone，均未收编）。
- **v2.16.0「存量功能大扫除」已发版上线**（VERSION 2.16.0/281，release note 在 docs/release/v2.16.0.md，等用户确认后跑 scripts/release.sh）：不加新功能，四视角审计（更新链/主界面/弹层流程/引擎数据，40 发现）修 30 条。三真 bug：源式套装 autoUpdate 写读键不同从未生效（P0）/sched 停用重启复活（unload 无 override）/promoteExpanded 键盘顺序脱节。加固：meta GC+损坏备份、linkStatus 指对才 on、物化收敛、批量收工账本、npm 串行队列、跳过态全 UI 回显、修复弹层键盘、添加流程后台化+驻留错误、回收站清空+撞名解析、Esc 分层退。测试 106→116；真实环境只读冒烟状态分布 90on/66on/0broken 零误判。裁掉记 roadmap：upstreamNew 安装入口/恢复回填 meta/scanUnmanaged 四 kind/store 根重建监听。
- **Latest = v2.15.0「实时同步 + 跳过此版本」已发版上线**（2026-07-07，build 280；appcast/GitHub Release/实下载 DMG 冷启验证全过，正式包上并复验了 FSEvents 重扫日志）：①FSEvents store 实时刷新（StoreWatch.swift，终端动 ~/.agents 秒级跟上，锁屏没做成 GUI 截图验证——改用 AppModel 全链集成测试锁行为，用户解锁后可随手实测）②更新徽标「跳过此版本/恢复更新提醒」（指纹钉版本，右键菜单入口）③挂载确认「不再询问」suppression。测试 106 个。详见「关键架构事实」三条 v2.15 bullet。
- 线上 **v2.14.0**「更新体验大修 + CLI 巡检 + 双语热门目录」（2026-07-05 发版，发版实撞坑 #18 notary 403 协议重签 + 坑 #8 第二形态 Pages 构建卡死，均已记档）：①更新计数按技能数+横幅点击跳转定位+主界面常驻检查按钮+表格视图补徽标 ②npm 源更新链（registry vs npm -g，升级 = npm i -g）+CLI 巡检面板（CliSheet 版本矩阵）③well-known 源全链（lark 系 27 项归一张卡+SKILL.md 单文件检查/更新/直装）④精选目录双语化+CatalogHot 411 条热门。调试钩子新增 POPSKILL_SHEET=cli。
- 此前线上 v2.13.2；v2.13.0「设计稿 uplift + 新手体检」：按 claude.ai/design 交接稿账本版最终态补齐三块（皮肤不变）——① 顶部类型统计条（`Stats.byType`/`inactiveByTool` 派生，glyph ◈◉▣⌨▦；未安装工具显示「未安装」）② 断链整卡红（任一工具 broken ⇒ 整卡红边 + 淡红底 + `BrokenBadge`）③ 卡片/表格双视图（`ViewMode`，过滤行右端分段切换 + 状态图例；表格 8 列 + 套装可展开表头行 + `FractionCell` + 子项 │ 缩进 + `StatusCell` 状态符号矩阵，复用现成组件，两视图共享 `kbFocusList`）。调试钩子新增 `POPSKILL_VIEW=list`。**外加 8 角色团队体检（34 确认）修的 6 拦路石**：github 解析前 `ensureGit` 预检 + `humanGitError` 人话错误；未安装工具挂载前 NSAlert 确认（不再静默建 ~/.codex）；导入未托管加确认弹窗（`confirmImport` 共用）；卡片/表格右键 `contextMenu`；统计条未挂载对比度提到 AA；install copyItem 失败回滚、moveToTrash 同秒补后缀。设计稿原包不入库；完整报告见 /tmp（一次性）。
- v2.12.0「双语」：UI 全量本地化（简中 + 英文）——**新增用户可见字符串必须 `L()` + 进 catalog + 跑 gen-l10n.sh**，ci-local 会拦漏网的（见「关键架构事实 → 本地化」节）。
- v2.11/2.10/2.9：激活 pill 压缩靠右、定时任务面板（launchd/crontab）；v2.8.0 成熟度大版见 docs/release/v2.8.0.md。
- **v2.13.1 紧急修复**：v2.12 起 `Bundle.module` 在打包 .app 里找不到本地化资源 → 启动即崩（别人机器全中招，dev/本机被 .build 绝对路径掩盖）；改为 Localization.swift 自己多候选找资源 + 找不到退回 .main 绝不崩；smoke-bundle 加固冷启复现（见坑 #17）。
- 测试 93 个（StoreFSTests 61+1 冒烟 skip + AppModelTests 8 + SchedTests 23），smoke 群全部可跑。

## 下一步候选（设计稿里刻意没做的）

1. **白卡 SaaS 皮肤**（设计 chat 里「保留观望」的另一版方向，账本皮肤的替代选项；做的话是全局换色大改，单独立项）
2. **well-known 附属文件**：协议只分发 SKILL.md，references/ 变化检不出——若 skills.sh 生态出清单协议再跟进
3. **cc-switch 参考清单里最后一项**：拖拽排序（价值存疑，矩阵有固定排序语义）（报告存 docs/dev/cc-switch-reference.md；dismiss v2.15 / 深链接+环境警告 v2.17 均已做掉）
4. **README「一键装进 Popskill」深链接徽章**：深链接已上线（v2.17），README/官网可挂 `popskill://install?src=…` 引导链接——涉及对外文案，单独定夺

## 沟通偏好（来自 user memory）

- 用中文沟通；direct + 具体数字；大改前先列计划，用户说"做"再开干
