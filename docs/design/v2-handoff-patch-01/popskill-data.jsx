// popskill-data.jsx — 数据层（v2 瘦身版）
// 统一为一个 entries 数组：每个条目 = 一个「已添加的源」(AddedSource)。
//   - 套装条目带 children（子能力数组）
//   - 独立能力条目自身就是能力（带 claude/codex 状态）
// LinkStatus: "on" | "off" | "stub" | "broken"
// broken 的能力带 brokenCause: "断链" | "源失联" | "校验失败"
// latest 字段存在且 ≠ version ⇒ 该源可更新。

function makeInitialState() {
  return {
    tools: [
      { id: "claude", name: "Claude Code", root: "~/.claude/", connected: true, defaultTarget: true },
      { id: "codex",  name: "Codex CLI",   root: "~/.codex/",  connected: true, defaultTarget: true },
    ],
    entries: [
      // ── 套装 ──────────────────────────────────────────
      {
        id: "feishu-suite", name: "feishu-suite", type: "Bundle", author: "feishu",
        desc: "飞书全家桶 · 1 CLI + 1 MCP + 6 项 skill",
        version: "1.2.0", latest: "1.3.0", autoUpdate: true,
        sourceUrl: "github.com/feishu/lark-suite", tokens: 412800,
        children: [
          { id: "fs-lark-cli",   name: "lark-cli",       type: "CLI",   desc: "飞书官方命令行",        version: "2.4.0", author: "feishu", tokens: 0,     claude: "on",   codex: "on"  },
          { id: "fs-mcp",        name: "feishu-mcp",     type: "MCP",   desc: "飞书 OpenAPI 接入",     version: "0.3.1", author: "feishu", tokens: 24800, claude: "on",   codex: "off" },
          { id: "fs-doc",        name: "doc-skill",      type: "Skill", desc: "云文档读写 + 摘要",     version: "1.0.0", author: "feishu", tokens: 18200, claude: "on",   codex: "on"  },
          { id: "fs-cal",        name: "calendar-skill", type: "Skill", desc: "日程 / 会议室检索",     version: "1.0.0", author: "feishu", tokens: 8400,  claude: "on",   codex: "on"  },
          { id: "fs-base",       name: "base-skill",     type: "Skill", desc: "多维表格 SQL-ish",      version: "1.0.0", author: "feishu", tokens: 22600, claude: "on",   codex: "on"  },
          { id: "fs-msg",        name: "message-skill",  type: "Skill", desc: "群聊消息推送",          version: "1.0.0", author: "feishu", tokens: 9400,  claude: "on",   codex: "on"  },
          { id: "fs-approval",   name: "approval-skill", type: "Skill", desc: "审批流单据",            version: "0.9.0", author: "feishu", tokens: 6800,  claude: "on",   codex: "off" },
          { id: "fs-base-agent", name: "base-analyst",   type: "Agent", desc: "多维表格分析师 persona", version: "0.4.0", author: "feishu", tokens: 14200, claude: "stub", codex: "off" },
        ],
      },
      {
        id: "baoyu-collection", name: "baoyu-collection", type: "Bundle", author: "@dotey",
        desc: "宝玉的提示词宇宙 · 7 项 skill",
        version: "2.4.1", latest: "2.5.0", autoUpdate: false,
        sourceUrl: "github.com/dotey/prompt-engineering", tokens: 386100,
        children: [
          { id: "by-comic",     name: "baoyu-comic",     type: "Skill", desc: "四格漫画 prompt",     version: "2.4.1", author: "@dotey", tokens: 184320, claude: "on",   codex: "on"  },
          { id: "by-translate", name: "baoyu-translate", type: "Skill", desc: "中英对照翻译 + 注释", version: "1.8.2", author: "@dotey", tokens: 62400,  claude: "on",   codex: "on"  },
          { id: "by-summarize", name: "baoyu-summarize", type: "Skill", desc: "长文三段式摘要",      version: "1.5.0", author: "@dotey", tokens: 41200,  claude: "on",   codex: "on"  },
          { id: "by-rewrite",   name: "wechat-rewrite",  type: "Skill", desc: "公众号文风润色",      version: "1.2.0", author: "@dotey", tokens: 12808,  claude: "on",   codex: "on"  },
          { id: "by-podcast",   name: "podcast-script",  type: "Skill", desc: "音频脚本生成",        version: "0.7.0", author: "@dotey", tokens: 18400,  claude: "on",   codex: "stub" },
          { id: "by-redbook",   name: "xhs-style",       type: "Skill", desc: "小红书爆款语气",      version: "0.6.0", author: "@dotey", tokens: 9200,   claude: "stub", codex: "off" },
          { id: "by-review",    name: "design-review",   type: "Skill", desc: "UI 评审 checklist",   version: "1.1.0", author: "@dotey", tokens: 47800,  claude: "on",   codex: "broken", brokenCause: "校验失败" },
        ],
      },
      {
        id: "guanyuan-bi", name: "guanyuan-bi", type: "Bundle", author: "guandata",
        desc: "观远 BI · npm 包 · 1 CLI + 4 项 skill",
        version: "3.1.0", autoUpdate: true,
        sourceUrl: "npm:@guandata/bi-suite", tokens: 96400,
        children: [
          { id: "gy-cli",       name: "guanyuan-cli",     type: "CLI",   desc: "BI 项目脚手架 + 部署", version: "3.1.0", author: "guandata", tokens: 0,     claude: "on", codex: "on"  },
          { id: "gy-sql",       name: "sql-query",        type: "Skill", desc: "自然语言 → SQL",       version: "2.0.0", author: "guandata", tokens: 38200, claude: "on", codex: "on"  },
          { id: "gy-dashboard", name: "dashboard-author", type: "Skill", desc: "看板搭建 prompt",      version: "1.4.0", author: "guandata", tokens: 22800, claude: "on", codex: "on"  },
          { id: "gy-chart",     name: "chart-recommend",  type: "Skill", desc: "数据 → 图表类型建议",  version: "1.2.0", author: "guandata", tokens: 18400, claude: "on", codex: "stub" },
          { id: "gy-report",    name: "data-report",      type: "Skill", desc: "周报 / 月报自动撰写",  version: "1.0.0", author: "guandata", tokens: 17000, claude: "on", codex: "off" },
        ],
      },

      // ── 独立能力（每条即一个源）────────────────────────
      { id: "op7418-design-review", name: "op7418-design-review", type: "Skill", desc: "歸藏的 UI 评审 prompt", version: "1.8.0", author: "@op7418", tokens: 92110, claude: "on",  codex: "off", sourceUrl: "github.com/op7418/design-review", autoUpdate: false },
      { id: "excalidraw-sketch",    name: "excalidraw-sketch",    type: "Skill", desc: "白板手绘 prompt",       version: "0.9.3", author: "majia",   tokens: 31044, claude: "on",  codex: "on",  sourceUrl: "~/work/my-skills/excalidraw-sketch", autoUpdate: false },
      { id: "ppt-generator",        name: "ppt-generator",        type: "Skill", desc: "PPTX 大纲 → 编辑稿",    version: "3.0.0", author: "majia",   tokens: 220500, claude: "on", codex: "stub", sourceUrl: "~/work/my-skills/ppt-generator", autoUpdate: false },
      { id: "xhs-cover",            name: "xhs-cover",            type: "Skill", desc: "小红书封面文案",        version: "0.6.0", author: "majia",   tokens: 8420,  claude: "stub", codex: "off", sourceUrl: "~/work/my-skills/xhs-cover", autoUpdate: false },
      { id: "code-reviewer",        name: "code-reviewer",        type: "Agent", desc: "Senior 代码评审 persona", version: "1.4.0", author: "anthropic", tokens: 154200, claude: "on", codex: "on", sourceUrl: "github.com/anthropics/claude-skills", autoUpdate: true },
      { id: "pm-spec-writer",       name: "pm-spec-writer",       type: "Agent", desc: "PRD 起草 agent",        version: "0.7.2", author: "majia",   tokens: 47800, claude: "on",  codex: "broken", brokenCause: "断链", sourceUrl: "~/work/my-skills/pm-spec-writer", autoUpdate: false },
      { id: "data-analyst",         name: "data-analyst",         type: "Agent", desc: "SQL + 图表分析师",      version: "2.1.0", author: "community", tokens: 88200, claude: "on", codex: "on", sourceUrl: "github.com/community/data-analyst", autoUpdate: false },
      { id: "gh",                   name: "gh",                   type: "CLI",   desc: "GitHub 官方 CLI",       version: "2.62.0", author: "github",  tokens: 0,     claude: "on",  codex: "on", sourceUrl: "github.com/cli/cli", autoUpdate: true },
      { id: "ripgrep",              name: "ripgrep",              type: "CLI",   desc: "rg — 高性能搜索",       version: "14.1.0", author: "burntsushi", tokens: 0,  claude: "on",  codex: "on", sourceUrl: "github.com/BurntSushi/ripgrep", autoUpdate: true },
      { id: "fd-find",              name: "fd-find",              type: "CLI",   desc: "现代化 find 替代品",    version: "10.2.0", author: "sharkdp", tokens: 0,     claude: "on",  codex: "on", sourceUrl: "github.com/sharkdp/fd", autoUpdate: true },
      { id: "mcp-fetch",            name: "mcp-fetch",            type: "MCP",   desc: "HTTP 抓取服务",         version: "0.4.2", author: "modelcontextprotocol", tokens: 22400, claude: "on", codex: "on", sourceUrl: "npm:@modelcontextprotocol/server-fetch", autoUpdate: true },
      { id: "mcp-filesystem",       name: "mcp-filesystem",       type: "MCP",   desc: "本地文件读写",          version: "0.5.0", author: "modelcontextprotocol", tokens: 18200, claude: "on", codex: "on", sourceUrl: "npm:@modelcontextprotocol/server-filesystem", autoUpdate: true },
      { id: "mcp-puppeteer",        name: "mcp-puppeteer",        type: "MCP",   desc: "浏览器自动化",          version: "0.3.1", author: "modelcontextprotocol", tokens: 41200, claude: "on", codex: "off", sourceUrl: "npm:@modelcontextprotocol/server-puppeteer", autoUpdate: false },
      { id: "linear-mcp",           name: "linear-mcp",           type: "MCP",   desc: "Linear issue 接入",     version: "1.0.0", author: "linear",  tokens: 6400,  claude: "off", codex: "on", sourceUrl: "npm:@linear/mcp", autoUpdate: false },
      { id: "context7",             name: "context7",             type: "MCP",   desc: "实时文档检索",          version: "1.7.0", latest: "1.8.0", author: "upstash", tokens: 28800, claude: "on", codex: "on", sourceUrl: "npm:@upstash/context7-mcp", autoUpdate: false },
    ],
  };
}

