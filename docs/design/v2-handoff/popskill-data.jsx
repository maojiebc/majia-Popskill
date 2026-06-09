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

Object.assign(window, { makeInitialState, psIsBundle, psAllCaps, psAgg, psStats, psIssues, psUpdates, psSourceKind });
