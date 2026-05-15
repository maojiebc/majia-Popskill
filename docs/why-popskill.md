# 为什么需要 popskill

> 写给所有在本地堆 AI 能力的人。
>
> 最后更新：2026-05-15
> 作者：majia

这篇是 popskill 的对外科普长文。技术架构、对手矩阵、产品状态等细节请直接看 [README.md](../README.md)、[PLAN.md](../PLAN.md) 和 [docs/asset-control-plane.md](./asset-control-plane.md)。

---

## 一、我本地现在是这样的

早上打开 Mac，跑一遍最近常用的几条指令。

```
ls ~/.claude/skills | wc -l        # 47
ls ~/.claude/agents | wc -l        # 9
ls ~/.local/bin | grep cli         # lark-cli、guancli、observable-cli、getnote-cli
cat ~/Library/Application\ Support/Claude/claude_desktop_config.json   # 5 个 MCP server
ls ~/.config | grep -E "skill|agent|cli"   # 一堆 config patch
```

47 个 skill、9 个 agent、4 个 CLI、5 个 MCP server、若干 config patch。算下来本地有 70+ 项 AI 能力，散在四五个不同的目录、靠四五套不同的命令管。

每装一个都是因为要解决一个具体问题。装飞书 CLI 是因为要让 Codex 帮我建多维表格；装观远 BI 那套 skill 是因为要写 ETL；装小红书 agent 是因为要写小红书风格的标题；装 cursor MCP 是因为想给 Cursor 接外部数据。每装一个都很高兴，因为又多了一种"一句话就搞定的事"。

问题是，**没人告诉我现在哪些还在用、哪些不在用、哪些 token 烧得最多、哪些升级了我没装上**。

47 个 skill 里有多少是去年某个周末手痒装的、装完就没再用过的？我不知道。9 个 agent 里哪些是 ECC 来的、哪些是 agency-agents 来的、哪些是我自己写的？翻 frontmatter 才知道。装了 6 个月的 lark-cli 这周有没有发版本？打开 GitHub 看 release tag。某个 skill 把我上个月 30% 的 token 烧掉了？打开 `~/.claude/projects/*.jsonl` 自己写 jq 才能看出来。

这就是我作为重度用户的痛点。**装很容易，管很难。**

---

## 二、47 + 9 + 4 + 5 这些数字背后是钱和时间

把这事算笔账。

**Token 账。** 假设一个稍重度的 Claude Code 用户每月烧 1500 万 token。按 Sonnet 4.6 现价 $3/M input + $15/M output 混合估，月支出 $80-200 不等。问题是，**这 1500 万 token 是哪些 skill / agent 烧的？** 每个 skill 的 SYSTEM 段有几百到几千 token 的"长期占用"，47 个 skill 全装、每次对话都加载，光是 SYSTEM 段每次就要 3-5 万 token。如果有 12 个 skill 一年没碰过，把它们 stub 掉，每次对话省一两万 token，按一个月 1000 次对话算，月省 1500 万 token，混合价就是 $30 上下。

一年 $360。

**时间账。** 我每周大概要做这几件事：

- 翻 GitHub 看常用 CLI 有没有新版（飞书、观远、getnote 各看一下，5 分钟）
- 查某个新写的 skill 跑了几次（写个 ad-hoc 脚本拉 jsonl，10 分钟）
- 装新机器把所有 skill/agent/CLI 重装（45 分钟，每次都怀疑人生）
- 在 Codex / Claude Code / OpenCode 之间同步同一个 skill（手动 cp，每次 2 分钟）

合计每周 1 小时。一年 52 小时。

**认知账。** 这个不算钱，但最实在——打开新机器，看 `~/.claude/skills/` 里 47 个目录，**我已经认不清每个是干啥的了**。每次新装一个，都要先回忆"我之前那个干同样事的 skill 叫啥来着"，找不到就再装一个。本地能力栈无声膨胀。

**SaaS 厂商版本的问题更大**——他们花大力气推 CLI、推 skill 包、推 MCP server、推 agent persona，但**用户装上之后没人统计、没人召回、没人比对**，他们也不知道哪个能力被用、哪个被冷落。

---

## 三、三个证据：这不是个人怪癖，是大势所趋

