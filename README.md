# Popskill

> A Mac App Store-style client for managing Claude Code Agent Skills.
> 一款看齐 Mac App Store 的 Claude Code Agent Skills 桌面客户端。

<p align="center">
  <strong>Status: Pre-alpha — sidecar + native Library / Discover / Updates / Backups / Insights MVP compile locally.</strong>
</p>

---

## English (TL;DR)

Popskill aims to be the App Store experience that Claude Code skills deserve on Mac:

- **Mac-native SwiftUI design** (inspired by Surge for Mac)
- **Multi-app toggles** for Claude / Codex / Gemini / OpenCode / Hermes (quick row toggles for the common three, full controls in detail)
- **Usage Insights** — token spend, top skills, hibernate candidates (parses `~/.claude/projects/*.jsonl`). No other tool does this.
- **Stub state** — like App Store's "purchased but not downloaded"; reclaim disk without losing the card
- **WebDAV sync** across devices (reuses [CC Switch](https://github.com/farion1231/cc-switch)'s implementation — zero re-implementation)
- **AgentShield security scan** for third-party skill installs (persisted Library badges; see [PLAN.md §11.8](./PLAN.md#118-第三方-skill-安全审计agentshield))

**Architecture**: SwiftUI front-end → `skill-cli` Rust sidecar → `cc_switch_lib` (CC Switch as git submodule, **zero fork, zero patch**).

**Current stage**: design + planning complete; MVP scaffolding is underway. `skill-cli` is wired to CC Switch for list/detail/toggle/discover/install/update/uninstall/import/repository/backup flows, SwiftUI Library + Discover + Updates + Backups + Insights compile locally, `scripts/dev-build.sh` verifies Rust build/tests + read-only sidecar smoke + Swift tests, and `scripts/package-dmg.sh` + `scripts/notarize.sh` sketch the v0.1 release path. See [PLAN.md](./PLAN.md) and [STYLE.md](./STYLE.md) for the full picture.

---

## 中文版

### 它是什么

Claude Code 的 Agent Skills 生态在 GitHub 上已经爆炸（[anthropics/skills](https://github.com/anthropics/skills) 13万⭐、各种 awesome-list 60万+⭐ 总和），但**没有一个 Mac 客户端把"发现 / 安装 / 管理 / 统计"做成 App Store 那种体验**。

Popskill 就是来填这个坑的。

### 它跟现有方案差在哪

| 工具 | 缺点 |
|---|---|
| **[CC Switch](https://github.com/farion1231/cc-switch)** (6.8万⭐) | 功能太杂（6 种 CLI + Provider + Skill 全塞一起），新手找不到入口；多 app toggle 必须进详情页 |
| **[skills-manage](https://github.com/iamzhihuix/skills-manage)** (1814⭐) | 同赛道头部，但不是 Mac 原生质感，公开包未 notarize，且没有 Usage Insights / Stub |
| **[skills-manager](https://github.com/yibie/skills-manager)** (152⭐) | SwiftUI 技术栈撞车，但视觉偏标准控件，没有 Usage Insights / Stub / WebDAV |
| **[agent-skills-guard](https://github.com/bruc3van/agent-skills-guard)** (354⭐) | 只做安全扫描，没有 App Store 发现/统计 |
| **[vercel-labs/skills](https://github.com/vercel-labs/skills)** (1.8万⭐) | CLI 工具，无 GUI |
| 一众 0-star `claude-skill-manager` | 没人做出 App Store 体验 |

**Popskill 的差异点**：

1. **Mac App Store 级别的视觉**——SwiftUI 原生，配 Surge for Mac 设计语言
2. **使用统计 / Insights 页**（全网独家）——告诉你装的几十个 skill 里哪些值得保留
3. **多 app toggle**——Library 列表行内切 Claude/Codex/Gemini，详情页支持 OpenCode/Hermes
4. **Stub 状态**——60 天没用的 skill 本地清掉内容、留 metadata 卡片，要用一键再装
5. **WebDAV 跨设备同步**——白嫖 CC Switch 已有能力，不重做
6. **AgentShield 安全审计**——第三方 skill 安装后立即扫描，blocked 自动回滚，安全状态显示到列表和详情页

### 技术架构（一句话）

```
SwiftUI 前端 (macOS 14+)
    ↓ Process.run
skill-cli (Rust, ~600 行 clap wrapper)
    ↓ pub use SkillService
cc_switch_lib (CC Switch 当 git submodule，一行不改)
```

我们**不 fork、不 patch CC Switch**，纯 Rust path 依赖。详见 [PLAN.md §4 技术架构](./PLAN.md#4-技术架构)。

### 当前状态

| 阶段 | 状态 |
|---|---|
| B. 摸 CC Switch 源码 | ✅ Done |
| A. Sidecar 剥离可行性 | ✅ 静态分析通过（lib.rs:52-56 已 pub use SkillService） |
| C. 产品形态 V1 | ✅ 5 个页面 wireframe + 状态机 + 16 条决策 |
| D-prep. 视觉设计语言 | ✅ Surge.app 拆解 + 22 个 design token |
| **D. 脚手架 init + Day 1** | 🚧 **已启动：sidecar + SwiftUI Library/Discover/Updates/Backups/Insights MVP 可编译** |

**这个仓库目前是 pre-alpha**：已有 Rust sidecar、SwiftUI Library/Discover/Updates/Backups/Insights 页面、transcript scanner 单测和本地开发脚本。Stub/WebDAV/AgentShield 已有纵切骨架；正式签名、公证、Sparkle 更新和 App Store 分发还没完成；本地 DMG 与 notarize 脚本骨架已先落位。

### 已落地的 MVP 能力

```bash
./skill-cli/target/debug/skill-cli health --json
./skill-cli/target/debug/skill-cli webdav-status --json
./skill-cli/target/debug/skill-cli webdav-remote-info --json
./skill-cli/target/debug/skill-cli list --json
./skill-cli/target/debug/skill-cli detail <skill-id> --json
./skill-cli/target/debug/skill-cli toggle <skill-id> --app codex --enabled true --json
./skill-cli/target/debug/skill-cli scan-unmanaged --json
./skill-cli/target/debug/skill-cli discover --query pdf --limit 20 --json
./skill-cli/target/debug/skill-cli repo-list --json
./skill-cli/target/debug/skill-cli repo-add --owner <owner> --name <repo> --branch main --enabled true --json
./skill-cli/target/debug/skill-cli repo-toggle --owner <owner> --name <repo> --enabled false --json
./skill-cli/target/debug/skill-cli repo-remove --owner <owner> --name <repo> --json
./skill-cli/target/debug/skill-cli install <skill-key> --app codex --json
./skill-cli/target/debug/skill-cli check-updates --json
./skill-cli/target/debug/skill-cli update <skill-id> --json
./skill-cli/target/debug/skill-cli uninstall <skill-id> --json
./skill-cli/target/debug/skill-cli stub-list --json
./skill-cli/target/debug/skill-cli stub <skill-id> --json
./skill-cli/target/debug/skill-cli rehydrate <skill-id> --app codex --json
./skill-cli/target/debug/skill-cli security-scan /path/to/skill --skill-id <skill-id> --json
./skill-cli/target/debug/skill-cli security-scan-list --json
./skill-cli/target/debug/skill-cli backup-list --json
./skill-cli/target/debug/skill-cli backup-restore <backup-id> --app codex --json
./skill-cli/target/debug/skill-cli backup-delete <backup-id> --json
./skill-cli/target/debug/skill-cli import-unmanaged <directory> --app codex --json
```

SwiftUI 端已接入：

- Library：本机 skill 列表、All/Active/Inactive/Stubs 过滤、Claude/Codex/Gemini 行内 toggle、详情页 5 App toggle、stub/rehydrate、AgentShield 持久化角标与手动扫描、unmanaged import 前扫描
- Discover：搜索 CC Switch 启用的 skill repositories，按 Claude/Codex/Gemini/OpenCode/Hermes 安装，安装后跑 AgentShield，blocked 自动回滚
- Repositories：查看、启停、删除 CC Switch skill discovery sources
- Updates：按需检查更新、逐条更新
- Backups：查看、恢复、删除 CC Switch uninstall backups
- Insights：本地扫描 `~/.claude/projects/**/*.jsonl`，聚合 token/session/file/model 指标，含 Recently Used、Token Spend、60 天 inactive Idle Candidates，Idle Candidates 可单个或批量转 Stub
- Settings：sidecar 路径、`POPSKILL_CLI` override、CC Switch skill store、WebDAV 状态/远端 snapshot 与 Keychain 策略诊断

### 文档导航

- **[PLAN.md](./PLAN.md)**（~1265 行）—— 产品 + 工程规划，自包含。新机器接手只需读这一份。
  - §0-2：怎么用 + 16 条核心决策
  - §3：产品形态（5 页 wireframe + 状态机）
  - §4-8：技术架构 + 数据模型 + Sidecar 接口
  - §9：第一周 Day 1-5 milestone
  - §11：已知坑 / 风险预案
  - 附录 A：新电脑接手 6 步 checklist

- **[STYLE.md](./STYLE.md)**（~840 行）—— 视觉设计语言，含立即可用的 SwiftUI design token 代码。
- **[docs/ipc.md](./docs/ipc.md)** —— SwiftUI ↔ `skill-cli` JSON 合约。
- **[docs/transcript-parsing.md](./docs/transcript-parsing.md)** —— Claude transcript 字段观察和 Insights MVP 策略。
- **[docs/security.md](./docs/security.md)** —— Keychain、skill 内容和 transcript insights 的安全边界。

### 在新机器上接手

```bash
# 装工具链
xcode-select --install
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
brew install gh jq

# 拉项目
gh repo clone maojiebc/majia-Popskill ~/projects/popskill -- --recurse-submodules
cd ~/projects/popskill

# 一键开发构建
./scripts/dev-build.sh

# 本地 CI（构建、测试、只读 smoke、App 启动 smoke、bundle/release smoke）
./scripts/ci-local.sh

# 需要额外覆盖写入型 repo 命令时
./scripts/ci-local.sh --mutating

# 原生 app 启动烟测
./scripts/smoke-app.sh

# 显式写入型 sidecar smoke（会创建并删除一个临时 repo）
./scripts/smoke-cli-mutating.sh

# 生成本地开发 .app bundle（内含 skill-cli sidecar）
./scripts/package-dev-app.sh

# 验证 .app bundle 能使用内置 skill-cli 启动
./scripts/smoke-bundle.sh

# 生成本地开发 DMG（含 Applications 拖拽入口），并输出 sha256
./scripts/package-dmg.sh

# 生成 release metadata（version / build / dmg sha256 / size）
./scripts/release-manifest.sh

# 从 release metadata 生成 Sparkle appcast 骨架（正式发布时传真实下载 URL/签名）
POPSKILL_APPCAST_DOWNLOAD_URL="https://example.com/Popskill.dmg" \
./scripts/generate-appcast.sh

# v0.1 发布前的签名/公证骨架（需要 Apple Developer ID 凭据）
POPSKILL_DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)" \
POPSKILL_APPLE_ID="you@example.com" \
POPSKILL_TEAM_ID="TEAMID" \
POPSKILL_NOTARY_PASSWORD="app-specific-password" \
./scripts/notarize.sh

# 本地启动 SwiftUI app
./scripts/run-app.sh
```

详见 [PLAN.md 附录 A](./PLAN.md#附录-a新电脑接手-checklist)。

### 致谢 / Credits

这个项目站在三类巨人肩膀上：

- **[CC Switch](https://github.com/farion1231/cc-switch)** by Jason Young — services 层写得极其干净（0 处 Tauri 耦合在 3042 行业务逻辑里），让 sidecar 路线变成 1 周的活而不是 4 周
- **[Surge for Mac](https://nssurge.com/)** — 视觉设计语言的主要灵感来源（仅参考设计，不复制资源）
- **[Anthropic Skills](https://github.com/anthropics/skills)**、[vercel-labs/skills](https://github.com/vercel-labs/skills) 和 [awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills) 等一票 awesome-list — 内容生态的基础设施

### 协作 / Contributing

这是 pre-alpha，主仓库还在私有阶段的话不建议提 PR。等 v0.1 发布后会写 CONTRIBUTING.md。

如果你对设计/架构有想法，欢迎在 Issues 讨论。

### License

[MIT](./LICENSE)
