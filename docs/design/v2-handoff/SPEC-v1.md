# Popskill — 功能与逻辑规格（开发交接）

> 面向 Claude Code 的实现说明。**可点击原型 = `prototype.html`** 为交互真源；
> `index.html` 是并排设计画布（探索用，非产品）。本文件描述产品逻辑、数据模型、
> 各屏行为与边界，供直接落地为真实应用。

---

## 1. 产品是什么

Popskill 是一个**本地 AI 能力管理器**。它在 `~/.popskill/store/` 维护一份**能力仓库（store）**，
通过 **symlink** 把每一项能力同时挂载到多个 AI 工具（Claude Code `~/.claude/`、Codex CLI `~/.codex/`，
以及任意支持文件系统 skill 的 CLI）。

核心价值：**一处管理，多端挂载**。安装一次写进 store，再决定链接到哪几个工具；
升级、修复、卸载都针对 store 与 symlink，而非各工具各自维护一份拷贝。

---

## 2. 数据模型

### 2.1 Capability（能力）
| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 唯一标识 |
| `name` | string | 展示名（同时是 symlink 名） |
| `type` | enum | `Skill` / `Agent` / `MCP` / `CLI` |
| `desc` | string | 一句话描述 |
| `version` | semver | 当前安装版本 |
| `author` | string | 作者 / 组织 |
| `sourceUrl` | string | **来源 URL**（见 §2.3 AddedSource），如 `github.com/owner/repo`、`npm:pkg`、`~/path` |
| `tokens` | number | 该能力的提示词体量（CLI 为 0） |
| `calls` | number | 累计调用次数（本地统计） |
| `claude` | LinkStatus | 在 Claude 侧的链接状态（见 §2.4） |
| `codex` | LinkStatus | 在 Codex 侧的链接状态 |

> 工具维度（claude/codex）是**示例**。实际应支持 N 个工具（见 §2.2 Tool），
> 每个能力对每个已连接工具各有一个 LinkStatus。原型为简化只画了两列。

### 2.2 Tool（工具）— 安装目标
| 字段 | 说明 |
|---|---|
| `id` | `claude` / `codex` / 自定义 |
| `name` | Claude Code / Codex CLI / … |
| `root` | 安装根目录，如 `~/.claude/`，symlink 写到其下 `skills/` `agents/` `mcp/` `bin/` |
| `connected` | bool |
| `defaultTarget` | bool — 新安装是否默认链接到它 |

### 2.3 Source — 两个层次（**务必区分**）
这是最容易混淆的地方，分两层：

**(a) Registry / 注册表连接** — *去哪儿发现*新能力的入口。
| 字段 | 说明 |
|---|---|
| `kind` | `github` / `clawhub` / `npm` / `local` |
| `endpoint` | `api.github.com`、`https://clawhub.dev/registry`、`https://registry.npmjs.org`、本地监视目录列表 |
| `auth` | 令牌 / 公开 / 无 |
| `enabled` | bool — 关闭后从「获取中心」的浏览 tab 与更新检查中移除 |
| `scope` | 可选：关注的 org / scope / 监视的本地目录 |

**(b) AddedSource / 已添加的源** — *你实际拉过的每一个 URL*。
| 字段 | 说明 |
|---|---|
| `url` | `github.com/feishu/lark-suite`、`npm:@guandata/bi-suite`、`~/work/my-skills/` |
| `kind` | github / npm / git / local |
| `provides` | 它提供的 Capability / Bundle（1 个或多个） |
| `installedVersion` | 当前版本 |
| `latestVersion` | 上游最新版本（更新检查写入；无更新则等于 installed） |
| `autoUpdate` | bool |
| `status` | `ok` / `update-available` / `source-removed`(上游 404) / `auth-error` |

> 关系：Registry 是"在哪个平台、用什么凭证搜"；AddedSource 是"我具体加了哪些 URL"。
> 一个 GitHub registry 连接下可以有 N 个 AddedSource（N 个 repo URL）。
> 每个已安装 Capability 通过 `sourceUrl` 指回它的 AddedSource。

