# Popskill v2 — 第一性原理重启计划

> 2026-06-10。前提：回到原始需求（PLAN.md §1「三笔账」），不求功能多，只求满足场景。
> 可以推倒重来。v1.x 永远停在 tag `v1.1.0`，随时可回。

---

## 1. 诊断：现实和 app 之间的三个断裂

### 断裂一：SSOT 错位（最致命）

| | app 以为的世界 | 机器上的真实世界（2026-06-10 实测） |
|---|---|---|
| 权威目录 | `~/.cc-switch/skills/`（52 个） | `~/.agents/skills/`（**72 个**，本地 git 仓） |
| Claude/Codex 启用方式 | sidecar 经 cc-switch 写链接 | `.claude/skills` `.codex/skills` 里的**裸 symlink**（6月8日手工重构） |

结论：**app 看不到 20 个能力，且 toggle 写的链接和真实拓扑不是一套**。继续在 v1.x 上修，等于给一个平行宇宙打补丁。

### 断裂二：幻影需求（为不存在的场景写的代码）

- **Gemini 第三列** — 本机没有 `~/.gemini/skills`，从未用过
- **Agent 管理** — `~/.claude/agents` 现在是 **0 个**文件
- **Discover 商店 / Sources 注册表 / Create / Compose / Fix / WebDAV / AgentShield** — v1.1.0 六个目的地里四个是 UI 占位、后端没接，本人日常一次没用过
- **Package「一等公民」矩阵** — 为「能力套装」概念服务，日常按单 skill 管理

### 断裂三：复杂度倒挂

17,595 行 Swift + 4,796 行 Rust sidecar + cc-switch submodule，服务的核心场景（看全 + 开关 + 揪闲置 + 追新）用 **~2,500 行纯 Swift** 就能覆盖——因为 SSOT 换成裸 symlink 之后，sidecar 存在的唯一理由（复用 cc-switch 的链接管理）消失了。

---

## 2. 场景还原：三笔账 → 四个动作

原始需求（PLAN.md §1 / why-popskill.md）就是三笔账，翻译成动作只有四个：

| # | 动作 | 对应的账 | 频率 |
|---|---|---|---|
| A | **看全**：我有什么、每个干嘛的 | 认知账 | 每周 |
| B | **开关**：这条能力 Claude / Codex 谁启用，一键切 | （Day-5 原始核心） | 每周 |
| C | **揪闲置**：哪些 N 天没用、哪些烧 token 最多 | token 账（杀手锏） | 每月 |
| D | **追新**：哪些上游有新版没拉 | 时间账 | 每月 |

**v2 的全部范围 = A + B + C + D，一个屏幕。** 其他一概不做。

---

## 3. 新架构：文件系统就是数据库

```
Popskill v2 (纯 Swift, 无 sidecar, 无 GRDB, 无 submodule)
│
├── 数据层 = 文件系统本身
│   ├── 扫描 ~/.agents/skills/*/SKILL.md frontmatter   → 能力清单（动作 A）
│   ├── readlink ~/.claude/skills/* ~/.codex/skills/*  → 启用矩阵（动作 B 读）
│   ├── symlink 创建/删除（原子，带防呆：只动指向 SSOT 的链接）→ toggle（动作 B 写）
│   ├── 解析 ~/.claude/projects/**/*.jsonl（懒加载+缓存）→ 用量/最后使用（动作 C）
│   └── git -C <skill> fetch + status（仅对是 git 仓的 skill）→ 更新检查（动作 D）
│
├── UI = 一屏矩阵 + 整页 Inspector（沿用 v1.1.0 紧凑账本视觉语言）
│   ├── 列：名称｜类型彩标｜Claude ●｜Codex ●｜最后使用｜30 天 token｜更新
│   ├── ⌘F 搜索（保留 CJK 别名）
│   └── 点行 → Inspector（README + 路径 + 链接状态，不做 6 个 tab）
│
└── 保留的既有资产（这些不重写）
    ├── 视觉令牌 PopskillColors / LedgerComponents（暖纸账本，直接搬）
    ├── 发布管线 scripts/*（签名/公证/DMG/Sparkle/appcast，已调通的学费）
    └── majia-ota-app skill（发版照走）
```

