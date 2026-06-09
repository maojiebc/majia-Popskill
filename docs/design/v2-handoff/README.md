# Handoff: Popskill — 本地 AI 能力管理器

## Overview

Popskill 是一个 macOS 桌面应用：在 `~/.agents/` 维护一份能力仓库（Skill / Agent / MCP / CLI / 套装，按类型分 `skills/ agents/ mcp/ bin/` 子目录），
通过 symlink 把每项能力挂载到多个 AI 工具（Claude Code `~/.claude/`、Codex CLI `~/.codex/`，可扩展到 N 个）。
选址 `~/.agents/skills/` 是有意为之：这是正在形成的跨工具约定目录，原生扫描它的工具（opencode 等）无需 symlink 直接可用。
核心场景：**技能装一次，挂到多个 AI 工具上；坏了能修，旧了能升。**

产品刻意做小：**一个主屏（卡片矩阵）+ 两个弹层（添加 / 设置）+ 一个空态**。没有侧栏、没有路由。
完整产品逻辑、数据模型与边界见同目录 `SPEC.md`（v2，为实现真源）；`SPEC-v1.md` 是被裁剪前的旧方案，仅供了解「为什么砍」。

## About the Design Files

本包内的 HTML/JSX 文件是**用 HTML 做的设计参考（可点击原型）**，不是可直接上线的生产代码。
你的任务是在目标技术栈中**重新实现**这套设计：

- 若项目已有代码环境（Electron/React、Tauri、SwiftUI…），用其既有模式与组件库重建；
- 若从零开始，自行选择最合适的桌面框架（建议 Tauri + React 或 Electron + React，需真实文件系统 / symlink 能力）。

原型中的 React 写法（全局 window 导出、Babel standalone、内联样式）是原型工具的产物，**不要照搬**；
但其中的状态模型、选择器逻辑（`popskill-data.jsx`）和交互流程可直接翻译。

打开 `prototype.html`（需联网加载 React CDN）即可体验全部交互。

## Fidelity

**High-fidelity（高保真）**。颜色、字号、间距、圆角、状态符号、文案均为最终意图，请按像素级还原。
唯一例外：`tweaks-panel.jsx` 与右下角 Tweaks 面板是**原型演示工具**（切空态/展开套装），不属于产品，不要实现。

## Design Tokens

### 颜色（账本风格：米白纸面 + 发丝线 + 单一电光蓝）
| Token | 值 | 用途 |
|---|---|---|
| bg/window | `#fafaf8` | 窗口与主区背景 |
| bg/chrome | `#f4f2ec` | 标题栏、状态栏、弹层头尾、悬停态 |
| bg/bundle-head | `#f4f1e8` | 套装卡头部 |
| bg/bundle-body | `#fcfbf6` | 套装卡子项区 |
| bg/card | `#fff` | 独立能力卡、设置行 |
| border/hairline | `#e8e6df` | 主要发丝线 |
| border/hairline-2 | `#efede5` | 卡内分隔 |
| border/control | `#dcd9cf` / `#d8d5cb` | 输入框、次级按钮 |
| ink | `#111` | 主文字、主按钮底、Bundle tag |
| text/secondary | `#7c7869` · `#6f6b5e` | 描述、副标题 |
| text/tertiary | `#9a9684` | 元信息、占位符、列头 |
| accent/blue | `#1f4ed8` | on 状态、链接、聚焦、开关 on |
| status/amber | `#b88300`（文字 `#8a6400`，徽标底 `#f6ecc8` 边 `#e0cb84`） | stub、可更新 |
| status/red | `#c01818` | broken、危险操作悬停 |
| status/green | `#1a9a4e`（同步点）· `#1a6b35`（推荐方案文字，底 `#f3f8f4` 边 `#bcd8c2`） | 同步、推荐 |
| off/gray | `#cdc8b9`（符号）· `#c4bfb0`（暗点） | off 状态 |
| desktop | `#d9d7d0` | 窗外桌面（原型外壳，应用本身不需要） |
| terminal | 底 `#16140f` 文字 `#c9c4b2` | 「将写入」预览块 |

### 字体
- UI：`Inter`，回退 `-apple-system, "Helvetica Neue", "PingFang SC", sans-serif`
- 等宽（路径/URL/版本徽标/状态符号/终端块）：`ui-monospace, SFMono-Regular, Menlo, monospace`（原型加载了 JetBrains Mono 但实际以 ui-monospace 为准）

