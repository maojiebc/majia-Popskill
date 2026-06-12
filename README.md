# Popskill

> **本地 AI 能力管理器**。技能装一次，挂到多个 AI 工具上；坏了能修，旧了能升。Claude Code 和 Codex 的 skill，从此一张表管完。

<p align="center">
  <a href="https://github.com/maojiebc/majia-Popskill/releases/latest">
    <img src="docs/screenshots/hero.png" alt="Popskill 能力矩阵 — 源式套装自动归拢" width="900">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/github/v/release/maojiebc/majia-Popskill?color=orange" alt="Latest release">
  <img src="https://img.shields.io/github/downloads/maojiebc/majia-Popskill/total?color=green" alt="Downloads">
  <img src="https://img.shields.io/github/license/maojiebc/majia-Popskill" alt="MIT License">
  <img src="https://img.shields.io/badge/Sparkle-auto--update-purple" alt="Sparkle">
</p>

> 中文 · [English README](./README.en.md)

---

## 下载安装

[**↓ 下载 Popskill（2.4 MB，已签名 + 已公证）**](https://github.com/maojiebc/majia-Popskill/releases/latest/download/Popskill-2.9.0.dmg)

要求 macOS 14 (Sonoma) 及以上。装完之后新版本走 Sparkle 应用内更新，不用再来 GitHub。

DMG 经过 Apple Developer ID 签名 + 公证 + 钉票，**双击不会跳"未识别开发者"警告**。

---

## 我为什么做这个

我的 Mac 上有 **72 个 skill、来自 9 个上游、用着 6 种互不兼容的更新机制**——npm 包、git monorepo、独立 clone、`npx skills`、自定义安装器、Marketplace。在 Popskill 之前，维持这套东西最新需要一个 178 行的 shell 脚本加 launchd 定时任务，而且没有任何工具能回答「我装了什么、哪个旧了、哪条链断了」。

Popskill 的回答是把管理建立在一个最简单的事实上：**技能就是文件夹，启用就是 symlink**。

```text
~/.agents/skills/baoyu-comic/          ← store：技能本体（装一次）
~/.claude/skills/baoyu-comic  → 软链   ← Claude Code 用
~/.codex/skills/baoyu-comic   → 软链   ← Codex 用
```

文件系统就是数据库。没有 sidecar、没有 SQLite，你的目录结构本身即全部状态——Popskill 只是给它一张看得见、点得动的脸。

---

## 截图

<table>
<tr>
<td><img src="docs/screenshots/settings.png" alt="来源自动识别"></td>
<td><img src="docs/screenshots/peek.png" alt="详情 peek"></td>
</tr>
<tr>
<td><b>来源自动识别</b> — 五级回填（lock 文件 / git remote / frontmatter / 内置目录），装过的东西不用告诉它从哪来</td>
<td><b>详情 peek</b> — 点名称看 SKILL.md 摘要，看完即走，深读去编辑器</td>
</tr>
<tr>
<td><img src="docs/screenshots/fix.png" alt="行内修复"></td>
<td><img src="docs/screenshots/add.png" alt="安装计划"></td>
</tr>
<tr>
<td><b>行内修复</b> — 断链 / 校验失败 / 本地副本，点 ✕ ◐ 出方案，推荐项标绿</td>
<td><b>安装计划</b> — 粘贴 URL，看清要写什么（含 ln -s 预览）再点安装</td>
</tr>
</table>

---

## 功能

- **能力矩阵** — 全部技能一张表：每行一个能力，Claude / Codex 两枚状态 pill，点一下挂载/摘除
- **源式套装** — 同一上游仓库的技能自动归拢成一张卡（宝玉系 22 项、飞书系 26 项），磁盘平铺、symlink 不动
- **内容哈希更新** — 不依赖版本号，逐成员 SHA-256 比对上游；monorepo 一次 clone 检完全员、只换变化的，还提示「上游新增了 N 个你没装的」
- **更新前自动备份** — 被替换的旧版进回收站（保留 20 份），随时可恢复
- **行内修复** — 断链 / 本地副本一键处理；所有危险操作只动 symlink，真实目录一律进回收站
- **未托管导入** — 散落在 `~/.claude` / `~/.codex` 的真实技能目录，一键收编进 store 换成 symlink
- **键盘导航** — `↑↓` 行焦点、`←→` 选工具列、`空格` 切换挂载或修复、`/` 搜索、`Esc` 退出
- **内置精选目录** — 约 80 个热门 skill 的中文一句话简介与类型提示，上游英文长描述不再直出卡片

---

## 快速上手

1. 装好打开——如果你已经在用 `~/.agents/skills/`（`npx skills` 生态约定目录），矩阵会直接铺满你现有的技能
2. 还没有？点「+ 添加」粘贴一个 GitHub 仓库试试，比如 `github.com/anthropics/skills`
3. 在卡片上点 Claude / Codex pill 挂载；点 ✕ 或 ◐ 修复异常；设置里开「自动更新」

---

## 工作原理

<p align="center">
  <img src="docs/architecture.png" alt="Popskill 功能架构 — 上游来源 → 六大模块 → ~/.agents store → symlink 到 Claude/Codex" width="820">
</p>

来源识别是五级回填：popskill 自装记录 → `.skill-lock.json`（`npx skills` 生态锁文件）→ 技能目录自带的 git remote → SKILL.md frontmatter homepage → 内置精选目录（救 guanskill 这类复制安装的「来源孤儿」）。更新比对用目录内容哈希（SHA-256），所以**没有规范版本号的技能也能发现更新**。

---

## FAQ

**Q：为什么不上 Mac App Store？**
App Store 的 sandbox 不允许应用管理 `~/.claude`、`~/.codex` 这些目录的 symlink。直接分发才能让它真正干活。签名 + 公证保证安全性等价。

**Q：收集任何数据吗？**
不。100% 本地运行，无统计、无遥测。网络访问只有两种：检查更新时 `git clone` 你自己技能的上游仓库，以及 Sparkle 检查应用自身更新。

**Q：数据存在哪？怎么卸载？**
技能本体在 `~/.agents/`（这是你的数据，不是 Popskill 的）；应用自身的元数据只有一个 `~/.agents/.popskill.json`。卸载 = 把 Popskill.app 拖进废纸篓，你的技能和 symlink 原样保留。

**Q：它会动我的文件吗？**
防呆三条铁律：只删 symlink、真实目录一律进回收站（`~/.agents/.trash/`，留 20 份）、store 目录绝不被开关动到。40 个引擎单测盯着这些行为。

**Q：支持 Claude Code / Codex 之外的工具吗？**
架构上工具列表是动态的，但当前版本刻意只做这两个（我自己的真实需求）。原生扫描 `~/.agents/skills/` 的工具（如 opencode）无需 symlink 直接可用。

**Q：Windows / Linux？**
不做。纯 SwiftUI，Mac only。

---

## 版本

当前 [v2.9.0](https://github.com/maojiebc/majia-Popskill/releases/tag/v2.9.0) · 全部版本见 [Releases](https://github.com/maojiebc/majia-Popskill/releases) · 更新日志在 `docs/release/`

v2 是一次按第一性原理的重写（一个屏幕、文件系统即数据库）。v1.x（sidecar 架构）已下线，设计过程归档在 `docs/design/`。

---

## 致谢

- **[CC Switch](https://github.com/farion1231/cc-switch)** — 这个项目的起点。Popskill v1 以零 fork 方式（git submodule）把它的 Rust services 层直接当存储引擎用；v2 虽然改为纯 Swift 直写文件系统，但 v2.1 的更新机制——内容哈希比对上游、更新前自动备份、按应用独立启用位——都直接借鉴自它的 skill 管理设计。
- **[Sparkle](https://sparkle-project.org)** — Mac 应用内自动更新的事实标准，本应用的更新分发由它驱动。
- **`npx skills` 生态** — `~/.agents/skills/` 跨工具约定目录与 `.skill-lock.json` 锁文件，是 Popskill 来源识别与互操作的基石。

---

## 👤 作者 / 联系

**马甲（@maojiebc）** · 超级马甲

如果这款 Mac app 帮到你,欢迎在以下任意渠道找我交流踩坑实录、提需求、报 bug,也欢迎勾兑 Mac 自研 app / 用户运营 / AI 工具集成的实战经验:

| 渠道 | 链接 |
|---|---|
| 📧 Email | [m9224@163.com](mailto:m9224@163.com) |
| 🐙 GitHub | [github.com/maojiebc](https://github.com/maojiebc) |
| 🪝 ClawHub | [clawhub.ai/p/maojiebc](https://clawhub.ai/p/maojiebc) |
| 🐦 X | [@maojiebc](https://x.com/maojiebc) |
| 📕 小红书 | [超级马甲](https://xhslink.com/m/4fQMJeHHWKC) |
| 📰 微信公众号 | **超级马甲** |

> 这款 app 是 14 年用户运营 + Mac 自研实战沉淀 出来的,问题/合作随时聊。

## License

[MIT](./LICENSE)