**关键简化**：SSOT 路径做成可配置（默认探测 `~/.agents/skills`，兜底 `~/.claude/skills`），公开 repo 的外部用户不受影响。

---

## 4. 明确砍掉（v2 非目标）

| 砍掉 | 理由 |
|---|---|
| Rust sidecar + cc-switch submodule | SSOT 换裸 symlink 后无存在理由；省 4.8k 行 + submodule 维护 |
| Discover / Sources 在线商店 | 装新 skill 的真实动作是 `git clone` / skill-manager，app 介入是伪需求 |
| Create / Compose（新建/组装） | 创作走 Claude Code 本身，v1 时代就定过「只做消费端」（PLAN.md §1.4） |
| Fix 修复中心 | 链接坏了 = 矩阵格变 ✕，点一下重建即可，不需要独立页面 |
| WebDAV 同步 / 备份 | ~/.agents/skills 本身是 git 仓，git 就是同步和备份 |
| AgentShield 扫描 | 独立工具的事 |
| Gemini 列 | 本机无此场景；列头做成动态的，哪天有了再加（探测到 ~/.gemini/skills 才显示） |
| Agent / Package 一等公民 | 当前 0 个 agent；package 概念退回「skill 的一种」 |
| GRDB 数据库 | 用量缓存一个 JSON 文件足够 |

---

## 5. 里程碑（每步结束都可发布）

| 版本 | 内容 | 工期估 | 完成标志 |
|---|---|---|---|
| **v2.0** | 矩阵屏（动作 A+B）：扫 ~/.agents/skills、Claude/Codex 双列 toggle（symlink 读写）、搜索、简 Inspector | 3-4 天 | 在自己机器上替代手工 `ln -s`，72 行全显 |
| **v2.1** | 闲置与用量列（动作 C）：jsonl 解析、最后使用时间、30 天 token 归因、闲置排序 | 2-3 天 | 一眼指出 ≥5 个可停用的 skill |
| **v2.2** | 更新检查（动作 D）：git fetch 比对、落后标记、一键 pull | 1-2 天 | 矩阵里能看到「落后 N commit」 |
| **v2.3** | 收口发布：签名/公证/Sparkle（沿用管线）、README 重写 | 1 天 | DMG + appcast 上线 |

总计 **7-10 天**，对照 v1 走了 8 周。

测试基线：每个数据层操作（扫描/链接/解析/防呆）有单测；symlink 写操作必须有「只删指向 SSOT 的链接、绝不 rm 真目录」的防呆测试。

---

## 6. 推倒方式（建议，待拍板）

**原 repo 内重启，不开新 repo**：

1. `main` 上打 tag 确认 `v1.1.0` 为 v1 终点（已有）
2. 新分支 `v2`：删 `skill-cli/`、`cc-switch/`（解 submodule）、`PLAN.md` 移入 `docs/history/`
3. `swift-app` 重建：保 `Design/` + `LedgerComponents` 视觉件，Models/Store/Views 按 §3 重写
4. v2.0 在本机跑顺一周后，`v2` 合回 `main`，发 v2.0.0

理由：保住签名/公证/Sparkle/Pages/Release 这些已付学费的基建和 GitHub 上的 star/历史；推倒的是代码，不是项目。

## 7. 待你拍板的决策点

1. **sidecar 和 cc-switch 彻底删掉**（§4 第一条）——这是不可逆里最大的一刀，但 v1.1.0 tag 永远可回
2. **就地重启 vs 全新 repo**（§6 推荐就地）
3. v2.0 期间 **`~/.cc-switch/skills` 里那 52 个旧副本**怎么处理：建议先不动，v2.1 后确认无引用再归档删除
