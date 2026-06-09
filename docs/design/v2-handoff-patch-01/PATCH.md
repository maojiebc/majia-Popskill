# PATCH 01 — 能力详情 peek

> 基于已交付的 `design_handoff_popskill` 包（~/.agents 路径版）的增量补丁。
> 只改 2 个实现文件 + SPEC；其余文件与上一包一致，无需重新对照。

## 变更动机

矩阵里每项能力只有一行描述，回答不了「这个 skill 大概是干什么的」。
方案：**行内详情 peek**，不做整页详情 —— 点击能力名称弹小浮层，看完即走；
深读场景仍交给「在编辑器中打开」（完整文档在 SKILL.md）。

## 变更清单

| 文件 | 变更 |
|---|---|
| `popskill-data.jsx` | ① 新增 `psReadmes` 映射（capId → SKILL.md/README 开头摘要，静态样例）与选择器 `psReadme(id)`；② export 增加 `psReadme` |
| `popskill-main.jsx` | ① 新增 `PsDetailPeek` 组件；② `PsMain` 增加 `peek` 状态、`onNameClick`、坐标换算抽出 `toDesign()`；③ 能力名称（独立卡 + 套装子项）变为可点击，悬停下划线 + `title="查看详情"`；④ Esc/遮罩关闭，与修复弹层互斥（开一个关另一个） |
| `SPEC.md` | §2.2 增加 `readme` 字段；§4.1 上方新增「详情 peek」条目；§10 新增摘要提取策略（待定项 6） |

## 数据模型增量

Capability 新增字段：

```
readme?: string   // SKILL.md / README 开头摘要
```

**提取策略（真实实现，见 SPEC §10.6）**：安装/更新时提取并缓存到 store 元数据，不要在打开 peek 时实时读文件。
- Skill / Agent / MCP：SKILL.md frontmatter 的 `description` + 正文首段，截 ~120 字
- CLI（无 SKILL.md）：README 首段或 `--help` 首行，前缀「二进制 CLI，无 SKILL.md。」

## PsDetailPeek 规格

- **触发**：点击能力名称（独立卡名称 / 套装子项名称）。悬停时名称显示下划线（`text-underline-offset: 3px`）提示可点。
- **尺寸/定位**：宽 380px；锚定点击位置水平居中，窗内夹紧（左右 12px 边距）；点击点 y > 430（设计空间 1280×820）时向上翻转。白底、圆角 9、边 `#dcd9cf`、阴影 `0 12px 36px rgba(0,0,0,0.18)`。
- **结构**（三段，分隔线 `#efede5`）：
  1. **头部**（底 `#fafaf8`）：名称(13.5/700) + 类型 tag + 右侧 `esc` 钮；副行(11/`#9a9684`)：`v{version} · {author} · {tokens}k tokens`，套装子项追加 `· ⊂ {bundle名}`（等宽）。
  2. **主体**：完整描述(12/`#444`/1.55)；「SKILL.MD · 文档摘要」小标签(9.5 全大写 `#b3ae9e`) + 引文块（底 `#fcfbf6` 边 `#efede5` 圆角 6，11.5/`#5e5a4e`/1.6，内容 = `readme`，无 readme 则整段隐藏）；两侧链接状态一行（`● Claude 已激活`，状态色 on 蓝/off 灰/stub 琥珀/broken 红，broken 显示 brokenCause）；来源 URL（等宽 10.5 截断）。
  3. **底部**（底 `#fafaf8`）：描边按钮「↗ 在编辑器中打开」（点击后关闭 peek 并打开 store 内对应目录）+ 右侧灰字「完整文档在 SKILL.md」。
- **关闭**：Esc / 点击遮罩 / 点编辑器按钮。与修复弹层互斥：打开任一方时关闭另一方。
- **不做**：peek 内不放挂载开关（矩阵单元格已承担）、不做编辑、不做整页路由。

## 验收清单

- [ ] 独立能力卡点名称 → peek 出现在名称下方；底部两排卡片点开时向上翻转、不被窗口裁剪
- [ ] 套装子项点名称 → peek 显示 `⊂ 所属套装`，来源 URL 为套装的 sourceUrl
- [ ] CLI 类（gh / ripgrep / lark-cli）摘要以「二进制 CLI，无 SKILL.md。」开头
- [ ] broken 项（pm-spec-writer / design-review）链接状态行显示红 ✕ + 成因文案
- [ ] Esc、点遮罩、点「在编辑器中打开」均关闭；peek 与修复弹层不会同时存在
- [ ] 名称悬停有下划线提示；点击名称不触发卡片/套装头的其他行为（stopPropagation）

## 截图

`screenshots/01-详情peek-套装子项.png`（doc-skill ⊂ feishu-suite）
`screenshots/02-详情peek-独立能力.png`（op7418-design-review，底部卡片向上翻转 + broken 状态展示）