**证据一：飞书 CLI 这周破万星。** 2026 年 3 月 28 日字节官方开源 [larksuite/cli](https://github.com/larksuite/cli)，5 月 14 日破 1 万颗 GitHub star，47 天均速 219 颗星/天。同期对照：钉钉 `dingtalk-workspace-cli` 1.8k 星、企微 `wecom-cli` 2k 星。飞书是国内办公套件第一个、目前唯一一个破万的。

更关键的不是 star 数。是飞书 CLI **本身就是一个 capability package**——它推的不是孤立 CLI，是一套打包：终端命令工具、配套的 `npx skills add larksuite/cli` skill 包、MCP 接入路径、auth scope 配置、`.lark-cli/` 本地 config 目录。**一个 SaaS 推一套全家桶给 Agent 用**，已经从"飞书一家在试"变成"所有 SaaS 都得跟"。详细分析见 [深耕多维表格的那篇文章](https://mp.weixin.qq.com/s/LzNys_UV4qxvJp2ALFMaHw)。

**证据二：ScaleKit 那个 CLI vs MCP benchmark。** 同模型同任务，CLI 比 MCP 便宜 4-32 倍，最极端的一组 1365 vs 44026 tokens。可靠性 CLI 25 次跑 100%，MCP 72%（剩下 7 次 TCP 超时）。结论是**CLI 路线在工程上被验证更优**，SaaS 厂商把能力打成 CLI 不只是赶时髦，是真省钱真稳定。所以这条路只会越走越多。但 MCP 也不会消失——它擅长"给 Agent 实时数据/工具"这类场景，CLI 擅长"在终端干活"，两者各有不可替代的位子。

**证据三：Anthropic 自家的 skills 生态在炸。** anthropics/skills 13 万星，awesome-claude-skills 系列加总 60 万+星。Skills 不是边缘概念，是 Claude Code 用户的第一入口。同期 agency-agents 这种 agent 内容池也在变成中文圈高频入口。

把三者放一起看，结论很清楚：**用户本地的 AI 能力正在膨胀成一个需要"control plane"的资产层**。一台 Mac 上装的 Skill、Agent、CLI、MCP server、Config，正在变成跟 Application、Document、Photo 一样需要被统一管理的资产类别。

---

## 四、现有工具帮不上忙的原因

挨家看一遍，原因都是同一个——**它们各自只覆盖 control plane 的一片**。

**[CC Switch](https://github.com/farion1231/cc-switch)（6.8 万星）** 国内做 Claude Code 工具最猛的项目，services 层 Rust 代码极其干净。但它**功能太杂**——6 种 CLI provider 切换 + API key 管理 + Skill 安装全塞一个 UI 里。它的 skill 管理是附属功能，没有用量统计，行内 toggle 也没有，新用户进来不知道从哪儿点。

**[Smithery](https://smithery.ai/)** MCP 那边的明星项目，Web 注册中心 + 安装器。但**它是 Web 的、它只管 MCP 这一类 component**——跟 Skill / Agent / CLI / Config 完全不打通。

**[skills-manage](https://github.com/iamzhihuix/skills-manage)（1814 星）/ [skills-manager](https://github.com/yibie/skills-manager)（152 星）** 都是 skill 类管理器。但**只管 skill 一类**，且 skills-manage 不是 Mac 原生质感、skills-manager 视觉偏标准控件、两者都没有 Usage Insights 和 Stub。

**[agent-skills-guard](https://github.com/bruc3van/agent-skills-guard)（354 星）** 只做安全扫描——它是安全工具，不是管理器。

**[Cherry Studio](https://github.com/CherryHQ/cherry-studio)** 大型 Electron LLM 聊天客户端，1000+ 内置助手。**它管聊天，不管本地资产**。

**手改 `claude_desktop_config.json` 党** 大多数高级用户的真实状态。装一个 MCP server 写一段 JSON，删一个 MCP server 删一段 JSON。没出错时挺好，出错对着 JSON 找半小时。普通用户根本不会写 JSON。

**每个 SaaS 自家的安装脚本** `npx @larksuite/cli@latest install`、`npx skills add larksuite/cli`、`curl ... | sh`、`brew install ...`。各管一摊，统一不起来。装得了，但**装了之后谁来统一管？**

横着看一遍，结论很明确——**没人站在「Skill + Agent + CLI + MCP + Config 五类 component + Mac 原生 + 用量统计 + 资产视角」这个十字路口上**。

---

## 五、popskill 的回答：asset control plane

popskill 不是又一个 skill 商店。它的底层模型是**本地 AI 能力的资产控制平面**（asset control plane）。

核心抽象是一条五层链路：

```
source -> package -> component -> deployment -> runtime
```

- **Source**：能力从哪儿来——local folder / Git repo / ZIP / registry / MCP endpoint
- **Package**：用户面对的安装/更新单元——飞书包、PDF 包、单个 skill 包
- **Component**：包里的具体能力，**7 类**：skill / CLI / MCP server / agent / rule / prompt / config
- **Deployment**：component 投射到目标 AI 工具的方式——copy / configPatch / wrapper / symlink
- **Runtime**：可执行体或长驻进程——CLI / MCP server / agent sidecar

完整契约看 [docs/asset-control-plane.md](./asset-control-plane.md)。

这个模型解决了一件事：**一个 SaaS 推的"飞书 CLI"不再被拆成 4 个独立条目（CLI 一个、配套 skill 一个、MCP 一个、config 一个）**，而是一个 Package，里面有 4 个 Component。用户面对的是"我装了飞书"这一件事，不是"我装了飞书的 4 个分散东西"。卸载也是一键卸载 Package，4 类 component 全清理，不留尾巴。

外在体感是 Mac App Store——Mac 原生 SwiftUI、Surge 风格设计语言、Library 行内 toggle、Insights 页全网独家用量统计、Stub 状态（60 天没用的本地清掉留卡片）、WebDAV 跨设备同步、AgentShield 安装后立即扫描。

不抢的赛道也写在 README 里：不做 LLM 聊天客户端（Cherry Studio 已经做了）、不做 MCP 注册中心（Anthropic MCP Registry 是上游 DNS）、不做 skill 创作工具（v1 只做"消费者端"）。

---

## 六、它会服务谁

**画像一：我自己（重度用户）。**

本地 47+ skill / 9+ agent / 5+ CLI / 5+ MCP server。每周花 1 小时在装/找/切/升级上。一年 $360 在不必要的 token 上。换新机器要 45 分钟重建环境。

popskill 给我的价值：把这 1 小时压到 5 分钟、把 $360 砍到 $50、把 45 分钟压到 5 分钟（WebDAV 同步过来一键 rehydrate）。

**画像二：刚听说 Skills 的中级用户。**

听了一耳朵 Claude Code、看了《飞书 CLI 破万星》那篇、想知道"我要不要也装一下"。打开 GitHub 一搜，47 个 awesome-list，每个 50 个 skill 推荐，**完全不知道从哪儿下手**。

popskill 给他的价值：Discover 页有 Editor's Pick + Top Charts + Curated for You，跟 Mac App Store 一样可以瞎逛。逛着装上 5 个 Package，用一段时间，Insights 页告诉他哪些真用上了。

**画像三：SaaS 厂商（v2 之后）。**

飞书、观远、Notion、Cursor、Figma，他们花大力气推自家的 capability package，但**装机率/激活率/调用频次/留存这些数据他们看不到**。

popskill 给他们的价值：如果未来装机量起来，可以做"开发者后台"——以 opt-in 聚合数据让 SaaS 厂商看到他们家 Package 的用量分布（聚合数据、不识别个人）。这是 v2 之后的事，但是赛道。

---

## 七、为啥是 2026 年这个时间点

最后一个判断题：为啥不是 2025 年，也不是 2027 年。

**2025 年还早。** Skills 协议是 2025 才稳的，CC Switch 是 2025 下半年起势。Capability package 这个概念还没成型——飞书 CLI 今年 3 月才开源，钉钉企微的 CLI 还在迭代早期，Anthropic MCP Registry 刚立项。生态密度不够，做 control plane 没东西管。

**2027 年就晚。** 那时候要么有人做出来了（最可能是 CC Switch 把 Library 那块单独剥出来做 App Store 体验，或者字节自己出个本地客户端），要么用户已经习惯"手动管"——形成路径依赖之后再换成本就高了。Mac App Store 当年抢的就是 2011 年那个时间点，再晚两年苹果都没机会让大多数应用从直接下载切到 App Store 渠道。

**2026 年是窗口。** Capability package 刚刚成主流（飞书破万就是发令枪），用户本地能力数刚从十几个跨到几十几百个、痛点开始具象化，但还没有任何一家做出"asset control plane + Mac native + App Store 级 UX"的组合——CC Switch 走的是工程师工具路线、Smithery 走的是 Web 路线、skills-manage 这类只覆盖 skill 单类、各家自家脚本各自为政。

时间窗口大概是 4-8 个月。这就是 2026 年这个时间点动手的原因。

---

## 写在最后

popskill 不是个简单的"再搞个 skill 商店"。

它的底层判断是：**本地 AI 能力正在膨胀成一类基础设施，需要一个统一的 asset control plane 来管。** 飞书 CLI 破万星证明了 capability package 已成主流，CC Switch 6.8 万星证明了用户对"集中管理"是有需求的，Anthropic MCP Registry 立项证明了上游基础设施在搭，但没人站在「Mac 原生 + 5 类 component + App Store UX + 使用统计」的交汇处。

popskill 想站在那里。

如果你也是本地装了 30+ skill / 5+ agent / 5+ CLI / 5+ MCP server 的人、如果你也对着 `claude_desktop_config.json` 写 JSON 写到怀疑人生、如果你也想知道你那 $200 月度 token 账单到底烧在了哪几个能力上——这工具是给你做的。

仓库：[maojiebc/majia-Popskill](https://github.com/maojiebc/majia-Popskill)
当前状态：v0.3 self-use iteration in progress，参考 [README.md](../README.md) 的「Current stage」段
有想法，Issues 见。