### 字号阶梯（px）
25(主标题 h1, 700) · 15.5(弹层标题) · 14/13.5(卡名) · 12.5(正文/按钮) · 11.5(描述/次级) · 11(元信息) · 10.5(辅助说明) · 10(更新徽标/列头) · 9.5(类型 tag) · 9(子项列头/聚合标签)。
标题负字距 `-0.02em ~ -0.025em`；全大写小标签 `letter-spacing: 0.06em`。数字一律 `font-variant-numeric: tabular-nums`。

### 圆角 / 阴影 / 尺寸
- 圆角：窗口 10 · 卡片/弹层 10-12 · 按钮/输入 7 · tag 3-4 · pill/开关 999
- 卡片阴影 `0 1px 2px rgba(0,0,0,0.03)`；弹层 `0 24px 64px rgba(0,0,0,0.30)`；修复弹层 `0 12px 36px rgba(0,0,0,0.18)`
- 窗口设计尺寸 1280×820（原型用 transform scale 适配视口；真实应用为可调窗口，最小建议 1080×720）
- 标题栏高 38 · 状态栏高 26 · 按钮高 30 · 开关 30×17

### LinkStatus 视觉词汇（贯穿全应用）
| 状态 | 符号 | 颜色 | pill 底/边 |
|---|---|---|---|
| on | ● | `#1f4ed8` | `rgba(31,78,216,0.06)` / `#aabde8` |
| off | ○（卡片 pill）/ —（子项单元格） | `#9a9684` / `#cdc8b9` | transparent / `#dcd9cf` |
| stub | ◐ | `#b88300` | `rgba(184,131,0,0.05)` / `#dcc27a` |
| broken | ✕ | `#c01818` | `rgba(192,24,24,0.04)` / `#e0a3a3` |

类型 tag（全大写、描边式、minWidth 50）：Skill `#5a4a14/#c9b478` · Agent `#1d3c63/#7faacd` · MCP `#3c1d5a/#a98cc9` · CLI `#1a4d33/#74b291` · Bundle 反白 `#111` 底。

## Screens / Views

### 1. 主屏：能力矩阵（`popskill-main.jsx`）

自上而下：**标题栏 → hero → 健康横幅（条件出现）→ 类型 chip 行 → 卡片网格（滚动）→ 状态栏**。

- **标题栏**：红黄绿窗钮 · 品牌 mark+「Popskill」· 右侧同步 chip（绿点「已同步」/ 空态灰点「未连接」）· ⚙ 按钮（开设置）。
- **hero**：h1「能力矩阵」+ 副标题计数（`3 套装 · 15 独立能力 · Claude 31 / Codex 22 已激活`，实时派生）；右侧搜索框（宽 220，快捷键 `/`，聚焦蓝描边 + `0 0 0 3px rgba(31,78,216,0.12)` 光环，有值时显 × 清除）+ 黑底「+ 添加」按钮。
- **健康横幅**（有 broken 或可更新时出现，底 `#faf5e6` 边 `#efe3c8`）：`✕ N 个链接问题 · ↑ M 个源可更新` + 灰字提示 + 右侧「全部修复 (N)」（黑底）「全部更新 (M)」（琥珀描边）。归零即整条消失。
- **类型 chip 行**：全部 / Skill / Agent / MCP / CLI / Bundle（单选，选中黑底反白）；右端过滤中显示「N 项匹配」（蓝），否则「排序：类型 ↓」。
- **卡片网格**：`grid-template-columns: 1fr 1fr; gap: 10px; padding: 16px 28px 28px`。

**独立能力卡**（双列）：左 38×38 中性单字头像（底 `#f4f2ec`）；中间名称 + 类型 tag + 描述 + 元信息行（`v1.8.0` · 可更新徽标 · 作者 · `92.1k tokens` · `↗ sourceUrl` 等宽截断 180px）；右列两枚工具 pill（Claude / Codex），每枚 = 状态符号 + 工具名 + 状态文案（已激活/未链接/占位/断链）。悬停卡片浮现 ↗（编辑器打开）与 ✕（移除，悬停变红）。

**套装卡**（通栏 `grid-column: 1 / -1`）：
- 头部（底 `#f4f1e8`，点击折叠/展开）：▼/▶ + 名称 + Bundle tag + `8 项` + 描述 + `· ↗ sourceUrl`；右侧 CLAUDE/CODEX 两个聚合块（小标签 + 分数 `5/8` + 36×3 迷你覆盖条：蓝 on/琥珀 stub/红 broken/灰 off 按比例分段）+ `v1.2.0` + 可更新徽标 + 悬停 ↗/✕。
- 子项清单：列头（CLAUDE / CODEX / 版本，9px 全大写）+ 每行：树形 `├─`/`└─` + 名称 + 类型 tag + 描述（截断）+ 两列状态符号（28×24 命中区，悬停淡灰底）+ 版本 + 悬停 ↗。