// ── 选择器（全部从 entries 派生，无第二份真相）────────────

function psIsBundle(e) { return e.type === "Bundle" && Array.isArray(e.children); }

// 全部能力（独立 + 套装子项）
function psAllCaps(entries) {
  return entries.flatMap(e => (psIsBundle(e) ? e.children : [e]));
}

// 套装在某工具侧的聚合
function psAgg(children, key) {
  const counts = { total: children.length, on: 0, off: 0, stub: 0, broken: 0 };
  children.forEach(c => { counts[c[key]] = (counts[c[key]] || 0) + 1; });
  return counts;
}

// 头部统计
function psStats(entries) {
  const caps = psAllCaps(entries);
  return {
    bundles: entries.filter(psIsBundle).length,
    standalone: entries.filter(e => !psIsBundle(e)).length,
    total: caps.length,
    claudeOn: caps.filter(c => c.claude === "on").length,
    codexOn:  caps.filter(c => c.codex  === "on").length,
    stubs:    caps.reduce((n, c) => n + (c.claude === "stub") + (c.codex === "stub"), 0),
    broken:   caps.reduce((n, c) => n + (c.claude === "broken") + (c.codex === "broken"), 0),
    symlinks: caps.reduce((n, c) => n + (c.claude === "on") + (c.codex === "on"), 0),
  };
}