### 2.4 LinkStatus（某能力在某工具侧的状态）
| 值 | 含义 | 视觉 |
|---|---|---|
| `on` | symlink 存在且目标有效 | 蓝实心 ● |
| `off` | 未链接到该工具 | 灰 — |
| `stub` | 占位（目标存在但未就绪 / 待校验） | 琥珀 ◐ |
| `broken` | symlink 存在但目标丢失 / 校验失败 | 红 ✕ |

### 2.5 Bundle（套装）
一个上游入口维护的**一组能力**（CLI + 多个 Skill + 可选 MCP/Agent）。
| 字段 | 说明 |
|---|---|
| `id`/`name`/`version`/`author`/`source` | 同上 |
| `children` | Capability[] — 子项 |
| 聚合状态 | 由子项 LinkStatus 汇总：全 on → `on`；全非 on → `off`；混合 → `partial`（在矩阵里以分数 `5/8` + 迷你覆盖条展示） |

> **「Bundle」是 Capability 的一种 type，不是独立概念。** 矩阵里的 `Bundle` 类型筛选 = 只看套装。
> 不需要在侧栏再单列「套装」入口（已移除，见 §6）。

---

## 3. 信息架构 / 导航

侧栏只放**目的地**（每项对应一个路由），不放筛选器、不放状态指示。

| 侧栏项 | route | 屏幕 |
|---|---|---|
| 视图 › 矩阵 | `matrix` | 能力矩阵（主视图） |
| 视图 › 修复中心 | `fix` | 健康 / 修复（断链等） |
| 获取 › 源 / 更新 | `sources` | 获取 / 更新中心 |
| 创建 › 新建能力 | `create` | 单个能力编辑器 |
| 创建 › 组装套装 | `compose` | 把已有能力打包成套装 |
| 系统 › 设置 | `settings` | 设置（含源 / 注册表管理） |

**全局覆盖层（非路由）**
- `⌘K` 命令面板（Spotlight）：跨能力 / 套装 / 动作 / 设置的搜索，↑↓ 选择、↵ 跳转、esc 关闭。
- 安装计划弹层（install sheet）：从某来源安装套装时的执行计划确认（原型 `v10`，画布展示；真实里由「+添加 / 安装」触发）。

**标题栏**：品牌 → matrix；⌘K → 命令面板；⚙ → settings。
**状态栏**（窗口底部）：store 路径 · symlink 总数 · 断链/占位计数 · 同步状态 · 版本。
（同步状态是**指示器**，固定在状态栏，不进侧栏。）

---

## 4. 各屏功能与交互

### 4.1 矩阵 `matrix`（主视图）
- 一张密集表：每行一个能力；列 = 名称 / 类型 / 作者 / Claude / Codex / 版本 / Tokens / 调用。
- **套装行可展开/折叠**（▼/▶），子项树形缩进；套装行的 Claude/Codex 列显示聚合分数 `5/8` + 覆盖条。
- **搜索框**（标题区右上，快捷键 `/`）：按 名称/描述/作者 实时过滤，命中高亮；空结果有空状态。
- **类型筛选 chip 行**：全部 / Skill / Agent / MCP / CLI / Bundle。**类型筛选只在这里**，不进侧栏。
- **+ 添加** → 跳 `sources`。
- 统计条：能力总数 / Claude 已激活 / Codex 已激活 / 占位 / 断链 / 本月 Tokens。
- 待办（建议实现）：把「仅 Claude / 仅 Codex / 双侧 / 仅断链」做成此处的**第二排筛选 chip**（即原侧栏「仅 Claude」的真实归宿，见 §6）。

### 4.2 修复中心 `fix`
处理所有**健康问题**，左列表 + 右详情。每个问题**关联其来源 URL**。
- **成因分类**（`cause`）：
  - `断链` — symlink 目标在 store 中丢失。
  - `源失联` — 上游仓库已删除该项（如套装新版移除了某子项）。
  - `校验失败` — 目标文件存在但 manifest / 签名校验不过。
