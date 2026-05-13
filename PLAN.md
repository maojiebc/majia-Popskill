# Popskill —— Mac 上的 Claude Code Skill App Store

> 这是一份**自包含的项目规划文档**。可以原样拷到任何一台电脑，扔给 AI 工程师就能从零接手。
>
> 最后更新：2026-05-13
> 作者：majia + Claude（讨论沉淀）
> 当前阶段：
> - ✅ B 阶段：CC Switch 源码刨完（services 层 0 个 Tauri 依赖，可干净剥离）
> - ✅ A 阶段：Sidecar 剥离可行性静态验证（lib.rs 已 pub use SkillService）
> - ✅ C 阶段：产品形态 V1（5 页 wireframe + 状态机 + 决策表）
> - ✅ D-prep 阶段：视觉设计语言（STYLE.md）+ Surge.app teardown 验证
> - 🚧 MVP 校准：Rust sidecar + SwiftUI Library / Agents / Discover / Updates / Backups / Insights 主流程已通，Discover/Library/Settings/Updates 截图级 polish 已完成，正在补发布关键路径

---

## 目录

0. [文档怎么用](#0-文档怎么用)
1. [项目目标](#1-项目目标)
2. [核心决策一览](#2-核心决策一览)
3. [产品形态](#3-产品形态)
4. [技术架构](#4-技术架构)
5. [项目结构](#5-项目结构)
6. [技术栈](#6-技术栈)
7. [数据模型](#7-数据模型)
8. [Sidecar 接口设计](#8-sidecar-接口设计)
9. [第一周 Milestone（已完成）](#9-第一周-milestone-day-1-5)
10. [后续阶段（进度校准）](#10-后续阶段-week-2-8)
11. [已知坑 / 风险预案](#11-已知坑--风险预案)
12. [引用资料](#12-引用资料)
13. [验证清单](#13-验证清单)
14. [词汇表](#14-词汇表)
15. [v0.2 战略储备：Package 能力包重构](#15-v02-战略储备package-能力包重构)

---

## 0. 文档怎么用

**如果你是 AI 工程师从零接手**：
- 通读全文一次，搞清楚为什么这么设计
- 重点看 §2（决策一览）、§4（架构）、§8（Sidecar 接口）、§11（已知坑）
- 不要重新设计 —— 这些决策都有讨论过的理由，理由没变就不要改
- 真要改的话，在 §2 加一行 "Rev N: ..." 说明改了什么、为什么

**如果你是 majia 本人**：
- 任何决策的 "为什么"忘了，回来翻这文档
- 在新电脑上：`git clone <repo>` 之后 §9 是 Day 1 待办

**如果你是要给这个文档加内容**：
- 改完务必更新顶部"最后更新"日期
- 决策类改动写到 §2 顶部，附 Rev 编号

---

## 1. 项目目标

### 一句话定义
**Mac 上的 App Store，但专门管理 Claude Code 的 Agent Skills**。

### 用户
- 一期：作者本人（重度 skill 使用者，本地有 47+ skill）
- 二期：开源给社区

### 跟现有方案比的核心差异

> 更新于 2026-05。按"对 Popskill 的威胁等级"从高到低排，**前两个是真正同赛道的头部对手，必须正面回答**。

| 现有方案 | 体量 / 技术栈 | 强项 | 缺点 / Popskill 对它的差异 |
|---|---|---|---|
| **iamzhihuix/skills-manage** | **1814⭐** / Tauri v2 + React 19 + Rust + SQLite(WAL) | 中心仓 `~/.agents/skills/` + symlink 分发；Collections 批量装；GitHub 仓库导入（PAT+retry）；AI 解释生成；双语 UI + Catppuccin 4 主题；覆盖 OpenClaw 全家桶（QClaw/EasyClaw/WorkBuddy） | (1) Tauri 跨平台壳，达不到 Mac 原生质感；(2) **macOS 公开包未 notarize，下载弹"已损坏"**；(3) **没有 Usage Insights**；(4) **没有 Stub 状态**；(5) PAT / API key 明文存 SQLite |
| **yibie/skills-manager** | **152⭐** / SwiftUI + SwiftData，macOS 14+ | **技术栈跟我们撞车，且已发布**。AgentRegistry 覆盖 40+ Agent；内置 LLM sandbox 试用；中文描述目录 + Ollama/LM Studio fallback；本地 Git 做版本管理；blessed TUI 双形态 | (1) 视觉是标准 SwiftUI 直出，**没有 App Store 设计语言**；(2) **没有 Usage Insights**；(3) **没有 Stub 状态**；(4) 多 app 安装是弹 picker，不是行内 toggle；(5) **没有 WebDAV 同步** |
| **CC Switch** (farion1231) | 6.8 万⭐ / Tauri | Provider 切换主战场，services 层干净 | 功能太杂（多 CLI 切换 + Provider + skill 全塞）；多 app toggle 必须进详情页。**我们当它的 lib 用，不当对手** |
| **agent-skills-guard** (bruc3van) | 354⭐ / Tauri | 安全扫描 | 只做安全扫描，能力可被 ECC AgentShield 覆盖 |
| **vercel-labs/skills** (npx skills) | 1.8 万⭐ / CLI | 官方背书，命令行分发顺手 | CLI 工具，无 GUI |
| **ECC / everything-claude-code** | 18 万⭐ / npm + 配置包 + Tkinter Dashboard | 208 skills + 55 agents，带 AgentShield 安全扫描 | 不是同赛道 GUI，但可作为上游内容源和安全能力来源 |
| **msitarzewski/agency-agents** | 9.6 万⭐ / Markdown agent library | 80+ agents、17 分类、MIT，中文圈传播强 | 不是 GUI 对手，但明确证明 Agent 角色库需求；Popskill 应先纳入本机 Agent 管理，再接来源发现 |

### 差异化复核

把 Popskill 计划的差异点跟两个头部对手逐一对照，确认护城河是否成立：

| Popskill 差异点 | iamzhihuix/skills-manage | yibie/skills-manager | 仍独家? |
|---|---|---|---|
| Mac App Store 视觉（Surge 风格） | shadcn + Catppuccin（Web 美学） | 标准 SwiftUI 直出 | ✅ 视觉独家，但必须真正落到代码 |
| Usage Insights（解析 `.jsonl`） | ❌ | ❌ | ✅ **真独家** |
| Stub 状态（保留卡片清内容） | ❌ | ❌ | ✅ **真独家** |
| 行内多 app toggle | 进详情才能切 | multi-install picker（弹窗） | 🟡 形式独家 |
| WebDAV 跨设备同步 | 仅本地 | 仅本地 | ✅ 独家 |
| Agent 本地管理 | ❌ | AgentRegistry，但偏内置目录 | 🟡 新增纵切，先做本机 `~/.claude/agents` |
| 第三方 skill 安全审计（AgentShield） | ❌ | ❌ | ✅ **新独家** |

**结论**：差异化定位成立。真正护城河是 **Usage Insights + Stub + AgentShield + Mac 原生视觉**；视觉、Stub、AgentShield 不能只停留在文档里。

### Popskill 的差异点（按重要性）

1. **Mac App Store 级别的视觉** —— SwiftUI 原生，对得起 Apple 美学（对 yibie 的回答）
2. **使用统计 / Insights 页**（两个头部对手都没做）—— 解析 `~/.claude/projects/*.jsonl`，能告诉用户"你装了 47 个 skill，哪些值得保留"
3. **行内多 app toggle** —— Library 列表每条 skill 直接行内切 Claude/Codex/Gemini，不进详情
4. **Stub 状态**（看齐 App Store"已购未下载"）—— 60 天没用的 skill 本地清掉内容，留 metadata 卡片，要用一键再装
5. **WebDAV 跨设备同步** —— 复用 CC Switch 已有能力（对 iamzhihuix 的回答）
6. **Agent 本地管理** —— AgencyAgents / ECC 证明 Agent persona 库正在成型，Popskill 要把 `~/.claude/agents` 纳入 Library
7. **第三方 skill 安全审计** —— 集成 ECC AgentShield，两个头部对手都没做（详见 §11.8）

### 从对手身上要抄什么 / 要绕什么

- **抄 yibie 的 AgentRegistry 路径表**：扩展 Popskill 支持的 Agent 矩阵（OpenClaw 系、Roo、Continue、Qwen 这些中文圈用户多的）
- **抄 yibie 的 IPv4 loopback 兜底**：macOS `localhost` 解析到 IPv6 `::1` 的坑，LLM 调用时默认 `127.0.0.1`
- **抄 iamzhihuix 的 SQLite schema 思路**：Usage Insights 落库时不要从零设计；WAL 模式是 GUI + sidecar 多进程读的标准答案
- **抄 iamzhihuix 的 GitHub 导入策略**：PAT 认证 + retry fallback 写进 `skill-cli`
- **抄 iamzhihuix 的项目级目录扫描**：扫 `.skills/`、`.agents/skills/`、`.claude/skills/`，把覆盖率拉满
- **抄 ECC 的 manifest-driven install**：`skill-cli install` 分 `plan` 和 `apply` 两步，GUI 端能 preview
- **抄 ECC 的 AgentShield**：第三方 skill 默认做安全审计
- **绕开 iamzhihuix 的 notarize 坑**：v0.1 就买 Apple Developer Program 做 notarize（详见 §11.7）
- **绕开 iamzhihuix 的密钥存储坑**：Popskill 自有 PAT / API key 进 Keychain，**不进 SQLite**；WebDAV password 当前委托给 CC Switch settings，Popskill 不另存副本

### 当前实现校准（2026-05-13）

代码已经明显超过最初 Day 1-5 计划，下面这些能力已经落地，后续不要再当成"未来计划"：

- **已完成**：`skill-cli list/detail/toggle/discover/install-plan/install/update/uninstall/import-unmanaged`
- **已完成**：本机 Claude Code Agent 只读管理纵切（`skill-cli agent-list` / `agent-targets` / `agent-catalog` / `agent-install-plan` + SwiftUI Agents 页，扫描 `~/.claude/agents/**/*.md`，展示 Agent 工具 target 诊断，只读预览 AgencyAgents catalog，并可预览写入路径）
- **已完成**：AgentShield sidecar + Library 手动/持久化扫描 + install/import gate（blocked 自动回滚或阻断；`security-scan` / `security-scan-list`，支持 `POPSKILL_AGENTSHIELD_BIN`）
- **已完成**：WebDAV 状态/远端 snapshot、手动同步 readiness plan 与配置写入纵切（`webdav-status` / `webdav-configure` / `webdav-remote-info` / `webdav-sync-plan`，Settings 显示配置、远端 manifest 状态与手动 sync 边界）
- **已完成**：自定义 skill repository 管理（`repo-list/add/toggle/remove`），含 URL/owner/name 校验、`.git` 后缀规范化、非法 scheme 拒绝
- **已完成**：SwiftUI Library / Discover / Updates / Backups / Insights / Settings 主页面可编译，Discover 已接 install-plan 行内预览
- **已完成**：行内 Claude/Codex/Gemini toggle、详情页更多 app toggle、Stub / Rehydrate、Idle Candidates 60 天 inactive + transcript attribution 筛选 + 批量 Stub、unmanaged import 前扫描
- **已完成**：Backups 查看 / 恢复 / 删除，Settings sidecar health 诊断
- **已完成**：本地 CI、read-only smoke、mutating repo smoke、`.app` development bundle、bundle launch smoke、release artifact smoke、development DMG 打包、release manifest/appcast 生成
- **已完成**：Discover/Library/Settings/Updates 截图级 polish（Discover 行 CTA 文案、sidebar badge 导航、Library 行布局、Settings 诊断密度、Updates 空态按钮层级）
- **未完成**：WebDAV 手动 upload/download sync、正式 codesign/notarize、Sparkle 公开 feed/key/signature 实测（SDK link、菜单/配置/package hooks 已先落地）

### 不做的事（避免范围爆炸）

- ❌ Windows / Linux —— Mac only，原生 SwiftUI
- ❌ 多 LLM 切换 / Provider 管理 —— CC Switch 已经做了，不抢这个赛道
- ❌ 自建 Registry 服务 —— 用 GitHub awesome-list 当数据源就够
- ❌ 自己生产 Agent 内容 —— Popskill 是本地管理器，不是 Agent 内容仓；Agent 内容优先接 agency-agents 这类上游
- ❌ Skill 创作工具（编辑器/上传器）—— v1 只做"消费者端"
- ❌ 用户评分系统 —— v2 再考虑

---

## 2. 核心决策一览

> 每一条决策都有为什么。**改之前先看为什么**。

| # | 决策 | 选项 | 选了什么 | 理由 |
|---|---|---|---|---|
| D1 | 平台 | Windows/Linux/跨平台 | **Mac only** | 用户明确要"看齐 Mac App Store"。SwiftUI 原生比跨平台框架的体验高一个数量级 |
| D2 | UI 框架 | SwiftUI / Tauri / Electron | **SwiftUI** | App Store 设计语言免费拿到 |
| D3 | 是否复用 CC Switch | 是 / 否 | **是** | 它的 services 层 7900 行 Rust 是稳定的工程资产 |
| D4 | 复用方式 | Fork / 静态库 FFI / **Sidecar CLI** / 重写 / 当后端服务 | **Sidecar CLI (R2)** | 4 个选项里唯一对非专业程序员友好的，升级跟随基本免费 |
| D5 | 依赖 CC Switch 的姿势 | git fork / **git submodule + cargo path dep** | **submodule + path dep** | 一行不改 CC Switch，零冲突升级。已用静态分析验证 |
| D6 | 导航 | TabView / **NavigationSplitView** / 混合 | **NavigationSplitView** | Mac App Store 实际就是纯侧边栏 |
| D7 | 最低系统 | macOS 12 / 13 / **14 Sonoma** | **macOS 14** | NavigationSplitView 完整能力 + @Observable 都要 14+ |
| D8 | 状态管理 | ObservableObject / **@Observable** (Swift 5.9+) | **@Observable** | 官方新范式 |
| D9 | 本地 DB | UserDefaults / Core Data / **SQLite via GRDB** | **GRDB.swift** | 跟 CC Switch 一致，便于互操作 |
| D10 | 跟 CC Switch 数据库的关系 | 只读它 / **双写自己的** / 共享 | **双写自己的** | 你有自己的字段（使用统计），但 skill metadata 读 CC Switch 那张表 |
| D11 | Insights 数据源 | API 调用埋点 / **解析 transcript.jsonl** | **解析 transcript.jsonl** | 唯一不需要侵入 Claude Code 的方式 |
| D12 | Token 归因 | 不归因（只算总量）/ **窗口归因** | **窗口归因** | 一个 skill 被调用后，下次切 skill 前的所有 token 都归它。粗糙但实用 |
| D13 | 图标系统（v1） | 抓 GitHub 头像 / hash identicon / **首字母 + 底色** | **首字母 + 底色** | 最便宜，零网络依赖。v2 再优化 |
| D14 | Stub 触发 | 仅手动 / **手动 + 60 天自动建议** | **手动 + 自动建议** | Insights 页推荐，不强制 |
| D15 | App 自身更新 | 手动检查 / **Sparkle 自动更新** | **Sparkle** | Mac App 标配 |
| D16 | 视觉设计参考 | 自创 / **Surge for Mac** / Setapp / 其他 | **Surge for Mac** | 用户挑选。设计语言落到独立的 [STYLE.md](./STYLE.md) |

---

## 3. 产品形态

### 3.1 导航架构

```
┌── Sidebar ──────────┬── 内容区 ───────────────────┐
│                     │                              │
│ DISCOVER            │                              │
│  ✨ Featured        │                              │
│  🗂 Repositories    │       [主内容区域]            │
│                     │                              │
│ MY LIBRARY          │                              │
│  📦 Installed (61)  │                              │
│  ⬇ Updates          │                              │
│  💾 Backups         │                              │
│  🕐 Recently Used   │                              │
│                     │                              │
│ INSIGHTS            │                              │
│  📈 Usage           │                              │
│  💳 Token Spend     │                              │
│  💤 Idle Candidates │                              │
│                     │                              │
│ ─────               │                              │
│ ⚙ Settings          │                              │
└─────────────────────┴──────────────────────────────┘
```

当前 SwiftUI 实现用 `NavigationSplitView` 两栏结构，侧边栏与 `RootView.swift` 的 `SidebarSelection` 保持一致。

说明：
- `Categories` / `Top Charts` 不再作为独立入口，合并进 Discover 的搜索、分组和排序体验。
- `Stubs` 不再作为独立入口，作为 Library 的过滤 tab（All / Active / Inactive / Stubs）。
- `Repositories` 是独立管理页，用于启停 CC Switch 发现源，并驱动 Discover 刷新。
- `Backups` 是独立管理页，用于查看和恢复 skill 备份。
- `WebDAV`、sidecar health、AgentShield 状态汇总在 Settings 中展示；WebDAV 当前是只读状态/远端探测，手动配置和主动同步留给 v0.1 收口。

### 3.2 五个核心页面

#### Page 1 — Featured (Discover 首页)

```
┌─────────────────────────────────────────────┐
│ Skills Store                  🔍 [Search]  │
├─────────────────────────────────────────────┤
│  ┌─ EDITOR'S PICK ──────────────────────┐  │
│  │  🪨  caveman                          │  │
│  │  "Cut 65% tokens by caveman speak"   │  │
│  │  ⭐ 58k  •  by JuliusBrussee         │  │
│  │              [▼ Install]              │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  🔥 New This Week                 See All → │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐        │
│  │card│ │card│ │card│ │card│ │card│        │
│  └────┘ └────┘ └────┘ └────┘ └────┘        │
│                                             │
│  📈 Top Installed                 See All → │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐        │
│  └────┘ └────┘ └────┘ └────┘ └────┘        │
│                                             │
│  🎯 Curated for You              See All → │
│  （based on what's in your Library）        │
└─────────────────────────────────────────────┘
```

数据源：
- **Editor's Pick**：本地硬编码列表（v1）→ 接 GitHub 一个 JSON（v2）
- **New This Week**：fetch awesome-list 仓库的 git log，按 commit 时间排
- **Top Installed**：从 skills.sh 公共目录（CC Switch 已对接）
- **Curated for You**：根据本地 Library 标签做关键词匹配，**不传任何数据出去**

#### Page 2 — Library（已装）

```
┌─────────────────────────────────────────────┐
│ Installed (47)               🔍 [Filter ▼] │
├─────────────────────────────────────────────┤
│ ▸ All  ▹ Active(32) ▹ Inactive(3) ▹ Stub(12)│
├─────────────────────────────────────────────┤
│ ┌──┐ guanyuan-majia                         │
│ │██│ Last used 2h ago · 412 calls          │
│ └──┘ ✓ Claude  ✗ Codex  ✗ Gemini      ⋯   │
│ ─────────────────────────────────────────── │
│ ┌──┐ lark-im            ⬇ Update v2.2.0    │
│ │██│ Last used 1h ago · 224 calls          │
│ └──┘ ✓ Claude  ✗ Codex  ✗ Gemini      ⋯   │
│ ─────────────────────────────────────────── │
│ ┌──┐ baoyu-image-gen                        │
│ │██│ Last used 5h ago · 178 calls          │
│ └──┘ ✓ Claude  ✗ Codex  ✗ Gemini      ⋯   │
│ ─────────────────────────────────────────── │
│ ┌──┐ old-translator                ☁ Stub   │
│ │░░│ Last used 4mo ago · 8 calls           │
│ └──┘ Tap ☁ to re-download         ⋯       │
└─────────────────────────────────────────────┘
```

**关键交互**：行内 toggle 直接点击切换启用状态。这是相对 CC Switch 最大的体验改进。

#### Page 3 — Detail

```
┌─────────────────────────────────────────────┐
│  ← Library                          🔗 ⋯  │
├─────────────────────────────────────────────┤
│   ┌─────┐  caveman                         │
│   │ 🪨  │  by JuliusBrussee                │
│   │     │  v0.3.2 · ⭐ 58,574              │
│   └─────┘                                  │
│                                            │
│           [▼ Install / Update]             │
│                                            │
│  ── Enable in ──────────────────────       │
│   ☑ Claude     ☐ Codex     ☐ Gemini       │
│                                            │
│  ── Description ─────────────────────      │
│  Cuts 65% of tokens by talking like        │
│  caveman. Compatible with all Claude       │
│  Code workflows.                           │
│                                            │
│  ── Your Usage ──────────────────────      │
│  Last 30 days: 96 calls · 412k tokens     │
│  ████████████░░░░░░░░░ Heavy user         │
│                                            │
│  ── Version History ─────────────────      │
│  • v0.3.2 — 2d ago — Bug fixes            │
│  • v0.3.1 — 1w ago — More rules           │
│                                            │
│  ── Source ──────────────────────────      │
│  github.com/JuliusBrussee/caveman    🔗   │
└─────────────────────────────────────────────┘
```

#### Page 4 — Updates

```
┌─────────────────────────────────────────────┐
│ Updates                   [Update All (3)] │
├─────────────────────────────────────────────┤
│ ℹ Auto-update is ON · Check every 6h       │
├─────────────────────────────────────────────┤
│ ┌──┐ lark-im                                │
│ │██│ v2.1.0 → v2.2.0                       │
│ └──┘ • Added attachment support             │
│       • Fixed thread parsing                │
│              [What's New]    [Update]       │
│ ─────────────────────────────────────────── │
│ ┌──┐ baoyu-image-gen                        │
│ │██│ v1.4 → v1.5                            │
│ └──┘ • New themes                           │
│              [What's New]    [Update]       │
└─────────────────────────────────────────────┘
```

**注意**：CC Switch 用 contentHash 比对（不靠 semver）。所以 v1 只显示"内容已变更"，不渲染 diff。v2 再做。

#### Page 5 — Insights（杀手锏）

```
┌─────────────────────────────────────────────┐
│ Usage Insights              Last 30 days ▼ │
├─────────────────────────────────────────────┤
│                                             │
│  📊 Total Calls       1,247                │
│  🪙 Total Tokens      18.3M                │
│  💵 Estimated Cost    $43.21               │
│                                             │
│  ─── Top by Frequency ──────────────────   │
│  ███████████████  guanyuan-majia  412      │
│  ████████         lark-im         224      │
│  ██████           baoyu-image-gen 178      │
│  ████             caveman          96      │
│  ███              majia-ota-skill  78      │
│                                             │
│  ─── Token Hogs ─────────────────────      │
│  guanyuan-majia ── 8.2M (45%)              │
│  baoyu-image-gen ─ 3.1M (17%)              │
│                                             │
│  ─── 💤 Hibernate Candidates ───────────   │
│  12 skills idle for 60+ days                │
│  • old-translator       [→ Stub]           │
│  • test-experiment      [→ Stub]           │
│  • lark-old-cli         [→ Stub]           │
│  [Stub All]                                 │
│                                             │
└─────────────────────────────────────────────┘
```

### 3.3 Skill 状态机

```
       discover
未发现 ──────────► Available（货架可见）
                       │
              install  │
                       ▼
                ┌──────────────┐
                │ Installed    │ ← toggle ─┐
                │  + Active    │           │
                │  (某个 app   │           │
                │   启用)      │           │
                └──────┬───────┘           │
                       │ disable all       │
                       ▼                   │
                ┌──────────────┐           │
                │ Installed    │ ──────────┘
                │  + Inactive  │
                │  (装着但全禁)│
                └──────┬───────┘
                       │
              hibernate│  (60d 没用，或手动)
                       ▼
                ┌──────────────┐
                │  Stub        │
                │  (本地内容删 │
                │   metadata 留)│
                └──────┬───────┘
                       │
        rehydrate ◄────┤────► hard-uninstall
        (再装)          │
                       ▼
                  不再追踪

   ★ 任何状态遇到 remote hash 变化
     → 叠加 "Has Update" 标记
```

### 3.4 视觉设计语言

**详见独立文档 [STYLE.md](./STYLE.md)**。

灵感来源：**Surge for Mac**（用户审美 anchor）。核心要素：
- 浅紫白渐变背景 + 大量白色圆角卡片
- 彩色 section heading 循环（橙/紫/蓝/绿）替代分块背景
- 关键数据用 56pt+ 大字号 SF Pro Rounded
- 页面级 toggle 直接挂 H1 旁边
- 两套图标体系：导航单色 SF Symbols / 设置入口彩色拟物
- Skill 头像 v1：首字母 + hash 到固定底色（用 `.gradient` 自带渐变）

### 3.5 UX 关键决策

| 决策 | 选项 | 选了 | 理由 |
|---|---|---|---|
| Stub 视觉 | 隐藏 / 灰图标+云角标 / 单独 tab | 灰图标 + 云角标，留在 Library 里 | 跟 App Store"已购未下载"一致 |
| 应用矩阵交互 | 详情页切 / 行内切 | 行内切 | CC Switch 痛点的根治 |
| 搜索 | 全局搜 / 上下文感知 | 上下文感知 | Discover 搜全网，Library 搜本地 |
| 首次启动 | 空白页 / 一键收编 | **一键收编 `~/.cc-switch/skills/` + `~/.claude/skills/`** | 避免空界面恐惧症 |

---

## 4. 技术架构

### 4.1 总体架构图

```
┌─────────────────────────────────────────────────────────┐
│                  Popskill.app (SwiftUI)                  │
│                                                          │
│  Views (NavigationSplitView) ◄── ViewModels (@Observable)│
│           │                              │              │
│           ▼                              ▼              │
│   ┌──────────────┐              ┌──────────────────┐    │
│   │ SkillCLIClient│              │ LocalDB (GRDB)   │    │
│   │ (Process pkg) │              │ ~/.popskill/db   │    │
│   └──────┬───────┘              └────────┬─────────┘    │
│          │                                │             │
│          │              ┌─────────────────┘             │
│          │              ▼                               │
│          │      ┌─────────────────┐                     │
│          │      │ TranscriptParser│                     │
│          │      │ (~/.claude/...) │                     │
│          │      └─────────────────┘                     │
└──────────┼──────────────────────────────────────────────┘
           │ Process.run("skill-cli list --json")
           ▼
┌─────────────────────────────────────────────────────────┐
│                    skill-cli (Rust)                      │
│         clap 解析参数 → 调 cc_switch_lib::services       │
└──────────────────────────┬──────────────────────────────┘
                           │ pub use SkillService
                           ▼
┌─────────────────────────────────────────────────────────┐
│         cc_switch_lib (git submodule, 不改)              │
│   SkillService / Database / WebDavSync / ...             │
│              数据落到 ~/.cc-switch/                       │
└─────────────────────────────────────────────────────────┘
```

### 4.2 为什么是 Sidecar 路线（D4 决策）

考虑过 5 个路线：

| 路线 | 复用度 | 难度 | 升级成本 | 否决理由 |
|---|---|---|---|---|
| R1. Rust→静态库 FFI | 95% | ⭐⭐⭐⭐ | 高 | FFI 桥太难调（async/Result/String 手动处理） |
| **R2. Rust→Sidecar CLI** | **95%** | **⭐⭐⭐** | **几乎零** | **✓ 选这个** |
| R3. Swift 重写后端 | 0% | ⭐⭐⭐⭐ | 零 | 重写 7900 行 Rust，违背初衷 |
| R4. CC Switch 当 headless 服务 | 100% | ⭐⭐ | 高 | 用户要装两个 App，体验崩了 |
| R7. 用 npx skills 当后端 | 60% | 中 | 零 | 失去 WebDAV/应用矩阵/备份/恢复 |

### 4.3 静态可行性证据

下面这些都是从 cc-switch v3.14.1 源码扒出来的，**没真编过**（详见 §13 验证清单）：

| 文件 | 证据 |
|---|---|
| `src-tauri/Cargo.toml` | `crate-type = ["staticlib", "cdylib", "rlib"]` —— 本身就以 rlib 形式提供 |
| `src-tauri/src/lib.rs:52-56` | `pub use services::{SkillService, ...}` —— 外部 crate 直接可调 |
| `src-tauri/src/services/skill.rs` | 3042 行，**0 处 `tauri::` 引用** |
| `src-tauri/src/services/webdav.rs` | 554 行，0 处 tauri |
| `src-tauri/src/services/webdav_sync.rs` | 884 行，0 处 tauri |
| `src-tauri/src/services/webdav_auto_sync.rs` | 4 处 tauri（唯一耦合点） |
| `src-tauri/src/database/mod.rs` | 0 处 tauri，`Database::init()` 无参 |
| `src-tauri/src/error.rs` | 0 处 tauri |
| `src-tauri/src/app_config.rs` | 0 处 tauri |

**唯一耦合点**：`webdav_auto_sync.rs` 用 `tauri::AppHandle + Emitter` 给前端 emit 事件。处理方式：sidecar 模式下不用这个文件，自动同步在 SwiftUI 用 `Timer` 实现。

### 4.4 升级跟随策略

由于 cc-switch 是 git submodule + path dep，零修改：

```bash
# 升级流程
cd ~/projects/popskill/cc-switch
git fetch
git checkout v3.15.0   # 或者最新 release tag

# 然后回项目根
cd ..
cd skill-cli && cargo build   # 重新编译，看有没有 API 变化
```

**真实兼容风险**：CC Switch 改 services 公共 API 签名。看 v3.x 节奏，平均一年 1-2 次大变。每次只需要改 `skill-cli/src/main.rs` 几行。

---

## 5. 项目结构

```
~/projects/popskill/
├── PLAN.md                         ← 你正在看的这个
├── README.md                       ← 公开 README
├── STYLE.md                        ← 视觉设计语言
├── LICENSE
├── .gitignore
├── .gitmodules                     ← 引用 cc-switch
│
├── cc-switch/                      ← git submodule（一行不改）
│   └── (CC Switch 完整仓库)
│
├── skill-cli/                      ← Rust sidecar binary
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── src/
│       └── main.rs                 ← clap 入口 + sidecar commands + tests
│
├── swift-app/
│   ├── Package.swift               ← Swift Package macOS app
│   ├── Sources/Popskill/
│   │   ├── PopskillApp.swift       ← @main 入口
│   │   ├── Components/
│   │   │   └── CommonViews.swift
│   │   ├── Design/
│   │   │   └── PopskillColors.swift
│   │   ├── Models/
│   │   │   ├── SkillModels.swift   ← CLI Codable 模型 + app matrix
│   │   │   └── UsageModels.swift
│   │   ├── Security/
│   │   │   └── KeychainService.swift
│   │   ├── Services/
│   │   │   └── SkillCLIClient.swift ← Process 包装
│   │   ├── Storage/
│   │   │   └── TranscriptUsageScanner.swift
│   │   └── Views/
│   │       ├── RootView.swift      ← NavigationSplitView
│   │       ├── DiscoverView.swift
│   │       ├── RepositoriesView.swift
│   │       ├── LibraryView.swift
│   │       ├── LibraryViewModel.swift
│   │       ├── UpdatesView.swift
│   │       ├── BackupsView.swift
│   │       ├── RecentActivityView.swift
│   │       ├── InsightsView.swift
│   │       ├── TokenSpendView.swift
│   │       ├── IdleCandidatesView.swift
│   │       └── SettingsView.swift
│   └── Tests/PopskillTests/
│       ├── SkillCLIClientTests.swift
│       ├── SkillModelsTests.swift
│       ├── LibraryFilterTests.swift
│       ├── RepositoryInputTests.swift
│       ├── TranscriptUsageScannerTests.swift
│       ├── KeychainServiceTests.swift
│       └── CommonViewsTests.swift
│
├── docs/
│   ├── ipc.md                      ← Swift ↔ skill-cli 协议
│   ├── security.md                 ← AgentShield / install gate
│   └── transcript-parsing.md       ← jsonl 归因策略
│
└── scripts/
    ├── ci-local.sh                 ← 本地 CI 总入口
    ├── dev-build.sh
    ├── run-app.sh
    ├── smoke-cli.sh
    ├── smoke-cli-mutating.sh
    ├── smoke-app.sh
    ├── smoke-bundle.sh
    ├── package-dev-app.sh
    ├── package-dmg.sh
    ├── release-doctor.sh
    ├── release-manifest.sh
    ├── generate-appcast.sh
    ├── smoke-release.sh
    └── notarize.sh
```

---

## 6. 技术栈

### 6.1 SwiftUI 端

| 用途 | 选型 | 版本 | 装法 |
|---|---|---|---|
| UI 框架 | SwiftUI | macOS 14+ | 系统自带 |
| 最低系统 | macOS 14 Sonoma | - | - |
| Swift 版本 | 5.9+ | - | Xcode 15+ |
| 状态管理 | `@Observable` 宏 | Swift 5.9+ | 标准库 |
| SQLite ORM | [GRDB.swift](https://github.com/groue/GRDB.swift) | 6.x | SPM |
| YAML 解析 | [Yams](https://github.com/jpsim/Yams) | 5.x | SPM |
| Markdown 渲染 | [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | 2.x | SPM |
| 自动更新 | [Sparkle](https://sparkle-project.org/) | 2.x | SPM |
| 测试 | XCTest | - | Xcode 自带 |

### 6.2 Rust 端 (skill-cli)

| 用途 | 选型 | 版本 |
|---|---|---|
| Rust toolchain | rustup → stable | 1.85+ (跟 cc-switch 对齐) |
| CLI 框架 | clap | 4.x |
| 序列化 | serde + serde_json | latest |
| 异步 | tokio | 1.x，跟 cc-switch 对齐 features |
| 错误 | anyhow | 1.x |
| cc-switch 引用 | path dep | submodule |

### 6.3 工具链

| 用途 | 工具 |
|---|---|
| Xcode | 15+ |
| Rust | rustup |
| Git submodule | git ≥ 2.40 |
| 测试 macOS 版本 | macOS 14+ |

---

## 7. 数据模型

### 7.1 SwiftUI 端模型

```swift
// Models/App.swift
enum TargetApp: String, Codable, CaseIterable {
    case claude, codex, gemini, opencode, openclaw, hermes
}

// Models/SkillState.swift
enum SkillState: Codable {
    case available                              // 货架可见，本地没装
    case installedActive(apps: Set<TargetApp>)  // 装了，至少一个 app 启用
    case installedInactive                      // 装了，全部 app 禁用
    case stub(originallyInstalledAt: Date)      // 本地内容删，metadata 留
}

// Models/Skill.swift
@Observable
final class Skill: Identifiable {
    let id: String                  // "owner/name:directory"
    var name: String
    var description: String
    var directory: String
    var repoOwner: String?
    var repoName: String?
    var repoBranch: String?
    var readmeUrl: String?

    var state: SkillState
    var hasUpdate: Bool
    var installedAt: Date?
    var updatedAt: Date?
    var contentHash: String?

    // Popskill 独有字段
    var lastUsedAt: Date?
    var totalCalls: Int
    var totalTokensSpent: Int64
    var avgTokensPerCall: Int64
}

// Models/UsageStat.swift
struct UsageEvent: Codable {
    let skillId: String
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let sessionId: String
}
```

### 7.2 本地 SQLite Schema（Popskill 自己的）

```sql
-- ~/.popskill/popskill.db

CREATE TABLE skill_local_state (
    id TEXT PRIMARY KEY,            -- 对应 cc_switch.installed_skill.id
    state TEXT NOT NULL,            -- "active" | "inactive" | "stub"
    stubbed_at INTEGER,             -- Unix timestamp
    pinned BOOLEAN DEFAULT 0,       -- 用户置顶
    notes TEXT                       -- 用户私人备注
);

CREATE TABLE usage_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    skill_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    cache_read_tokens INTEGER DEFAULT 0
);

CREATE INDEX idx_usage_skill_time ON usage_events(skill_id, timestamp DESC);

CREATE TABLE transcript_cursor (
    file_path TEXT PRIMARY KEY,
    last_line_offset INTEGER NOT NULL,
    last_processed_at INTEGER NOT NULL
);
-- 用来增量解析 jsonl，避免每次全量扫

CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

### 7.3 跟 CC Switch SQLite 的关系（D10）

- **CC Switch 的 SQLite (`~/.cc-switch/cc-switch.db`)** 是 skill metadata 的 SSOT
- **Popskill 的 SQLite (`~/.popskill/popskill.db`)** 只存:
  - 使用统计（CC Switch 没有的）
  - 本地状态机字段（Stub/pinned/notes）
- **不重复存** name/description/repoOwner 等 —— 这些通过 skill-cli 查
- **写 metadata 的唯一路径** = skill-cli → cc_switch_lib，Popskill 不直接改 cc-switch.db

---

## 8. Sidecar 接口设计

### 8.1 总原则

- skill-cli 所有输出走 **stdout JSON**
- 错误走 **stderr + 非 0 exit code**
- 每个子命令一个独立的 JSON Schema，文档在 `docs/ipc.md`

### 8.2 子命令清单

```bash
skill-cli health --json
  → sidecar 路径、CC Switch 目录、repository / backup 计数、Keychain 策略等诊断

skill-cli webdav-status [--json]
  → 读取 CC Switch WebDAV sync 设置并脱敏输出

skill-cli webdav-configure --base-url=<url> --username=<u> --password-env=<env> --remote-root=<root> --profile=<profile> --enabled=<true|false> --auto-sync=<true|false> [--json]
  → 写入 CC Switch WebDAV sync 设置；密码只通过环境变量传入，省略 password-env 时保留旧密码

skill-cli webdav-remote-info [--json]
  → 复用 CC Switch 远端 manifest 查询（未配置/未启用时失败）

skill-cli webdav-sync-plan [--json]
  → 返回手动 upload/download readiness 与 CC Switch private/Tauri 边界原因，不修改本地或远端状态

skill-cli list [--json]
  → 输出所有已装 skill（对应 SkillService::get_all_installed）

skill-cli agent-list [--root=<agents-dir>] [--json]
  → 只读列出本机 Claude Code agents（默认 ~/.claude/agents，解析 frontmatter 的 name/description/tools/model）

skill-cli agent-targets [--json]
  → 只读列出 AgencyAgents 验证过的 Agent-capable 工具目标路径与本机 detected 状态

skill-cli agent-catalog [--query=<text>] [--limit=<n>] [--json]
  → 只读发现 AgencyAgents 的 installable Agent markdown，解析 frontmatter 作为后续安装计划输入

skill-cli agent-install-plan <agent-key> --target=<target-id> [--json]
  → 只读预览 AgencyAgents Agent 安装到某个 Agent-capable 工具时的写入路径、冲突和格式转换需求

skill-cli detail <skill-id> [--json]
  → 单个 skill 详情

skill-cli toggle <skill-id> --app=<claude|codex|gemini> --enabled=<true|false>
  → 切换某 app 的启用状态

skill-cli install <skill-key> --app=<claude>
  → 安装（从已知 registry）

skill-cli install-plan <skill-key> --app=<claude>
  → 只读预览安装目标 app、来源仓库、写入路径、安全 gate

skill-cli uninstall <skill-id> [--keep-backup]
  → 卸载

skill-cli stub-list [--json]
  → 列出 Popskill stub metadata（存于 ~/.popskill/stubs.json，指向 CC Switch backup）

skill-cli stub <skill-id>
  → Popskill 独有：把 skill 转为 Stub（CC Switch 负责卸载与备份，Popskill 留 metadata）

skill-cli rehydrate <skill-id> --app=<claude>
  → 从 Stub 状态恢复（从保存的 backup id 还原，并启用目标 app）

skill-cli security-scan <skill-dir> [--skill-id=<skill-id>] [--json]
  → 调 ECC AgentShield，输出 verified / warning / blocked / unavailable 结果，并可持久化到本地角标

skill-cli security-scan-list [--json]
  → 列出已持久化的 AgentShield 扫描结果

skill-cli update <skill-id>
  → 更新单个 skill

skill-cli check-updates [--json]
  → 列出所有有 update 的 skill

skill-cli discover [--query=<text>] [--json]
  → 从所有 registry 拉可发现的 skill

skill-cli repo-list [--json]
  → 列出 CC Switch skill discovery repositories

skill-cli repo-add --owner=<owner> --name=<repo> --branch=<branch> --enabled=<true|false> [--json]
  → 添加自定义 skill repository（owner/name 会规范化并校验）

skill-cli repo-toggle --owner=<owner> --name=<repo> --enabled=<true|false> [--json]
  → 启停一个 discovery repository

skill-cli repo-remove --owner=<owner> --name=<repo> [--json]
  → 删除一个 discovery repository

skill-cli scan-unmanaged [--json]
  → 扫野生 skill（~/.claude/skills 下没纳入管理的）

skill-cli import-unmanaged <directory> --app=<claude>
  → AgentShield 扫描后把野生 skill 收编

skill-cli backup-list [--json]
  → 列备份

skill-cli backup-restore <backup-id> --app=<claude>
  → 从备份恢复

skill-cli backup-delete <backup-id> [--json]
  → 删除一份 uninstall backup
```

后续未完成但已确定要补的接口：

```bash
skill-cli webdav sync-now
  → 立刻触发同步

skill-cli search-skills-sh --query=<text> --limit=20 --offset=0 [--json]
  → 搜 skills.sh 公共目录

skill-cli install-plan <skill-key> --app=<claude>
  → 参考 ECC manifest-driven install，先输出将写入/覆盖/启用的计划
```

### 8.3 JSON 输出示例

```json
// skill-cli list --json
{
  "ok": true,
  "data": [
    {
      "id": "anthropics/skills:pdf",
      "name": "PDF Skill",
      "description": "Use this skill whenever the user wants to do anything with PDF files",
      "directory": "pdf",
      "repoOwner": "anthropics",
      "repoName": "skills",
      "repoBranch": "main",
      "apps": {
        "claude": true,
        "codex": false,
        "gemini": false
      },
      "installedAt": 1731412345,
      "updatedAt": 1731412345,
      "contentHash": "abc123..."
    }
  ]
}

// 错误情况
{
  "ok": false,
  "error": {
    "code": "SKILL_NOT_FOUND",
    "message": "Skill 'foo/bar' not found in any configured repo",
    "details": { "queried": "foo/bar" }
  }
}
```

### 8.4 skill-cli 主入口骨架

```rust
// skill-cli/src/main.rs

use anyhow::Result;
use clap::{Parser, Subcommand};
use std::sync::Arc;
use cc_switch_lib::{Database, SkillService};

#[derive(Parser)]
#[command(name = "skill-cli", version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    List { #[arg(long)] json: bool },
    Toggle { skill_id: String, #[arg(long)] app: String, #[arg(long)] enabled: bool },
    Install { skill_key: String, #[arg(long)] app: String },
    Uninstall { skill_id: String, #[arg(long)] keep_backup: bool },
    Update { skill_id: String },
    CheckUpdates { #[arg(long)] json: bool },
    Discover { #[arg(long)] query: Option<String>, #[arg(long)] json: bool },
    // ... 其他子命令
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let db = Arc::new(Database::init()?);
    let service = SkillService::new();

    match cli.command {
        Commands::List { json } => commands::list::run(&db, json).await,
        Commands::Toggle { skill_id, app, enabled } => {
            commands::toggle::run(&db, &skill_id, &app, enabled).await
        }
        // ... 其他分发
    }
}
```

### 8.5 skill-cli/Cargo.toml 骨架

```toml
[package]
name = "skill-cli"
version = "0.1.0"
edition = "2021"

[dependencies]
cc_switch_lib = { path = "../cc-switch/src-tauri" }
clap = { version = "4", features = ["derive"] }
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
anyhow = "1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

### 8.6 SwiftUI 端调 skill-cli

```swift
// SkillCLI/SkillCLIClient.swift

import Foundation

actor SkillCLIClient {
    private let cliPath: String

    init() {
        // 开发期：从项目目录读
        // 发布期：从 .app/Contents/MacOS/skill-cli 读
        self.cliPath = Bundle.main.path(forResource: "skill-cli", ofType: nil)
            ?? "\(NSHomeDirectory())/projects/popskill/skill-cli/target/release/skill-cli"
    }

    func list() async throws -> [CLISkillData] {
        let result = try await run(args: ["list", "--json"])
        return try JSONDecoder().decode(CLIResponse<[CLISkillData]>.self, from: result).data
    }

    func toggle(skillId: String, app: TargetApp, enabled: Bool) async throws {
        _ = try await run(args: [
            "toggle", skillId,
            "--app", app.rawValue,
            "--enabled", String(enabled)
        ])
    }

    private func run(args: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = args

        let stdout = Pipe()
        process.standardOutput = stdout

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SkillCLIError.exitCode(Int(process.terminationStatus))
        }

        return stdout.fileHandleForReading.readDataToEndOfFile()
    }
}

struct CLIResponse<T: Decodable>: Decodable {
    let ok: Bool
    let data: T
}
```

---

<a id="9-第一周-milestone-day-1-5"></a>

## 9. 第一周 Milestone (Day 1-5) —— ✅ 已全部完成（2026-05-13）

> 这一节现在是历史 bootstrap 记录：最初目标是“周末有一个能跑、能看到本机 skills、能切换 Claude/Codex/Gemini 启用状态的 demo”。当前实现已经超过这个目标，后续推进以 §10 的发布收口清单为准。

| Day | 原目标 | 当前状态 | 证据 |
| --- | --- | --- | --- |
| ✅ Day 1 | 项目 init，Rust + Swift 能跑 | 已完成 | `skill-cli` workspace、`swift-app` Swift Package、`scripts/ci-local.sh` 已打通 |
| ✅ Day 2 | `skill-cli list` 输出本机 skills JSON | 已完成并扩展 | 已有 `list` / `detail` / `toggle` / `discover` / `install-plan` / `install` / `update` / `uninstall` / `import-unmanaged` / `backups` / `repositories` / `webdav` |
| ✅ Day 3 | SwiftUI 主框架 + 侧边栏入口 | 已完成并扩展 | `RootView.swift` 已有 Discover、Repositories、Library、Updates、Backups、Recently Used、Insights、Token Spend、Idle Candidates、Settings |
| ✅ Day 4 | Library 接 `skill-cli` 数据 | 已完成 | `SkillCLIClient` + `LibraryViewModel` + Library UI 已接 sidecar 数据 |
| ✅ Day 5 | 行内 Claude/Codex/Gemini toggle | 已完成并扩展 | App 矩阵已覆盖 Claude、Codex、Gemini、OpenCode、Hermes，toggle 走 sidecar/CC Switch 状态 |

实际已超出第一周计划的内容：
- Discover 已接 repository discovery、安装计划预览、AgentShield scan gate。
- Library 已有 unmanaged import、AgentShield 状态持久化、stub / rehydrate 和 idle candidates。
- Updates、Backups、Repositories 已成为独立页面。
- Insights 已有 transcript 解析基础、recent activity、token spend。
- Settings 已展示 sidecar health、repositories、backup path、WebDAV status、remote snapshot 和 manual sync readiness。
- release pipeline 已有 DMG、manifest、Sparkle appcast 的 smoke 脚本。

---

<a id="10-后续阶段-week-2-8"></a>

## 10. 后续阶段 (Week 2-8) —— 当前进度校准

| 原阶段 | 原计划 | 当前状态 | 发布前剩余 |
| --- | --- | --- | --- |
| Week 2 | Discover 页 V1 | ✅ 已完成 | 做视觉 polish，补截图/空态文案；Categories/Top Charts 不做独立路由 |
| Week 3 | Detail 页 + 安装/卸载流程 | ✅ 已完成 | install-plan 目标 App 缓存和风险解释已打磨；更细的失败态仍可继续补 |
| Week 4 | Insights + transcript 解析 | ✅ 已完成 | 已验证真实 `attributionSkill` / `attributionPlugin` 字段；Usage / Token Spend 可展示 skill 级统计，仍忽略正文 |
| Week 5 | Updates 页 + 自动检查 | ✅ Updates 页面完成，含 Update All 和 last checked 状态 | Popskill 自身更新已有 Sparkle SDK link、菜单入口、配置守卫和 package hooks；公开更新检查仍待 feed/key/signature 实测 |
| Week 6 | Stub 状态机 | ✅ 已完成 | 60 天建议已落在 Idle Candidates，并避开最近 60 天内有 transcript attribution 使用的 skill |
| Week 7 | WebDAV 同步 UI | 🟡 配置/只读边界已完成 | Settings 已有配置写入、status + remote info；Sync Now 留给 v0.1 收口 |
| Week 8 | 打磨 + 打包 | 🟡 pipeline 已打通，release doctor 可检查 Developer ID/notary/Sparkle bundle 前置条件，README 截图已补 | 需要 Apple Developer Program 通过、真实签名/公证、Sparkle 公开更新实测和人工验收 |

### v0.1 收口清单

- [x] sidecar/library 主链路：本机 list/detail/toggle/import/update/uninstall/backups/repositories。
- [x] Discover 安装计划：安装前可预览目标路径、动作、目标 App 和 AgentShield rollback；切换目标 App 会清掉旧计划。
- [x] AgentShield gate：unmanaged import 和 discover install 均能阻断高风险 skill。
- [x] Stub MVP：stub/rehydrate、Idle Candidates、bulk stub dry-run/执行。
- [x] WebDAV sidecar 边界：配置写入 / 只读 status / remote info / manual sync plan / local backup summary。
- [x] Agent sidecar smoke：`agent-list` / `agent-targets` / `agent-install-plan` 已纳入只读 smoke；`agent-catalog` 因 GitHub rate limit 不进默认 CI。
- [x] release smoke：DMG、release manifest、Sparkle appcast 生成脚本。
- [x] release doctor：检查 Developer ID、notarytool/stapler、notary 凭据、app/dmg/appcast 和 Sparkle framework/rpath 前置条件。
- [x] release runbook：`docs/release-runbook.md` 写明 Developer ID、notary keychain profile、Sparkle env、notarize、DMG、appcast 和 Gatekeeper 验证步骤。
- [x] release notes draft：`docs/release-notes-v0.1.md` 写明 highlights、隐私边界、已知限制和验证入口。
- [x] 视觉 polish 第一轮：Discover 行内 `Plan` / `Install` 可读，带 badge 的 sidebar 项可导航，Library 行内 app toggle 不挤压标题。
- [x] 视觉 polish 收尾：Settings 诊断字段紧凑化，Updates 空态隐藏不可用批量操作。
- [ ] Apple Developer Program：确认是否加入；不加入则只能走 ad-hoc/unsigned 分发说明。
- [ ] 真实签名/公证：接入 Developer ID 后跑 `notarytool`，补 CI/本地验证文档。
- [x] Sparkle SDK link：App 已正式链接 Sparkle 2.9.1，当前已完成菜单入口、`SUFeedURL` / `SUPublicEDKey` 配置守卫、bundle framework copy hooks、release doctor 检查与 Sparkle key/sign_update wrapper。
- [ ] Sparkle public update smoke：配置真实 feed、public EdDSA key、signed notarized payload 后，在 App 内完成一次公开更新检查。
- [x] WebDAV 配置表单：Settings 可写入 CC Switch WebDAV settings；新密码通过 sidecar 环境变量传递，状态输出脱敏。
- [ ] WebDAV Sync Now：upload/download、冲突/失败态；当前先以 `webdav-sync-plan` 暴露明确 blocked readiness。
- [x] Transcript boundary：UI/文档说明本地聚合并忽略消息正文。
- [x] Transcript attribution：已验证真实 `attributionSkill` 调用标记，补 skill 级归因统计与 Idle Candidates 最近使用过滤。
- [x] README 截图：Discover、Library、Usage Insights、Idle Candidates 真实界面截图已补到 `docs/assets/screenshots/`。
- [x] Screenshot asset smoke：`scripts/smoke-screenshots.sh` 校验 README 截图存在、PNG 格式、尺寸和文件大小，并接入本地 CI。
- [x] v0.1 QA checklist：`docs/v0.1-qa-checklist.md` 写明自动门、视觉检查、隐私检查、release artifact 和 notarized build 验收项。
- [ ] 最终视觉 QA：发布前再做一次全局一致性检查。

---

## 11. 已知坑 / 风险预案

### 11.1 Day 1 第一次 cargo build 可能踩的坑

**坑 1**：`cc-switch` 用了 `tauri-build` build script，可能在没有 Tauri runtime 的情况下编不过。

**预案**：
- 看 `cc-switch/src-tauri/build.rs`
- 如果 build script 强依赖 Tauri，可能需要在 `skill-cli/Cargo.toml` 加 `[features]` 排除掉
- 最差情况：fork cc-switch 改一行 `build.rs`，第一次升级要 rebase

**坑 2**：某些依赖只在 `cdylib` 或 `staticlib` 下编译，不在 `rlib` 下。

**预案**：试编看错误，按需在 Cargo.toml 加 features。

**坑 3**：`rusqlite` 用 `bundled` feature，编译时间很长（包含 C 编译）。第一次可能 15-20 分钟。

**预案**：忍着等。

### 11.2 服务层 API 升级风险

**风险**：CC Switch 改 `SkillService` 公共方法签名。

**预案**：
- 在 `skill-cli` 加一个 `version_compat.rs` 模块封装所有调用
- 每次 cc-switch 升级，只这一个文件可能要改
- 强制升级前先编一遍，失败就改

### 11.3 Transcript 解析归因

**问题**：怎么把 token 消耗归因到具体 skill？

**当前策略（真实 attribution marker）**：
1. 扫 `~/.claude/projects/*/transcript.jsonl`
2. 对包含 `message.usage` 的记录读取顶层 `attributionSkill`
3. 若存在 `attributionSkill`，该 usage 事件直接计入对应 skill；若同时有 `attributionPlugin`，用于 UI 来源角标
4. 没有 attribution marker 的 usage 仍只计入 session/model 汇总，不强行猜测 skill

**风险**：只有 Claude Code 写入 `attributionSkill` 的事件能做 skill 级统计。**接受**。v1 不解析消息正文、不用启发式猜测，优先保证隐私边界与可信度。

**已验证**：
- 真实 transcript 中存在顶层 `attributionSkill`、`attributionPlugin`、`attributionAgent`
- `message.usage` 字段位置稳定，可解析 token 计数
- 多 Claude Code 会话并行时按每条 usage 记录自己的 attribution marker 独立计数

### 11.4 webdav_auto_sync 的 Tauri 耦合

**问题**：4 处 `tauri::` 引用，主要是 `AppHandle + Emitter`。

**预案**：
- sidecar 模式下**不用** `webdav_auto_sync.rs`
- 在 `skill-cli` 暴露 `webdav sync-now` 同步命令（手动触发）
- SwiftUI 用 `Timer` 每 N 分钟调一次 `sync-now`
- 同步状态通过文件（如 `~/.popskill/sync-state.json`）或 SQLite 表落地
- SwiftUI 起一个 file watcher 监听状态变化

### 11.5 Stub 状态实现细节

**问题**：Stub 之后内容删了，怎么记住"原来是哪个 skill"？

**预案**：
- Popskill 自己的 SQLite (`skill_local_state`) 里存 stub 状态 + 原 metadata 引用
- CC Switch 那边的记录可以删掉（uninstall），也可以留着只是 disable —— **选后者**（保留 backup 路径方便 rehydrate）

### 11.6 多用户场景

**问题**：如果用户开了多个 Claude Code session 同时跑 skill，transcript 怎么解析？

**预案**：v1 不处理，按时间窗口归因。v2 看每个 session ID 单独归因。

### 11.7 macOS 公证 / Gatekeeper（发布前必做）

**问题**：未签名 / 未公证的 `.app` 发给朋友试用，下载后会弹 **"Popskill.app 已损坏，无法打开"** 或 **"无法验证开发者"**。`iamzhihuix/skills-manage` 现状就是这样，README 专门教用户 `xattr -dr com.apple.quarantine` 绕过，这是个真实用户流失点。

**预案**：
- **时机**：本地开发不需要；**v0.1 发给第一个外部用户之前必须做完**
- **成本**：Apple Developer Program **$99 / 年**。一个会员覆盖 macOS / iOS / 全平台，notarization 本身免费
- **身份选择**：先用 **Individual**；Organization 需要 D-U-N-S 编号，周期更长
- **证书**：使用 **Developer ID Application**，不是 Mac App Distribution
- **流程**：`package-dev-app.sh` 产出 `.app`（可注入 Sparkle feed/key 并复制 `Sparkle.framework`）→ `codesign --options runtime --timestamp` → `ditto` 压 zip → `xcrun notarytool submit --wait` → `xcrun stapler staple` → `stapler validate` → `package-dmg.sh` 产出带 Applications 拖拽入口的 `.dmg` → `release-manifest.sh` 记录 version / build / sha256 / size → `generate-appcast.sh` 生成 Sparkle appcast 骨架
- **脚本化**：封装成 `scripts/release-doctor.sh`、`scripts/notarize.sh`、`scripts/package-dmg.sh`、`scripts/release-manifest.sh` 与 `scripts/generate-appcast.sh`。每个 Sparkle 更新包都要重新走 codesign + notarize + staple
- **密钥策略**：Apple app-specific password 走环境变量或 Keychain profile；Popskill 自有 PAT / LLM API key 进 Keychain，**不进 SQLite**。WebDAV password 当前由 CC Switch settings 持有，Popskill 仅通过环境变量传给 sidecar，不另存副本。

**验收**：拿一台干净的、没装过 Popskill 的 Mac，从 Releases 下 `.dmg` → 拖进 Applications → 双击打开，**全程零警告弹窗**。

### 11.8 第三方 skill 安全审计（AgentShield）

**问题**：Popskill 做 Discover / Install 之后，本质上是在帮用户把陌生仓库里的 `SKILL.md` 和脚本放进本地 agent 运行路径。没有安装前审计，App Store 隐喻会变成信任风险。

**预案 —— 集成 ECC AgentShield**：
- **来源**：ECC / everything-claude-code 的 AgentShield
- **能力**：约 102 条规则、1282 个测试，覆盖 prompt injection、命令执行、敏感文件访问、网络 exfiltration 等风险模式
- **调用方式**：`npx ecc-agentshield <skill-dir>`，先作为 sidecar 子进程调用，不把 Node runtime 嵌进 SwiftUI
- **当前安装路径**：受 CC Switch `install()` 粒度限制，先 install 到 SSOT 后立即扫描；`blocked` 自动调用 uninstall 回滚。后续补 `install-plan/apply` 后再前移到 apply 前扫描
- **UI 表达**：Library 行与 Detail 卡片显示 `Verified` / `Warning` / `Blocked` / `Unavailable` 安全角标；Detail 展示规则摘要
- **落库**：当前先用 `~/.popskill/security-scans.json` 记录 skill id、skill directory、summary、severity、scanned_at；后续若引入 Popskill 自有数据库，再迁移到 `security_scan_results`
- **离线策略**：规则和 npm 包可预热缓存；离线时显示 `Not scanned`，但不伪装成安全

**验收**：安装第三方 skill 后立即得到扫描状态；构造含危险命令的测试 skill 会被标记为 `Blocked`，并被自动回滚。`install-plan/apply` 落地后，把扫描时机前移到写入目标目录之前。

### 11.9 WebDAV 写同步 sidecar 边界

**当前状态**：`webdav-status` 与 `webdav-remote-info` 可以直接复用 CC Switch re-export 的无状态 command；`webdav-configure` 通过 `get_settings` → JSON patch → `save_settings` 写入 CC Switch settings；`webdav-sync-plan` 以只读 contract 暴露手动 upload/download 的 blocked readiness。Settings 已能配置、显示状态、远端 snapshot 和手动 sync 边界。

**阻塞点**：`webdav_sync_upload` / `webdav_sync_download` 需要 Tauri `State<AppState>`；底层 `services::webdav_sync` 与 `settings::WebDavSyncSettings` 仍在 CC Switch 私有 module 里，Popskill sidecar 不能在不改 submodule 的前提下干净调用。配置写入已绕过类型边界，但 upload/download 仍不能这样处理。

**原则**：不修改 `cc-switch/` submodule，不复制 WebDAV 协议实现。下一步应该等 CC Switch 暴露无 Tauri State 的公共 service API，或在 Popskill 自己侧做一个明确版本锁定的 adapter，并把风险写进测试。

---

## 12. 引用资料

### 12.1 CC Switch 关键源码位置（基于 v3.14.1）

| 模块 | 路径 | 行数 | 用途 |
|---|---|---|---|
| skill service | `cc-switch/src-tauri/src/services/skill.rs` | 3042 | 主业务逻辑 |
| skill commands (Tauri) | `cc-switch/src-tauri/src/commands/skill.rs` | 336 | 你不用，但作为接口参考 |
| skill API surface (TS) | `cc-switch/src/lib/api/skills.ts` | 283 | 接口文档 |
| Database | `cc-switch/src-tauri/src/database/mod.rs` | - | SQLite 入口 |
| DB schema | `cc-switch/src-tauri/src/database/schema.rs` | 2050 | 完整 schema |
| WebDAV transport | `cc-switch/src-tauri/src/services/webdav.rs` | 554 | HTTP 层 |
| WebDAV sync | `cc-switch/src-tauri/src/services/webdav_sync.rs` | 884 | 同步协议 |
| WebDAV auto sync (有 tauri 耦合) | `cc-switch/src-tauri/src/services/webdav_auto_sync.rs` | - | 不用 |
| lib.rs re-exports | `cc-switch/src-tauri/src/lib.rs:52-56` | - | `pub use SkillService` 的关键位置 |
| Cargo.toml | `cc-switch/src-tauri/Cargo.toml` | - | rlib crate-type 配置 |

### 12.2 主仓库

- **CC Switch**：https://github.com/farion1231/cc-switch
- **官方 Anthropic Skills**：https://github.com/anthropics/skills (13万⭐)
- **vercel-labs/skills (npx skills)**：https://github.com/vercel-labs/skills (1.8万⭐)
- **agentskills 规范**：https://github.com/agentskills/agentskills (1.8万⭐)

### 12.3 Awesome-list（v1 Registry 数据源）

聚合这些当 Discover 数据：

- https://github.com/ComposioHQ/awesome-claude-skills (5.9万⭐)
- https://github.com/travisvn/awesome-claude-skills (1.2万⭐)
- https://github.com/BehiSecc/awesome-claude-skills (9k⭐)
- https://github.com/VoltAgent/awesome-agent-skills (2.1万⭐, 1000+ skills)
- https://github.com/sickn33/antigravity-awesome-skills (3.7万⭐, 1400+ skills)
- https://github.com/affaan-m/everything-claude-code (ECC, 18万⭐, 208 skills + 55 agents + AgentShield)
- https://github.com/msitarzewski/agency-agents (9.6万⭐, 80+ agents, 17 分类, MIT；高价值 Agent persona 来源)

### 12.4 相关项目（友商）

**真正同赛道头部**（必看）：

- **iamzhihuix/skills-manage** (1814⭐, Tauri v2 + React 19 + Rust + SQLite) - 中心仓 + symlink 范式，覆盖 OpenClaw 全家桶 https://github.com/iamzhihuix/skills-manage
- **yibie/skills-manager** (152⭐, SwiftUI + SwiftData) - 技术栈撞车，同走 Mac native 路线，AgentRegistry 覆盖 40+ Agent + 内置 LLM sandbox + blessed TUI https://github.com/yibie/skills-manager

**上游内容与安全能力**：

- **affaan-m/everything-claude-code** (18 万⭐) - ECC 内容池 + AgentShield 来源 https://github.com/affaan-m/everything-claude-code
- **msitarzewski/agency-agents** (9.6 万⭐) - 80+ Agent persona、17 分类、MIT，中文圈覆盖强 https://github.com/msitarzewski/agency-agents

**其他参考**：

- **agent-skills-guard** (354⭐, Tauri 桌面端，安全扫描) - 单一功能对手，能力可被 AgentShield 覆盖 https://github.com/bruc3van/agent-skills-guard
- **neuDrive** (178⭐, Go 后端) - 备份服务参考 https://github.com/agi-bar/neuDrive
- **claude-skills-manager**（一堆 0-star 的）- 各种半成品，可看不可抄

### 12.5 SwiftUI / Mac 开发参考

- [Apple SwiftUI 文档](https://developer.apple.com/documentation/swiftui)
- [NavigationSplitView 教程](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [@Observable 宏](https://developer.apple.com/documentation/observation/observable())
- [GRDB.swift 文档](https://swiftpackageindex.com/groue/GRDB.swift/documentation/grdb)
- [Sparkle 集成指南](https://sparkle-project.org/documentation/)

### 12.6 本地资料

- 当前用户的 `~/.cc-switch/` 已经有 cc-switch 数据，包含 ~47 个 skill
- 当前用户的 `~/.claude/skills/` symlink 指向 `~/.cc-switch/skills/`
- 当前用户的 `~/projects/majia-private-skills/` 是私有 skill 仓库

---

## 13. 验证清单

> 这些是**还没被真编验证过**的假设。第一次 cargo build 时核对。

| # | 假设 | 验证方式 | 风险等级 |
|---|---|---|---|
| V1 | `cc_switch_lib` 能作为 path dep 引入 | `cargo build` | 中（lib.rs 已 pub use，应该能） |
| V2 | `Database::init()` 在 sidecar 模式无运行时依赖 | 跑 `skill-cli list` | 低 |
| V3 | `SkillService::get_all_installed(&db)` 同步调用可用 | 同上 | 低 |
| V4 | `SkillService::install()` async 调用在 tokio 下可用 | 跑 `skill-cli install <key>` | 低 |
| V5 | webdav 模块无需 Tauri 上下文可调 | 跑 `skill-cli webdav sync-now` | 中 |
| V6 | transcript.jsonl 包含 `<command-name>` 标签或类似归因信息 | grep/jq 真实 transcript | 低（已验证顶层 `attributionSkill`） |
| V7 | transcript.jsonl 的 `usage` 字段位置稳定 | 同上 | 低（已验证 `message.usage`） |
| V8 | cc-switch `build.rs` 不强依赖 tauri-build 在 lib 模式下 | `cargo build` | 中（可能踩坑） |
| V9 | 行内 toggle 调 toggle_app 后 symlink 立刻生效 | Day 5 验收 | 低 |

### V6/V7 验证小脚本

```bash
# 只抽字段和值的名字，不输出 message.content
find ~/.claude/projects -name '*.jsonl' -print0 \
  | xargs -0 jq -r 'select(.message?.usage? and .attributionSkill?) | .attributionSkill' \
  | sort | uniq -c | sort -nr | head
```

如果未来 Claude Code 改字段名，归因层降级为 session/model 汇总，不能回退到读取正文猜测。

---

## 14. 词汇表

| 术语 | 含义 |
|---|---|
| **SSOT** | Single Source of Truth，CC Switch 用这个词指 `~/.cc-switch/skills/` 这个唯一权威目录 |
| **Skill** | Claude Code / Codex / Gemini 用的 Agent Skill，本质是一个 Markdown 文件（SKILL.md）+ 资源 |
| **Agent** | Claude Code 的 role/persona/subagent 定义，通常是 `~/.claude/agents/*.md` 或分类子目录下的 Markdown 文件，和 Skill 的工具包/能力模块不是同一类对象 |
| **Package / 能力包** | v0.2 规划中的一级商品抽象。一个 Package 表示用户想获得的完整 AI 能力，可包含 Skill、Agent、CLI、MCP、配置 schema、权限和依赖图 |
| **App 矩阵** | 一个 skill 可以在 Claude/Codex/Gemini/OpenCode/OpenClaw/Hermes 这 6 个 app 里独立启用/禁用 |
| **contentHash** | CC Switch 用这个比对 skill 内容是否变化（不靠 semver） |
| **Stub** | Popskill 引入的状态。本地内容已删，但 metadata 留着，UI 显示为云角标卡片 |
| **Hibernate** | 把一个 skill 转为 Stub 的动作 |
| **Rehydrate** | 从 Stub 状态重新下载内容的动作 |
| **Discover** | App Store 的"发现"页，可以浏览未安装的 skill |
| **Library** | 已安装的 skill 列表 |
| **Sidecar** | 主进程旁边跑的辅助进程。Popskill 里指 `skill-cli` —— SwiftUI 主 App 通过 `Process` 调它 |
| **Registry** | Skill 的索引/目录服务。Popskill v1 用 awesome-list 当 registry |
| **awesome-list** | GitHub 上的 curated list 仓库（如 `awesome-claude-skills`） |
| **WebDAV** | 跨设备同步用的协议。CC Switch 已经实现，复用即可 |
| **Transcript** | Claude Code 把对话记录在 `~/.claude/projects/<proj>/transcript.jsonl`，是 Insights 数据源 |
| **窗口归因** | Token 归因策略：某 skill 被调用后，下次切换前的 token 都算它 |

---

## 15. v0.2 战略储备：Package 能力包重构

> 重要边界：v0.1 **不做 Package 代码重构**。本节只作为 v0.2 战略储备，等 v0.1 发布后再启动实现。

### 15.1 原点校准

Popskill v0.1 的真实形态是 Claude Code Skill 管理器，这对首发是正确的；但 v0.2 的产品主轴应该从"管理技术组件"升级为"交付用户能力"。

用户不会说"我要装一个 CLI / MCP / Skill / Agent"，用户会说"我要让 AI 会用飞书"、"我要让 AI 会处理 PDF"、"我要让 AI 会运营小红书"。因此 v0.2 的一级目录不应该是 Skill / Agent / CLI / MCP，而应该是 **Package（能力包）**。

### 15.2 核心定义

一个 Package 是一个完整能力的商品单元。它可以包含多种组件：

- `cli`：命令行工具或本地 binary，例如 `lark-cli`、`gh`
- `mcp`：MCP server，例如 GitHub MCP、Notion MCP
- `skills`：Claude/Codex/Gemini 等按 trigger 加载的能力模块
- `agents`：角色化 subagent/persona，例如飞书办公助手、小红书运营专家
- `config_schema`：API key、token、workspace、权限等配置项
- `permissions`：Keychain、网络、文件系统、第三方平台授权边界
- `target_apps`：Claude、Codex、Cursor、OpenClaw、Kimi 等目标工具

当前独立 Skill 在 v0.2 中自动降级为"单组件 Package"，保证向后兼容。

### 15.3 Package Manifest 草案

```yaml
package:
  id: lark
  name: 飞书
  name_en: Feishu / Lark
  category: 办公协作
  vendor: ByteDance
  description: 让 AI 操作飞书文档、表格、日历、消息、任务、审批等办公协作能力。
  use_cases:
    - AI 自动整理会议纪要到飞书文档
    - AI 从飞书多维表格生成数据报表
    - AI 维护飞书知识库

components:
  cli:
    - id: lark-cli
      required: true
  mcp:
    - id: lark-openapi-mcp
      required: false
  skills:
    - id: lark-doc
      depends_on: [lark-cli]
    - id: lark-base
      depends_on: [lark-cli]
  agents:
    - id: lark-office-assistant
      uses: [lark-doc, lark-base]
  config_schema:
    - key: lark.app_id
      type: secret
      storage: keychain
      required: true

target_apps:
  - claude
  - codex
  - cursor
  - openclaw
  - kimi
```

### 15.4 UI 主轴

v0.2 的 sidebar 三段式：

- **能力包**：默认入口，面向普通用户，按能力分类浏览
- **我的能力包**：已安装、可更新、Hibernate/Stub 状态
- **组件库（高级）**：Skills、Agents、CLI Tools、MCP Servers，保留开发者直接管理组件的能力

能力包详情页应替代当前 Skill 详情页成为主商品页，展示用途场景、包含组件、必需配置、支持工具、权限边界和安装计划。组件视图仍然存在，但下沉为高级入口。

### 15.5 第一批内置能力包候选

v0.2.1 只内置少量高价值样板，避免范围爆炸：

| 优先级 | 能力包 | 组件构成 | 证明点 |
|---|---|---|---|
| P0 | 飞书 Lark | CLI + MCP + 24 Skills + Agents + Config | 高复杂度办公协作样板 |
| P0 | PDF | 3-5 Skills | 无 CLI 的低复杂度能力包 |
| P0 | GitHub | `gh` + MCP + Skills + Agents | 开发者最大公约数 |
| P0 | 会员运营 | 8 Skills + 2 Agents | majia 独家工作流 |
| P1 | Notion | MCP + Skills + Agent | 知识管理样板 |
| P1 | Spreadsheet | Sheets/Excel Skills + Agent | 办公自动化样板 |
| P1 | 图像生成全家桶 | baoyu image/comic/cover/xhs/infographic 系列 | 内容创作样板 |
| P2 | 微信生态 | 公众号/视频号/私域/直播 Skills + Agents | 中文圈差异化 |
| P2 | 观远 BI | `guancli` + Skills + Agent | 企业数据样板 |
| P2 | 马甲个人 IP 包 | majia 系列 Skills + Agents | 自用与个人 IP 样板 |

### 15.6 迁移路径

v0.2.0 先引入 Package 抽象层，但不立即推翻 v0.1 UI：

1. 所有 v0.1 Skill 自动包装为一对一 Package。
2. 根据命名规则和内置 manifest 做轻量归类，例如 `lark-*` 合并进飞书包。
3. 保留"组件库（高级）"入口，避免老用户升级后找不到原来的 Skill 管理路径。
4. Package 级 Insights 与 Hibernate 后续逐步替换 Skill 级推荐。
5. v0.2.2 再把默认入口从组件视图切到能力包视图。

### 15.7 Sidecar 协议演进

v0.1 命令全部保留：

```bash
skill-cli list
skill-cli install-plan <skill-key>
skill-cli install <skill-key>
```

v0.2 新增 Package 级命令：

```bash
skill-cli package-list
skill-cli package-detail <package-id>
skill-cli package-install-plan <package-id>
skill-cli package-install <package-id>
skill-cli package-config <package-id> --key <key> --value-env <env>
```

实现原则：

- 先做 `package-install-plan`，延续 v0.1 已验证的 read-only preview 模式。
- 所有 secret 只通过 env / Keychain，不能进入 argv、SQLite 明文字段或日志。
- Package 安装器必须能解释依赖图、缺失组件、冲突路径和回滚策略。
- AgentShield 从 Skill 级 gate 升级为 Package 级 component gate。

### 15.8 风险边界

- v0.1 不改主叙事、不改导航、不改数据模型，避免发布延期。
- v0.2 只做 4 个 P0 能力包，证明模型成立后再扩展。
- Popskill 不自己生产 Agent/Skill 内容，优先接 agency-agents、ECC、majia 私有技能仓等上游。
- Package 是用户心智抽象，不是把所有工具都塞进一个巨大安装器；组件库仍然保留直接管理能力。

---

## 附录 A：新电脑接手 checklist

在另一台 Mac 上从零开始：

```bash
# 1. 装工具链
xcode-select --install                  # Xcode CLI tools
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh   # Rust

# 2. 拉项目
mkdir -p ~/projects && cd ~/projects
git clone --recurse-submodules <YOUR_REPO_URL> popskill
cd popskill

# 3. 跑本地 CI（会编 Rust sidecar、Swift Package、跑 smoke）
./scripts/ci-local.sh

# 4. 单独验证 CLI（可选）
./skill-cli/target/debug/skill-cli list --json | jq

# 5. 启动 App
./scripts/run-app.sh

# 6. 需要 Xcode 调试时，打开 Swift Package
open swift-app/Package.swift

# 完事
```

## 附录 B：2026-05-13 现状校准

截至 2026-05-13，最初 Day 1-5 纵切已经完成，代码已推进到 Week 2-5 的主要功能：

- ✅ 调研 GitHub 生态（含 `iamzhihuix/skills-manage`、`yibie/skills-manager`、ECC / AgentShield）
- ✅ 刨 CC Switch 源码（B 阶段）
- ✅ 静态验证剥离可行性（A 阶段）
- ✅ 产品形态设计 V1（C 阶段）与 `STYLE.md`
- ✅ `cc-switch` 作为 git submodule 固定到 v3.14.1
- ✅ `skill-cli` sidecar 已覆盖 list/detail/toggle/discover/install-plan/install/update/uninstall/import/repo/backup/agent-list/agent-targets/agent-catalog/agent-install-plan/health
- ✅ SwiftUI Library / Agents / Discover / Updates / Backups / Insights / Settings 主页面可编译
- ✅ 行内 Claude/Codex/Gemini toggle、Stub / Rehydrate 与详情页多 app toggle 已接 sidecar
- ✅ 自定义 skill repository 管理、sidecar health、backup 管理已倒灌进计划
- ✅ AgentShield sidecar、Library 手动/持久化扫描、install-plan 安全预览、安装后 blocked 回滚、unmanaged import 前阻断已落地
- ✅ Agent 只读管理已启动：默认扫描 `~/.claude/agents/**/*.md`，解析 name/description/tools/model；AgencyAgents catalog 可只读发现；agent-install-plan 可预览写入路径/冲突/转换需求；SwiftUI Agents 页支持搜索、分类、详情和 Agent target 诊断
- ✅ WebDAV 状态、远端 snapshot 与 manual sync plan 只读入口已落地；upload/download 当前受 CC Switch Tauri State/private module 边界阻塞，先不绕实现
- ✅ `scripts/dev-build.sh`、`scripts/ci-local.sh`、read-only smoke、mutating smoke、bundle/release smoke、development DMG 打包、release manifest/appcast 已落地
- ✅ Stub 状态机已完成手动 hibernate/metadata/rehydrate，Idle Candidates 已按 60 天 inactive 生命周期 + transcript attribution 最近使用筛选，并支持单个/批量 stub
- 🔴 WebDAV 手动 sync、正式 notarize、Sparkle 公开更新实测尚未落地
- ✅ Sparkle SDK 正式 link 已落地：依赖固定为 Sparkle 2.9.1，App 二进制链接 `Sparkle.framework`，菜单入口、feed/key 配置守卫、framework copy hook、release doctor 检查已落地；SwiftPM 下载 Keychain 卡顿通过 `scripts/swiftpm.sh` 临时 HOME 构建 wrapper 固化规避
- 🟡 视觉 tokens 与主要页面容器已按 `STYLE.md` 落地；Discover/Library/Settings/Updates 截图级 polish 与 README 截图已完成，screenshot smoke 已校验尺寸/字节/基础像素方差，仍需最终全局一致性检查

下一个动作：v0.1 继续保持 Skill 中心化范围，优先做最终截图 QA、真实签名/公证与 Sparkle 公开 feed/key/signature 实测；Package 能力包重构等 v0.1 发布后进入 v0.2。
