# Popskill

> A Mac App Store-style client for managing Claude Code Agent Skills.
> 一款看齐 Mac App Store 的 Claude Code Agent Skills 桌面客户端。

<p align="center">
  <strong>Status: 📋 Planning / Pre-alpha — no code yet, only docs.</strong>
</p>

---

## English (TL;DR)

Popskill aims to be the App Store experience that Claude Code skills deserve on Mac:

- **Mac-native SwiftUI design** (inspired by Surge for Mac)
- **Inline multi-app toggle** for Claude / Codex / Gemini (CC Switch's pain point: you have to enter a detail page just to flip Codex on/off)
- **Usage Insights** — token spend, top skills, hibernate candidates (parses `~/.claude/projects/*.jsonl`). No other tool does this.
- **Stub state** — like App Store's "purchased but not downloaded"; reclaim disk without losing the card
- **WebDAV sync** across devices (reuses [CC Switch](https://github.com/farion1231/cc-switch)'s implementation — zero re-implementation)

**Architecture**: SwiftUI front-end → `skill-cli` Rust sidecar → `cc_switch_lib` (CC Switch as git submodule, **zero fork, zero patch**).

**Current stage**: design + planning complete; Day 1 scaffolding pending. See [PLAN.md](./PLAN.md) and [STYLE.md](./STYLE.md) for the full picture.

---

## 中文版

### 它是什么

Claude Code 的 Agent Skills 生态在 GitHub 上已经爆炸（[anthropics/skills](https://github.com/anthropics/skills) 13万⭐、各种 awesome-list 60万+⭐ 总和），但**没有一个 Mac 客户端把"发现 / 安装 / 管理 / 统计"做成 App Store 那种体验**。

Popskill 就是来填这个坑的。

### 它跟现有方案差在哪

| 工具 | 缺点 |
|---|---|
| **[CC Switch](https://github.com/farion1231/cc-switch)** (6.8万⭐) | 功能太杂（6 种 CLI + Provider + Skill 全塞一起），新手找不到入口；多 app toggle 必须进详情页 |
| **[agent-skills-guard](https://github.com/bruc3van/agent-skills-guard)** (354⭐) | 只做安全扫描，没有 App Store 发现/统计 |
| **[vercel-labs/skills](https://github.com/vercel-labs/skills)** (1.8万⭐) | CLI 工具，无 GUI |
| 一众 0-star `claude-skill-manager` | 没人做出 App Store 体验 |

**Popskill 的差异点**：

1. **Mac App Store 级别的视觉**——SwiftUI 原生，配 Surge for Mac 设计语言
2. **使用统计 / Insights 页**（全网独家）——告诉你装的 47 个 skill 里哪些值得保留
3. **行内多 app toggle**——Library 列表行内直接切 Claude/Codex/Gemini
4. **Stub 状态**——60 天没用的 skill 本地清掉内容、留 metadata 卡片，要用一键再装
5. **WebDAV 跨设备同步**——白嫖 CC Switch 已有能力，不重做

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
| **D. 脚手架 init + Day 1** | ⏳ **等待启动** |

**这个仓库目前只有规划和设计文档**，还没写一行代码。

### 文档导航

- **[PLAN.md](./PLAN.md)**（~1265 行）—— 产品 + 工程规划，自包含。新机器接手只需读这一份。
  - §0-2：怎么用 + 16 条核心决策
  - §3：产品形态（5 页 wireframe + 状态机）
  - §4-8：技术架构 + 数据模型 + Sidecar 接口
  - §9：第一周 Day 1-5 milestone
  - §11：已知坑 / 风险预案
  - 附录 A：新电脑接手 6 步 checklist

- **[STYLE.md](./STYLE.md)**（~840 行）—— 视觉设计语言，含立即可用的 SwiftUI design token 代码。

### 在新机器上接手

```bash
# 装工具链
xcode-select --install
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 拉项目
gh repo clone maojiebc/majia-Popskill ~/projects/popskill
cd ~/projects/popskill

# 跟着 PLAN.md §9 干 Day 1
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