**搜索行为**：按名称/描述/作者过滤，命中黄底高亮（`#fde68a`）；命中子项时自动展开所属套装；类型过滤非「全部」时子项摊平为独立卡并标注 `⊂ 所属套装`；无结果显示空提示。

- **状态栏**：`~/.agents` + 蓝链接「↗ 在编辑器中打开」 · `53 symlinks`（实时）· `2 断链`（>0 红色加粗）`/ 6 占位` · 右侧「同步于 2 分钟前」+ `popskill v0.10.0`。空态变体：`store 为空`、「未连接同步」。

### 2. 行内修复弹层（点击 ✕/◐ 单元格或 pill）

320px 宽小浮层，锚定被点元素水平居中（夹紧在窗内 12px 边距），默认朝下展开，点击点 y>520 时向上翻转。结构：
- 头部（底 `#fafaf8`）：成因标题（`✕ 断链 — pm-spec-writer · Codex CLI`，✕ 红 / ◐ 琥珀）+ 来源行（等宽 URL + 有新版时 `↑ x.y.z` 琥珀加粗）。
- 方案列表（2-3 项，每项 = 标题 + 一行说明，悬停淡灰底）。**推荐项**：绿字 + 绿边淡绿底 + 「推荐」小徽标。方案矩阵：
  - 有新版 → `更新到 x.y.z 并修复`（推荐）置顶
  - 断链 → 重链到 store 本地版本（无新版时推荐）/ 从源重新拉取 / 移除该侧链接
  - 校验失败 → 从源重新拉取并校验（无新版时推荐）/ 跳过校验启用（降级）/ 移除该侧链接
  - 占位(stub) → 完成校验并启用（推荐）/ 移除该侧占位
- 点方案立即执行：更新方案走源级更新；其余把该单元格置 on/off。点遮罩或 Esc 关闭。每次执行弹 toast。

### 3. 添加弹层（「+ 添加」/ 空态 CTA / 设置内入口）

520px 居中模卡（遮罩 `rgba(24,20,12,0.34)`，点遮罩/Esc/取消关闭）。两步：
1. **粘贴 URL**：等宽输入框（placeholder `github.com/owner/repo · npm:pkg · ~/path`）+ 三枚示例 chip 一键填入 + 底栏「取消 / 解析 →」（空值禁用，Enter 也可触发）。
2. **安装计划**：来源行（kind tag：github/npm/local 由 URL 形态推断 + URL + 版本）→「提供 N 项」清单（名称 + 类型 tag + tokens）→「挂载到」每个工具一行（名称 + 目标路径 + 开关，默认值 = Tool.defaultTarget）→「将写入」终端预览块（store 路径 + 每个选中工具一条 `ln -s` 命令，随开关实时变化）→ 底栏「← 返回 / 取消 / 安装并链接 (N)」（N=0 时文案变「仅保存到 store」）。

完成后：新条目**置顶**进入网格，蓝边淡蓝底高亮 1.8s 后淡出；toast `已安装 x 并链接到 N 个工具`。
原型的 URL 解析是假数据（任意 URL → 单个 Skill）；真实实现读取源 manifest，可能多项（计划清单 UI 已支持多行）。

### 4. 设置弹层（⚙）

560px 居中模卡，内部滚动（maxHeight 680），右上 `esc` 钮。四个分区（小标签全大写分隔）：
1. **已添加的源（N）**：每条 = kind tag + 等宽 URL（截断）+ 第二行「提供 xxx 等 N 项 · vX.Y.Z」+ 可更新徽标（点击即更新）+ 自动更新开关 + ✕ 移除；底部「+ 粘贴 URL 添加」（切到添加弹层）+ 说明文字。
2. **工具（挂载目标）**：连接状态点（绿/灰）+ 名称 + 根目录 + 「新安装默认挂载」开关；「+ 添加工具…」。
3. **Store 与同步**：路径 + 「↗ 在编辑器中打开」；同步后端行（`iCloud Drive · 已同步` 绿字）+ 说明「store 在设备间同步；symlink 是各机本地状态」。
4. **关于**：`popskill v0.10.0 · store 482 MB · MIT`。

