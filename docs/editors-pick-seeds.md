# Editor's Pick Seed List

> v0.1 发布时 Discover 页 "Featured / Editor's Pick" 模块的首发候选清单。
> 跟 [docs/launch-kol-outreach.md](./launch-kol-outreach.md) 配套使用。
>
> 最后更新：2026-05-15
> 作者：majia
>
> 状态：**候选清单初稿**。带 `[待 verify]` 标记的条目需要在 T-10 前确认实际 GitHub repo / skill 名。

## 为什么需要这份清单

[PLAN.md §15.5](../PLAN.md#155-第一批内置能力包候选) 已经定了 v0.2 第一批**Package**（飞书 / PDF / GitHub / 会员运营 / Notion 等）的候选名单。这是 popskill 自己内置的「精装样板间」。

但**v0.1 还没到 Package 重构**，Library / Discover 仍然以 **Skill** 为基本单位。Discover 页需要一个"今天打开 popskill 第一眼看到什么"的答案——这就是 Editor's Pick。

Editor's Pick 跟内置 Package 的差别：

| | 内置 Package（v0.2） | Editor's Pick（v0.1） |
|---|---|---|
| 范围 | popskill 团队自己构建的复合包 | 第三方现成 skill |
| 数量 | P0 四个、P1+P2 各几个 | 10-15 个 |
| 装机方式 | 一键装多组件 | 单 skill 直接装 |
| 价值 | 证明 Package 模型成立 | 证明 popskill 真有内容可逛 |

## 候选标准

1. **作者属于"头部 Skills 开发者"** —— 至少满足下面一条：
   - op7418 2026-05-13 推钦点的「藏师傅、宝玉、乔木、一泽」四家
   - GitHub 仓库 1k+ Star 的 Claude Code skill 集合
   - awesome-claude-skills 类合集里被反复提名
2. **跨 Agent 通用** —— 至少在 Claude Code + Codex 两家工具下可用
3. **文档清晰** —— SKILL.md 有 frontmatter、有 trigger 描述、有用例
4. **持续维护** —— 最近 30 天有 commit 或回复 issue
5. **MIT / Apache / 兼容协议** —— popskill 内置展示不引入授权风险

## Tier 1：op7418 钦点四家的代表 skill

下面四家的 skill 仓库名 / 具体 skill 名在 T-10 前需要逐项 verify。先列名字框架，verify 之后填实际 repo 路径。

### 宝玉 / dotey

- **来源**：dotey 自陈"baoyu-skills 快 2 万 Star"（2026-05-11 长推原话）
- **候选 GitHub repo**：`dotey/baoyu-skills` 或类似 `dotey/baoyu` 命名 `[待 verify]`
- **候选 skill 入选 2-3 个**：
  - `baoyu-presentations`（dotey 在 Codex 实际用的 Presentations Plugin 的对应 skill）`[待 verify]`
  - `baoyu-image-gen`（如果存在）`[待 verify]`
  - `baoyu-xhs`（如果存在，对应"内容创作"轨道）`[待 verify]`
- **入选理由文案**：「2 万 Star 的 baoyu-skills 系列，作者 dotey 在 X 上长期分享 Skills 商业化思考。这几个是从 Codex 实际生产用例里挑出来的。」

### 归藏 / op7418

- **来源**：op7418 自家 guizang.ai 平台 + 个人 GitHub
- **候选 GitHub repo**：`op7418/guizang-skills` 或 `op7418/skills` `[待 verify]`
- **候选 skill 入选 2-3 个**：
  - `guizang-xhs`（小红书运营，归藏的标志性场景）`[待 verify]`
  - `guizang-prompt-engineering`（如果存在）`[待 verify]`
- **入选理由文案**：「归藏（藏师傅）是 op7418 主推钦点的'头部 Skills 开发者'之一，专注 AI 内容创作生态。」

### 乔木 / vista8

- **来源**：op7418 钦点
- **候选 GitHub repo**：`vista8/skills` 或类似 `[待 verify]`
- **候选 skill 入选 1-2 个**：`[待 verify]`
- **入选理由文案**：待 verify 后填具体场景

### 一泽 / eze_is_1

- **来源**：op7418 钦点
- **候选 GitHub repo**：`eze_is_1/...` 或类似 `[待 verify]`
- **候选 skill 入选 1-2 个**：`[待 verify]`
- **入选理由文案**：待 verify 后填具体场景

## Tier 2：高 Star 的 Claude Code skill 集合（不分作者）

补足头部四家覆盖不到的领域，确保 Editor's Pick 横跨 8-10 个用例场景。

| 候选 | repo | 用例场景 | 标 |
|---|---|---|---|
| caveman | `JuliusBrussee/caveman` | Token 节省（说"caveman speak"省 65% token）| 58k Star，火爆 |
| Lark Doc skill | majia 自己写的 lark-doc skill | 飞书文档处理 | 自家产品对照 |
| guancli skills | majia 写的观远 BI 系列 | 企业数据分析 | 自家产品对照 |
| anthropic-skills:pptx | Anthropic 官方 | PPT 生成 | 官方背书 |
| anthropic-skills:docx | Anthropic 官方 | Word 文档 | 官方背书 |
| anthropic-skills:xlsx | Anthropic 官方 | Excel 处理 | 官方背书 |
| anthropic-skills:pdf | Anthropic 官方 | PDF 阅读 | 官方背书 |
| ECC 内 top 3 skill | everything-claude-code | 综合工具 | 中文圈认知 |

## Editor's Pick UI 显示策略

Discover 页 Featured 区域的卡片布局（参考 [PLAN.md §3.2 Page 1](../PLAN.md#page-1--featured-discover-首页)）：

```
🌟 EDITOR'S PICK
┌──────────────────────────────────────────────┐
│  baoyu-presentations  by @dotey              │
│  2 万 Star 系列里的 PPT 神器                  │
│  ⭐ 19,000  •  在 Codex / Claude Code 可用   │
│                          [▼ Install]         │
└──────────────────────────────────────────────┘
```

**关键 UX 细节**：

- 作者头像旁加蓝色 verified 角标（如果在 Tier 1 四家名单里）
- 卡片下方副标题用一句**作者本人的话**或**op7418 推钦点**的语境句
- Tier 1 四家的 skill 在 Featured **始终置顶 4 卡**
- Tier 2 其他卡片轮换显示（按本周 awesome-list 新增数排序）

## 怎么把这些 skill 升级成 v0.2 Package

[PLAN.md §15.5](../PLAN.md#155-第一批内置能力包候选) 已经定了 P0 四个 Package（飞书 / PDF / GitHub / 会员运营）。Tier 1 的 skill 可以这样归类到未来 Package：

| Editor's Pick skill | 候选目标 Package（v0.2） | 注释 |
|---|---|---|
| `baoyu-presentations` | 新增 Package: **Presentations** | dotey 实际在用 Codex Plugin 验证过这条赛道 |
| `baoyu-image-gen` | P1 **图像生成全家桶**（已在 PLAN §15.5） | 直接归入 |
| `baoyu-xhs` | P2 **微信生态** 或 新增 **内容创作** | 暂归内容创作 |
| `guizang-xhs` | 同上 | 中文圈小红书运营轨道 |
| `vista8-*` / `eze-*` | 看 verify 之后的具体场景 | 待 verify |
| `caveman` | 不归 Package，**独立卡片**保留 | 因为它是横切性的 token saver，不属任何垂直领域 |

**结论**：dotey 的几个 skill 大概率会触发一个 PLAN.md §15.5 没列的 **Presentations Package** 候选，需要 v0.2 周期重新评估。

## T-10 前必须 verify 的事项

发布前 10 天要做的一次性核实，避免发布时 Editor's Pick 卡片指向 404 或错误 repo：

1. **四家 KOL 的实际 GitHub handle**：
   - dotey 在 GitHub 是 `dotey` 还是别的？
   - op7418（归藏）在 GitHub 的实际 username？
   - vista8 / eze_is_1 GitHub 是否存在？
2. **每家代表性 skill repo**：
   - `baoyu-skills` 是否就是 dotey 那个 2 万 Star 的 repo？
   - 还是 `dotey/skills`？
   - skill 文件结构是 anthropics/skills 格式还是自定义？
3. **License 兼容**：
   - 至少 MIT 或 Apache 2.0
   - 不能是 AGPL / CC-NC（popskill 内置展示算商业用途，CC-NC 不允许）
4. **作者 awareness**：
   - Tier 1 两位（dotey / op7418）按 [docs/launch-kol-outreach.md](./launch-kol-outreach.md) 在 T-7 私信预告，**包含**"想把您家几个 skill 放进 popskill Editor's Pick"的提议
   - 不需要正式 license / 协议，但需要让作者知情，避免发布后他们觉得被"未经同意展示"

## 长期：从"内置硬编码"过渡到"动态拉取"

v0.1 的 Editor's Pick 是**硬编码 JSON**（在 popskill bundle 里），改一次要发版本。

v0.2 之后应该：

1. **远端 JSON** —— popskill 启动时拉一份 `https://popskill.example/editors-pick.json`（具体域名 TBD）
2. **轮播策略** —— 一个 skill 在 Featured 区最多显示 2 周，避免疲劳
3. **本地化** —— 中文 / 英文用户看到的 Editor's Pick 不一样（dotey/op7418 这种中文圈 KOL 对英文用户不一定有意义）
4. **作者投稿** —— 开 PR 让作者主动 nominate 自己的 skill 进 Editor's Pick（带 review）

v0.1 不做以上四件事，硬编码就够。本文件归档到 `docs/history/` 时把实际 verify 之后的清单 commit 进去，作为 v0.2 远端 JSON 的第一版数据。

## 失败兜底

如果 T-10 verify 完发现 Tier 1 四家中任何一家的 skill repo **不符合 anthropics/skills 格式**、**不兼容 license**、或**作者明确拒绝**：

- **不在 Editor's Pick 强行展示**（强行展示对作者不尊重，也容易翻车）
- 用 Tier 2 候选填补该位置
- 在 docs/launch-kol-outreach.md 里更新这位 KOL 的状态：从 Tier 1 降级为 Tier 3（只关注、不私信、不放 Pick）

最坏情况：Tier 1 全军覆没，Editor's Pick 全用 Anthropic 官方 + caveman + majia 自家几个 skill 填——**这也能跑**，只是失去"头部背书"这一层。**popskill v0.1 发布不依赖 KOL 入选，它只是加分项**。