- 详情含：来源行（来源标记 + URL + 「在「源」中管理 →」跳 settings + 有更新则标 `↑ x.y.z`）、symlink 链路 diff、诊断日志。
- **修复方案对接源 / 更新**（每问题 2–3 个，推荐项标绿）：
  - 有新版 → 推荐 **「更新到 x.y.z 并修复」**（一步升级 + 重链，引用真实 sourceUrl）。
  - 源失联 → 「更新套装移除该子项」/「保留为本地分叉(detach)」/「彻底移除」。
  - 校验失败 → 「从源重新拉取并校验(repull)」/「跳过校验启用(trust，降级)」/「移除」。
  - 断链(无更新) → 「重链到本地旧版本」/「从源重新拉取」/「移除该侧链接」。
- 交互：点列表切换；「应用」把该项标为已修复（成功态）；右上 **「全部自动修复 (N)」** 对每项执行其推荐方案。
- 计数与状态栏随已修复实时归零。

### 4.3 获取 / 更新中心 `sources`
- **来源 tab**：GitHub(★stars) / ClawHub(↓) / npm(↓) / 本地。切 tab 换浏览列表。tab 列表来自**已启用的 Registry**（§2.3a）。
- **可更新区**：列出 `latestVersion > installedVersion` 的 AddedSource，每行 `当前 → 最新` + 「更新」；右上「全部更新 (N)」。
- **浏览区**：当前来源里**未安装**的可装项，带版本 / 热度 + 「安装」。
- 顶部「↗ 粘贴 URL / npm 包 / 本地路径」直接添加 → 新增一条 AddedSource，触发安装计划弹层。
- 工具栏「⚙ 管理源」→ settings 的源管理。

### 4.4 设置 `settings` — 含源管理
分区：连接 / 同步 / **源** / 安装 / 配额 / 关于。源分区两块：
- **注册表连接**（§2.3a）：4 类入口，各有端点 / 认证 / 启用开关 / 编辑；+ 添加注册连接。
- **已添加的源**（§2.3b）：每个 URL 一行 → 提供什么 · 版本 · 可更新标记 · **自动更新开关** · 移除；+ 粘贴 URL 添加。
- 其他分区：工具连接（每个 Tool 的根目录 + 默认目标）、Store 与同步（路径 / 后端 / 自动同步 / 冲突策略）、安装默认（默认链接目标 / 签名校验级别 / 自动更新策略）、Token 配额、关于。

### 4.5 新建能力 `create`
单个能力的编辑器。左：元数据（名称含可用性校验 / 描述 / 作者 / 版本）+ 正文 Markdown 编辑器（`SKILL.md`/`AGENT.md`…，frontmatter 语法着色）。右：矩阵行实时预览 + 安装目标开关（Claude/Codex）+ 「将写入」终端预览（store 路径 + symlink 命令）。
- 类型切换（Skill/Agent/MCP/CLI）联动预览标签、文件名、终端命令、写入目录。
- 主按钮：`创建并链接 (N)` / 无目标时 `仅保存到 store`。

### 4.6 组装套装 `compose`
从已有能力勾选若干 → 打包成 Bundle。左：候选能力列表（可搜、可勾）。右：套装信息（名称/版本/上游目标）+ 覆盖统计（N 项 · Claude X/N · Codex Y/N）+ 套装内容（可移除）+ 实时生成的 `popskill.toml`。主按钮 `发布套装 (N)`。

### 4.7 命令面板 `⌘K`（覆盖层）
真实搜索 + 分组（套装 / 各类型 / 快捷动作 / 设置）+ 命中高亮 + 结果计数 + ↑↓/↵ 键盘。空查询展示最近 / 建议 / 动作 / 设置。动作可直达各路由。

### 4.8 批量操作（矩阵的一个模式）
多选行（点行切换；点套装连同子项一起选；表头复选框全选；半选态）。底部浮动操作条：启用到 Claude / 启用到 Codex / 升级 / 导出 / 卸载 / 取消。计数区分"顶层条目数"与"含能力数"。
> 原型作为独立屏 `bulk` 演示；落地应是矩阵的多选态，不是单独页面。

### 4.9 首次启动 / 空状态
store 为空时：扫描结果条（0）+ 三条起步路径（粘贴 URL / 精选套装 / 扫描本地）。标题栏「未连接」、状态栏「store 为空」、侧栏置灰 0 值。各 CTA → `sources`，跳过 → `matrix`。

---

## 5. 关键逻辑