### 5. 空 store 态（entries 为空时主屏自动切换）

垂直居中：等宽 `~/.agents — 空` → 「还没有任何能力」(18px, 700) → 两行说明 → 「+ 粘贴 URL 添加」（黑底，开添加弹层）+「扫描本地目录」（描边）。标题栏同步 chip 变「未连接」，状态栏变空态文案。

## Interactions & Behavior

- **pill / 单元格点击**：on ↔ off 直接切换（toast 反馈「已链接/已断开 x → 工具」）；stub/broken 打开修复弹层。
- **更新徽标 `↑ x.y.z`**（套装头/卡片元信息/设置源列表）：点击一步更新 = version←latest、徽标消失、该源下所有 broken→on、toast。
- **全部修复**：对每个问题执行其推荐方案（有新版→更新并修复，否则重链本地）。**全部更新**：对所有可更新源执行更新。
- **移除**：顶层条目悬停 ✕ 或设置内 ✕ → 移除条目（套装连子项）+ toast「store 副本与全部 symlink 已清理」。真实实现建议加确认。
- **↗ 在编辑器中打开**：调用系统打开 store 内对应目录（原型仅 toast）。这是「编辑能力」的唯一入口——应用内不做编辑器。
- **toast**：底部居中黑底白字，2.6s 自动消失，同时只显示一条（新的顶掉旧的）。
- **键盘**：`/` 聚焦搜索；`Esc` 关闭弹层/浮层。
- **悬停**：卡片操作钮默认隐藏悬停浮现；危险操作悬停变红；推荐外方案/子项行悬停 `#f4f2ec` 底。
- 动画克制：开关 knob 0.15s、新装条目高亮 1.2s 淡出；无其他装饰动画。

## State Management

单一应用级 state（原型在 `popskill-app.jsx`，可直译为 store/reducer）：

```
state = {
  tools:   [{ id, name, root, connected, defaultTarget }],
  entries: [Entry]   // 唯一顶层集合；Bundle 带 children
}
派生（不存储）：stats（计数/激活数/symlink 数）、issues（每个 broken 单元格一条）、updates（latest>version 的源）
UI 态：sheet(null|add|settings) · toast · flashId(新装高亮) · query · typeFilter · expanded(Set) · 修复弹层锚点
```

动作清单（全部在原型中有实现可对照）：`toggleLink(capId, tool)` · `resolveCell(capId, tool, on|off)` ·
`applyUpdate(entryId)` · `updateAll()` · `fixAll()` · `install(plan, targets)` · `removeEntry(entryId)` ·
`toggleAutoUpdate(entryId)` · `toggleDefaultTarget(toolId)`。

真实数据来源：文件系统扫描 + `readlink` 解析（见 SPEC.md §8 关键逻辑）；样例数据在 `popskill-data.jsx`（3 套装 + 15 独立能力，覆盖全部状态组合，可直接做开发期 fixture）。

## Assets

无图片/图标资产。品牌 mark 是 18×18 内联 SVG（黑圆角方 + 两圆一线，见 `popskill-ui.jsx` 的 `PsMark`）；
其余符号均为文本字符（● ○ ◐ ✕ ▼ ▶ ├─ └─ ↗ ↑ ⚙），用等宽字体渲染。

## Files

| 文件 | 内容 |
|---|---|
| `prototype.html` | 入口，打开即可体验（需联网） |
| `popskill-data.jsx` | 数据模型 + 选择器（stats/issues/updates）— 逻辑可直接翻译 |
| `popskill-ui.jsx` | 设计 token 落地 + 标题栏/状态栏/tag/单元格/toast |
| `popskill-main.jsx` | 主屏：卡片矩阵 + 健康横幅 + 修复弹层 + 空态 |
| `popskill-sheets.jsx` | 添加弹层 + 设置弹层 + 开关组件 |
| `popskill-app.jsx` | 状态容器 + 全部动作 + 缩放外壳 |
| `tweaks-panel.jsx` | ⚠️ 原型演示工具（空态/展开开关），**不要实现** |
| `SPEC.md` | 产品规格 v2（数据模型/逻辑/边界/待定项）— 实现真源 |
| `SPEC-v1.md` | 旧版 10 屏方案留底，仅说明裁剪来由 |
| `screenshots/` | 6 张关键状态截图（主屏 / 行内修复弹层 / 添加两步 / 设置 / 空 store 态），供快速比对还原效果 |