// 链接问题清单（每个 broken 单元格一条）
function psIssues(entries) {
  const out = [];
  entries.forEach(e => {
    const caps = psIsBundle(e) ? e.children : [e];
    caps.forEach(c => {
      ["claude", "codex"].forEach(tool => {
        if (c[tool] === "broken") out.push({
          capId: c.id, capName: c.name, tool,
          cause: c.brokenCause || "断链",
          entryId: e.id, entryName: e.name,
          sourceUrl: e.sourceUrl,
          latest: e.latest && e.latest !== e.version ? e.latest : null,
        });
      });
    });
  });
  return out;
}

// 可更新的源
function psUpdates(entries) {
  return entries.filter(e => e.latest && e.latest !== e.version);
}

// URL → 来源种类
function psSourceKind(url) {
  if (!url) return "local";
  if (url.startsWith("npm:")) return "npm";
  if (url.startsWith("~") || url.startsWith("/")) return "local";
  return "github";
}

// ── SKILL.md / README 开头摘要（安装时从源文档提取，原型为静态样例）──
const psReadmes = {
  "fs-lark-cli":   "二进制 CLI，无 SKILL.md。提供 lark auth / lark docs / lark im 等子命令，首次使用需 lark auth login 完成 OAuth。",
  "fs-mcp":        "接入飞书 OpenAPI 的 MCP server。暴露 doc.read / doc.write / im.send 等 14 个工具，需要在环境变量配置 app_id / app_secret。",
  "fs-doc":        "云文档读写技能：按 URL 拉取文档转 Markdown，支持在指定标题下追加内容与生成全文摘要；大于 50k token 的文档自动分段。",
  "fs-cal":        "日程技能：查空闲 / 订会议室 / 拉取与会人本周日程；输出统一为表格，冲突时给出候选时段。",
  "fs-base":       "多维表格技能：用类 SQL 语法查询/聚合 Base 表，支持 join 视图与批量写入；写操作默认 dry-run。",
  "fs-msg":        "群聊消息技能：按群名/群 ID 推送富文本卡片，支持 @成员与定时发送；附带消息模板库。",
  "fs-approval":   "审批流技能：读取待办审批、草拟单据、追踪审批进度；提交类操作需二次确认。",
  "fs-base-agent": "多维表格分析师 persona：拿到表链接后自动识别字段类型、生成分析计划并输出结论 + 图表建议。依赖 base-skill。",
  "by-comic":      "四格漫画 prompt：输入一个概念或对话，输出分镜脚本 + 画面描述，附风格参考图库；适合配合生图模型使用。",
  "by-translate":  "中英对照翻译：逐段对照 + 术语表 + 译注，专有名词首次出现时保留原文；适合技术文章与论文。",
  "by-summarize":  "长文三段式摘要：一句话结论 → 三点论据 → 关键引文；超过 30k token 自动分块归并。",
  "by-rewrite":    "公众号文风润色：口语化、短句、小标题分段，保留原意不改事实；附标题党检测清单。",
  "by-podcast":    "音频脚本生成：把文章/大纲转双人对谈脚本，含语气标注与时长估算；支持指定主持人设。",
  "by-redbook":    "小红书爆款语气：标题 + 正文 + 话题标签三件套，emoji 密度与句长有硬性规则；附 20 个爆款案例。",
  "by-review":     "UI 评审 checklist：按层级（布局/密度/对比/可达性）逐项检查截图，输出问题清单 + 修改建议，附评分标准。",
  "gy-cli":        "二进制 CLI，无 SKILL.md。提供 gy init / gy deploy / gy datasource 等子命令，面向观远 BI 项目脚手架与部署。",
  "gy-sql":        "自然语言转 SQL：结合数据字典生成可执行查询，输出前先跱列出用到的表与字段；默认 LIMIT 1000。",
  "gy-dashboard":  "看板搭建 prompt：按业务问题推导指标体系 → 生成看板结构 JSON；适配观远看板 DSL。",
  "gy-chart":      "图表类型建议：根据字段类型与基数推荐图表，给出反例警告（饼图>6类、双轴滥用等）。",
  "gy-report":     "周报/月报撰写：拉取指定看板数据，按「结论先行 + 异动归因」模板生成报告；支持对比上期。",
  "op7418-design-review": "歸藏的 UI 评审 prompt：先判断设计意图，再从层级/间距/色彩/文案四轴逐项评分，输出可直接执行的修改建议；附大量好/坏对比案例。",
  "excalidraw-sketch": "白板手绘 prompt：把概念/架构描述转成 Excalidraw JSON，手绘风格，支持分组与连线语义；生成后可直接粘贴到 excalidraw.com。",
  "ppt-generator": "PPTX 生成：大纲 → 逐页讲稿 + 版式建议 → 调用脚本输出可编辑 .pptx；内置三套版式主题，支持品牌色替换。",
  "xhs-cover":     "小红书封面文案：主标题≤10字 + 副标题带钩子，输出 5 组候选 + 字体排版建议。",
  "code-reviewer": "Senior 代码评审 persona：先理解变更意图再逐文件评审，区分 blocking / nit；覆盖安全、性能、可读性三类规则，附各语言专项 checklist。",
  "pm-spec-writer": "PRD 起草 agent：七步引导（背景 → 目标 → 非目标 → 方案 → 边界 → 指标 → 发布计划）把模糊想法收敛为可评审的 PRD；内置模板与反例库。",
  "data-analyst":  "SQL + 图表分析师：探索性提问 → 生成查询 → 解读结果 → 给出下一步假设；输出始终区分「事实」与「推断」。",
  "gh":            "GitHub 官方 CLI，无 SKILL.md。gh pr / gh issue / gh run 等子命令覆盖完整 GitHub 工作流；首次使用需 gh auth login。",
  "ripgrep":       "二进制 CLI，无 SKILL.md。rg — 高性能正则搜索，默认遵守 .gitignore，是 agent 检索代码库的事实标准工具。",
  "fd-find":       "二进制 CLI，无 SKILL.md。fd — 现代化 find：直觉语法、默认忽略隐藏文件与 .gitignore，速度快一个量级。",
  "mcp-fetch":     "HTTP 抓取 MCP server：fetch 工具拉取网页并转 Markdown，支持分页与内容截断控制；适合联网检索场景。",
  "mcp-filesystem": "本地文件读写 MCP server：read/write/list/search 工具，可配置允许访问的目录白名单；越界访问直接拒绝。",
  "mcp-puppeteer": "浏览器自动化 MCP server：导航/截图/点击/表单填写，基于无头 Chromium；适合端到端验证与抓取动态页面。",
  "linear-mcp":    "Linear 接入 MCP server：查询/创建/更新 issue，支持按周期与标签过滤；需要 LINEAR_API_KEY。",
  "context7":      "实时文档检索 MCP server：按库名 + 版本拉取最新官方文档片段注入上下文，避免模型用过时 API 写代码。",
};
function psReadme(id) { return psReadmes[id] || null; }

Object.assign(window, { makeInitialState, psIsBundle, psAllCaps, psAgg, psStats, psIssues, psUpdates, psSourceKind, psReadme });