1. **链接解析**：`readlink ~/.<tool>/<kind>/<name>` → 解析到 `store/<kind>/<name>-<version>/`；
   目标不存在 = `broken`；存在但校验失败 = `broken`(校验失败成因)；未链接 = `off`。
2. **安装**：fetch 到 store（校验签名）→ 对选中的每个 Tool 建 symlink。套装 = 对每个子项重复，按勾选的目标。
3. **更新检查**：对每个 AddedSource 比对上游版本，写 `latestVersion`；`>` 即"可更新"。
   更新 = 拉新版到 store → 重指 symlink（保留各工具的链接关系）。
4. **修复**：见 §4.2，方案均落到 relink / repull / update / detach / unlink / remove 之一。
5. **同步**：store 通过 iCloud Drive / Git / 本地 在设备间同步；symlink 是各机本地态，不同步。

---

## 6. 本轮裁剪（及理由）— 相对早期原型

| 移除项 | 理由 |
|---|---|
| **图谱（双总线接线图）** | 展示性强但操作性弱；它表达的"对称性/缺口"用矩阵的列 + 筛选即可覆盖。已删除路由与文件。 |
| 侧栏「套装」 | 与矩阵的 `Bundle` 类型筛选完全重复。类型筛选统一在矩阵 chip 行。 |
| 侧栏「仅 Claude / 仅 Codex」 | 原为非功能性"快捷视图"。应作为**矩阵的筛选 chip**实现（§4.1 待办），不占侧栏目的地。 |
| 侧栏「iCloud Drive」 | 是状态指示器，不是目的地。固定在状态栏。 |

裁剪后侧栏 = 6 个真实目的地（§3），所有屏共用同一 `LedgerSidebar` 组件（首次启动用 `empty` 置灰态）。

---

## 7. 待定 / 假设（需产品确认）

1. **多工具**：原型只画 Claude/Codex 两列；真实需支持任意数量 Tool（列动态）。每工具一个 LinkStatus。
2. **"仅 Claude/Codex/双侧/断链" 筛选**：建议落在矩阵第二排 chip，未在原型实现。
3. **安装计划弹层**：原型中 `v10` 为画布展示；真实由 sources/+添加 触发，需接入路由。
4. **签名/信任模型**：`trust`（跳过校验）是降级操作，需确认是否保留及风险提示。
5. **本地源监视**：本地目录的"收录"是手动还是 watch 自动，需确认。
6. **数据**：原型用 `data.jsx` 内的样例数据（3 套装 + 17 独立能力 + 派生统计）；真实接 CLI / 文件系统。

---

## 8. 屏幕 ↔ 文件对照（原型）

| 屏幕 | 文件 | 导出 |
|---|---|---|
| 共享 chrome（标题栏/侧栏/状态栏/导航） | `v1-ledger.jsx` | `LedgerTitlebar` `LedgerSidebar` `LedgerStatusbar` `goNav` |
| 矩阵 | `v1-ledger.jsx` | `LedgerVariation` |
| 修复中心 | `v8-broken.jsx` | `FixVariation` |
| 获取/更新中心 | `v15-sources.jsx` | `SourcesVariation` |
| 设置（含源管理） | `v12-settings.jsx` | `SettingsVariation` |
| 新建能力 | `v13-create.jsx` | `CreateVariation` |
| 组装套装 | `v14-bundle.jsx` | `CreateBundleVariation` |
| 命令面板 | `v6-palette.jsx` | `PaletteLive` |
| 批量操作（矩阵模式演示） | `v11-bulk.jsx` | `BulkVariation` |
| 首次启动 | `v7-empty.jsx` | `EmptyVariation` |
| 安装计划弹层（画布展示） | `v10-install.jsx` | `InstallVariation` |
| 路由 / 缩放外壳 | `app.jsx` | `PopskillPrototype` |
| 共享样例数据 | `data.jsx` | `CAPS` `BUNDLES` `ROWS` `ALL_CAPS` `STATS` … |

> 已移除：`v9-graph.jsx`（图谱）。`v2/v3/v4/v5` 是早期视觉方向探索（卡片/编辑/终端/Inspector），
> 仅存于 `index.html` 画布，**不属于产品**。
