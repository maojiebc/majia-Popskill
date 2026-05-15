# Architecture Reference: skillctl Conversation (2026-05-15)

> 一份**归档参考**文档。归档自 Codex thread `019e2aaa-21e4-75a0-8408-a1e8f21e0822`
> （2026-05-15 16:04 UTC）majia 与 Codex 的本地 skill 治理设计讨论。
>
> 这份文档不是 popskill 的 PLAN，是 PLAN 的**设计输入源材料**。popskill v0.2+
> 周期遇到「本地 skill store 该怎么设计」这类问题时，先看这份。
>
> 最后更新：2026-05-15
> 作者：majia + Codex（讨论沉淀）
> 关联文档：[docs/asset-control-plane.md](./asset-control-plane.md) / [PLAN.md §15.2](../PLAN.md#152-核心定义)

---

## 0. 这次讨论为什么发生

majia 起的头是一个非常实际的本地 skill 治理问题：

> "重新梳理本地的 skill 现状，codex、Claude 应该是有两套，ccswitch 还有一套软链接的兼容方式"

盘点之后发现本地实际是**三层叠加**：

| 层 | 路径 | 内容 |
|---|---|---|
| Codex 运行层 | `~/.codex/skills` + `~/.agents/skills` | 48 个入口，37 个软链，17 个断链 |
| Claude 运行层 | `~/.claude/skills` | 30 个入口全是软链，19 个断链（Lark 扩展指向已不存在的 `~/.agents/skills/lark-*`） |
| ccswitch 缓存/兼容层 | `~/.cc-switch/skills` | 63 个目录全有 SKILL.md（卸载后变残留缓存）|

加上 plugin namespace（`anthropic-skills:*` 这种被 plugin manifest 加载、不走 `~/.claude/skills/` 解析的 skill），实际是**四个不同来源**叠在一起。

majia 在讨论里说出了 popskill 真正想解决的那句话：

> "把它想成**agent 世界的 pnpm / mise**——核心模型是'一份物理存储 + 多个消费者投影'，别的都是边角。"

整个 session 围绕这个 frame 跑下来，沉淀出一套**最小但完整**的设计契约。下面是核心提炼，**不是 popskill 已经实现的**，而是 popskill 在 v0.2+ 周期可以参考的设计参照系。

---

## 1. 三层数据模型

```
~/.agents/sources/         # 上游来源（local source / git / archive）
   xxx-skill/              # 本机开发，mutable，指向 ~/projects/xxx
   yyy-skill@1.2.0.tgz     # 上游下载，immutable

~/.agents/store/           # content-addressable，一份物理存储
   xxx-skill@dev-7f3a/     # tag = sha256(SKILL.md + 主要文件) 前 4 位
   yyy-skill@1.2.0-abcd/
   yyy-skill@1.3.0-efgh/   # 多版本共存

~/.agents/projections/     # 每个 agent 一份投影
   claude/skills/
       xxx-skill -> ../../store/xxx-skill@dev-7f3a/
       yyy-skill -> ../../store/yyy-skill@1.3.0-efgh/
   codex/skills/
       xxx-skill -> ../../store/xxx-skill@dev-7f3a/
       yyy-skill -> ../../store/yyy-skill@1.2.0-abcd/   # codex 还没升级
```

`~/.claude/skills/` 整目录软链到 `~/.agents/projections/claude/skills/`，以后只动 projection 这一层，Claude/Codex 看到的是**同一个物理目录**，版本自然一致。

### 跟 popskill 当前模型的对应关系

popskill v0.3 的 [asset-control-plane.md](./asset-control-plane.md) 抽象是：

```
source -> package -> component -> deployment -> runtime
```

两套对应：

| skillctl 层 | popskill 层 | 备注 |
|---|---|---|
| `sources/` | `source` | 一致，都是"能力来源" |
| `store/` | **当前缺失** | popskill 没有专门的 content-addressable store 层 |
| `projections/` | `deployment` | 一致，都是"投射到目标 agent" |

**关键 gap**：popskill 当前缺 `store/` 这一层——所有 component 直接从 source 投影到 deployment，没有中间的 content-addressable 快照层。这意味着：

- 版本管理是隐式的（靠 contentHash 字段）
- 多版本共存做不到（只有"当前装的那一版"）
- mutable 和 immutable 没有边界（开发中和已发布的 skill 处理方式一样）

这是 popskill v0.2 周期最值得考虑引入的**新抽象层**。

---

## 2. 5 条命令够

skillctl 的完整 CLI surface 就 5 条：

```bash
skillctl add <source>                  # 注册进 sources/，算 hash，落 store
skillctl link <name> --to claude,codex # 在 projection 里建链
skillctl pin <name>@<ver> --for claude # 某个 agent 锁版本
skillctl status                        # 一张表：每个 agent 当前每个 skill 的 hash+mtime
skillctl doctor                        # 扫遗留目录、断链、name 冲突、未锁飘移
```

**刻意不做的**（这才是设计精髓）：

- ❌ 不做 daemon
- ❌ 不做 GUI（status 输出真要可视化再加个本地 web）
- ❌ 不做自动升级
- ❌ 不做 LLM 端版本自省 API
- ❌ 不做跨机自动同步

### 跟 popskill 当前 sidecar 命令的对应

popskill 的 [skill-cli](../skill-cli/) 已经有 40+ 子命令。但这 40+ 命令里**没有完全对位 skillctl 5 条**的：

| skillctl 命令 | popskill 当前 | 差距 |
|---|---|---|
| `add <source>` | `repo-add`、`import-unmanaged` | 没有 hash 进 store 这一步 |
| `link <name> --to <targets>` | `install <skill> --app <target>` | 是 copy/configPatch 不是 symlink projection |
| `pin <name>@<ver> --for <agent>` | 无 | **缺失**——没有 per-agent pin 概念 |
| `status` | `list`、`detail` | 接近，但缺 lockfile 视图 |
| `doctor` | `health` | popskill 的 health 是 sidecar 健康，不是 skill 拓扑健康 |

**关键 gap**：缺 **per-agent pin** 这个概念。popskill 当前是"装一次给所有 enabled apps"，不能"Claude 用新版、Codex 临时 pin 老版"。这是包管理器和同步工具的根本差别。

---

## 3. 3 个非显然的设计决策

### 3.1 name 和 id 分离

SKILL.md 加 `id:` 字段（reverse-domain，例如 `com.majia.guanyuan`），`name:` 只是显示名。

```yaml
---
id: com.majia.guanyuan
name: 观远 BI 全链路
aliases: [guanyuan-majia, majia-guandata]
version: 2.1.4
---
```

`guanyuan-majia` 和 `majia-guanyuan` 可以是同一个 id 的两个 alias，registry 按 id 去重，doctor 报 alias 冲突。

**这一条不做，后面所有去重逻辑都是临时补丁。**

popskill 当前 [Skill 模型](../swift-app/Sources/Popskill/Models/SkillModels.swift)用 `id = "owner/name:directory"`（仓库格式），不是 reverse-domain。**v0.1.x 补丁周期应该把 stable id 字段加进 schema**，旧 skill 生成 synthetic id（`gen:owner.name`），doctor 报"建议补 id"。

### 3.2 每个 agent 一份 lockfile

`~/.agents/projections/claude/lock.toml` 写明这台机当前 Claude 看到的每个 skill 的 `id + version + hash + source`。

```toml
[[skills]]
id = "com.majia.guanyuan"
name = "majia-guanyuan"
version = "2.1.4"
hash = "sha256:7f3a..."
store = "majia-guanyuan@2.1.4-7f3a"
source = "local:/Users/majia/projects/majia-guanyuan"
mutable = false
aliases = ["guanyuan-majia"]
```

可以 `git commit`、可以 `diff`、可以 PR review。Codex 那份独立——可以 Claude 用新版、Codex 临时 pin 老版，等验完再升。

> "这是和'软链直挂源码'最大的区别：那种做法两边强制同步，一升就一起升，出问题没有缓冲。"

**popskill 当前是 SQLite + jsonl 持久化**——机器可读但不利于 git diff / PR review。v0.2 周期建议**旁路出一份 lockfile.toml**（每个 target 一份），SQLite 仍然是 SSOT 但 lockfile 是"人类视图 + 跨设备同步媒介"。

### 3.3 区分 mutable / immutable

- **mutable**：本机正在写的 skill（指向 `~/projects/xxx-skill`），store 里就是软链回源码，hash 每次进出重算
- **immutable**：上游下载或伞形发布的，落 store 后**只读**

doctor 看到 immutable 目录被人手改过会报 **tamper**（很常见的事故：在 store 目录里直接 `vim SKILL.md` 改完忘了）。

popskill 当前**没有区分 mutable / immutable**。所有 skill 一视同仁。引入这个区分会让 doctor 能发现"开发中 skill 还在 store 里"和"已发布 skill 被本地改过"这两类不同的健康问题。

---

## 4. Codex 收敛的 5 个硬不变量

讨论尾声 Codex（GPT-5）对这套模型做了一次收敛，提出 5 个**绝不能违反的设计原则**：

### 不变量 1：Plugin namespace 只读旁路

> `anthropic-skills:*`、Codex bundled/plugin skills 不进 `store`，只在 `status/doctor` 里作为 external namespace 展示。**不能投影、不能劫持。**

理由：plugin 是 host app（Claude Desktop / Codex / Cursor）自家加载机制的产物，**不在 popskill 的 SSOT 范围内**。试图通过软链劫持 plugin 目录，下次 plugin 自我升级会把软链覆盖回去，造成静默事故。

**给 popskill 的明确决策**：v0.1 PLAN §15.2 提的"v0.2 评估 plugin 一类 component kind"——结论是 **plugin 不入 store / 不投影 / 不作为 component kind**。它只在 doctor 的 inventory 里作为 external namespace 显示（让用户知道"这是 plugin 来的，popskill 管不到"）。

### 不变量 2：projection 是唯一 agent 可见面

> Claude/Codex 不再各自维护实体 skill。能整目录 symlink 就整目录；实测不行就退成目录内逐项 symlink，但仍然由 projection 生成。

理由：每个 agent 直接读 `~/.claude/skills` / `~/.codex/skills` 这样的固定路径。popskill 把这些路径软链到 projection 目录，agent 看到的就是 popskill 渲染的视图。

**给 popskill 的明确决策**：当前 popskill 的 deployment 策略已经支持 4 种（copy / configPatch / wrapper / symlink），但 `symlink` 是最后选择。**v0.2 周期应该让 symlink 升为默认**（前提是实测各 agent 都能稳定接受）。

### 不变量 3：lockfile 是真相，symlink 是产物

> `~/.agents/projections/<agent>/lock.toml` 决定当前版本；`skills/<name> -> store/...` 只是 render 出来的结果。坏了可重建。

理由：lockfile 是 SSOT，symlink 是 render。万一 symlink 全断了或被外部工具改坏，**根据 lockfile 重新 render projection 即可**，不丢数据。

**给 popskill 的明确决策**：当前 popskill 的 SSOT 是 SQLite + 文件投影。**v0.2 加 lockfile**，让 projection 变成"可重建的视图"。

### 不变量 4：mutable 要显式标红

> content-addressed store 默认应该是 **immutable snapshot**。开发中的 `~/projects/xxx` 可以用 `--dev` 模式投影，但 lockfile 要写 `mutable = true` 和 `observed_hash`，doctor 一看到 hash drift 就提示，而不是假装它还是 `dev-7f3a`。

理由：路径名里带 hash 但内容会漂——这个语义在多人协作或多机同步时会爆。

**给 popskill 的明确决策**：v0.2 引入 `mutable: bool` + `observed_hash: string` 两个字段。`--dev` 模式下不冻结 hash，但 doctor 每次启动比对 observed_hash 和当前实际 hash，drift 就告警。

### 不变量 5：id 优先，name/alias 次之

> `id = "com.majia.guanyuan"` 是去重主键；`name` 是显示/触发名；`aliases = ["guanyuan-majia"]` 处理历史命名。没有 `id` 的旧 skill 先生成 synthetic id，doctor 报"建议补 id"。

理由：name 是给人看的，会改、会撞。id 是机器主键，必须稳定。

**给 popskill 的明确决策**：**v0.1.x 补丁周期**加 `id` 字段到 Skill schema，SQLite migration 给历史 skill 生成 synthetic id（`gen:{owner}.{name}`），AgentShield 用 id 而非 path 作 dedup key。

---

## 5. Publisher / Consumer 解耦

majia 在 session 最后给出了一个非常关键的角色划分：

> "`bundle_sync.py` 那一套重新定位成 **publisher**：把 mutable source 打包、产出 immutable archive、push 到伞形仓库 / GitHub release。这个新工具是 **consumer side**：在每台 mac 上 `skillctl add <umbrella-url>` 拉下来，projection 给各 agent。publisher 和 consumer 解耦后，不会再出现'伞形 push 回来，本机软链被覆盖成实体目录'那种 race。"

### 给 popskill 的角色定位

```
┌─────────────────────────────────────────────────────────────┐
│  Publisher 侧                                                │
│  majia-ota-skill (已存在)                                    │
│  - bundle_sync.py 产出 immutable archive                     │
│  - 推 umbrella repo / GitHub release / npm                   │
└──────────────────────────┬──────────────────────────────────┘
                           │ artifact / lockfile
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  Consumer 侧（两个工具，各管一摊）                            │
│                                                              │
│  popskill (GUI consumer)        skillctl (CLI consumer)      │
│  - macOS 原生 SwiftUI            - 终端纯文本                 │
│  - Usage Insights + Stub         - lockfile diff             │
│  - 多类 component                - 只管 skill 一类           │
│  - WebDAV 跨设备同步              - 不跨机                    │
└──────────────────────────┬──────────────────────────────────┘
                           │ projection
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  Agent 侧                                                    │
│  Claude Code / Codex / Cursor / OpenClaw / Hermes            │
└─────────────────────────────────────────────────────────────┘
```

**popskill 的 raison d'être 就在 consumer 侧**——做 GUI、做多 component、做 Usage Insights、做 WebDAV 同步。**popskill 不应该自己做 publisher**（majia-ota-skill 已经做了），也**不应该跟 skillctl 抢 CLI 用户**（两者目标用户不同）。

---

## 6. 给 popskill 的具体改造清单

按 v0.1 / v0.1.x / v0.2 分期，按价值排序：

### v0.1 内（可立即落实，doc-only）

1. ✅ **本文件归档** —— 这次 session 的核心讨论沉淀
2. ✅ **PLAN.md §15.2 收敛 plugin namespace 决策** —— 从"开放评估"变成"明确不入 store"
3. **更新 docs/asset-control-plane.md** —— 加一节「Content-Addressable Store（v0.2 储备）」预留位置

### v0.1.x 补丁周期（v0.1 发布后 30 天内）

4. **Skill schema 加 stable `id` 字段** —— reverse-domain 风格，SQLite migration，synthetic id 兜底
5. **`skill-cli doctor --inventory` 子命令** —— 扫所有 skill 根目录的断链/重复/版本漂/孤儿/未补 id

### v0.2 周期（Package 重构同期）

6. **Content-addressable store 层** —— `~/.popskill/store/<id>@<version>-<hash4>/`，与 sources 和 deployments 解耦
7. **Per-target lockfile** —— `~/.popskill/projections/<target>/lock.toml`，SQLite 仍是 SSOT 但 lockfile 是人类视图
8. **mutable / immutable 区分** —— 字段 + doctor tamper detection
9. **Per-agent pin** —— 一个 skill 在 Claude 锁新版、Codex 临时锁老版

### 永不做（明确划线）

- ❌ 自动升级 —— 每次升级走人工 review lockfile diff
- ❌ LLM 端版本自省 API —— 防止 skill 作者写 `if version >= 1.3` 分支
- ❌ 跨机自动同步替代 WebDAV —— popskill 走 WebDAV，跨机不再做新机制

---

## 7. 实证测试计划

majia 在 session 里强调了一条非常关键的方法论：

> "Codex 是否真的直读 `~/.agents/skills` 要先实测一次。最稳的验证方式：塞个最小 `_probe` skill，物理目录的 SKILL.md 标 `version: B`，软链入口标 `version: A`，看 Codex 命中之后报的是哪个版本。这条不先打通，'统一入口'只是你以为的统一，实际可能 Codex 还有自己的 cache / 优先目录。"

### popskill v0.2 进入 Content-addressable store / projection 设计前的实证测试清单

每个目标 agent 都要跑一次：

| 测试 | 目标 | 通过标准 |
|---|---|---|
| `_probe` skill 整目录 symlink | Claude / Codex / Cursor / OpenClaw / Hermes | agent 调用后报出 store 里的 version 而非 projection 标的 |
| `_probe` skill 逐项 symlink | 同上 | symlink 失败时 fallback 也能工作 |
| store 内容修改 → projection 是否反映 | 同上 | mutable 模式下能看到改动；immutable 模式下报 tamper |
| 同名不同 id 的 skill 共存 | 同上 | 用 id 路由不撞名 |
| plugin namespace 旁路 | Claude（含 `anthropic-skills:*`）| popskill doctor 列出 plugin skill 但不投影 |

这套 _probe 测试**应该作为 v0.2 实施前的硬 gate**——没跑完不开工。

---

## 8. 关于这份文档

- **它是参考材料，不是 PLAN** —— popskill 的实施计划仍以 [PLAN.md](../PLAN.md) 为准
- **不主动 sync** —— Codex session 是 2026-05-15 的快照，未来 skillctl 这套模型如有进展，由 majia 主动更新本文档
- **可以归档** —— v0.2 实施完成后，把"具体改造清单"标记为 ✅ 后归档到 `docs/history/`，留一份记录

如果 v0.2 周期开始时这份文档跟当时的 popskill 实施现状有重大分歧，**以新现状为准**——架构参考永远应该被实际跑出来的代码覆盖，不是反过来。

---

## 9. 引用资料

- **原始 session**：`~/.codex/sessions/2026/05/15/rollout-2026-05-15T16-04-13-019e2aaa-21e4-75a0-8408-a1e8f21e0822.jsonl`
- **popskill 当前架构契约**：[docs/asset-control-plane.md](./asset-control-plane.md)
- **popskill PLAN v0.2 Package 重构段**：[PLAN.md §15](../PLAN.md#15-v02v03-实现状态package-能力包重构)
- **majia-ota-skill 发布管道**（publisher 侧已有）：`~/projects/majia-private-skills/skills/majia-ota-skill/`
