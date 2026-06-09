import Foundation

// 原型样例数据（popskill-data.jsx 1:1 翻译）— POPSKILL_FAKE_DATA=1 时加载。
// 覆盖全部状态组合，供开发期 fixture 与设计稿像素比对。

enum Fixtures {
    static func make() -> ([Tool], [Entry]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tools = [
            Tool(id: "claude", name: "Claude Code", root: home.appendingPathComponent(".claude"), connected: true, defaultTarget: true),
            Tool(id: "codex", name: "Codex CLI", root: home.appendingPathComponent(".codex"), connected: true, defaultTarget: true),
        ]

        func cap(_ id: String, _ name: String, _ type: CapType, _ desc: String, _ version: String,
                 _ author: String, _ tokens: Int, _ claude: LinkStatus, _ codex: LinkStatus,
                 cause: String? = nil) -> Capability {
            var c = Capability(id: id, name: name, type: type, desc: desc, version: version,
                               author: author, tokens: tokens, dirURL: URL(fileURLWithPath: "/tmp/\(name)"))
            c.links = ["claude": claude, "codex": codex]
            if let cause {
                if claude == .broken { c.brokenCause["claude"] = cause }
                if codex == .broken { c.brokenCause["codex"] = cause }
            }
            return c
        }

        func bundle(_ id: String, _ desc: String, _ version: String, latest: String? = nil,
                    autoUpdate: Bool = false, _ author: String, _ sourceUrl: String, _ tokens: Int,
                    _ children: [Capability]) -> Entry {
            var head = Capability(id: id, name: id, type: .bundle, desc: desc, version: version,
                                  author: author, tokens: tokens, dirURL: URL(fileURLWithPath: "/tmp/\(id)"))
            head.links = [:]
            return Entry(id: id, cap: head, children: children, sourceUrl: sourceUrl, latest: latest, autoUpdate: autoUpdate)
        }

        func standalone(_ id: String, _ type: CapType, _ desc: String, _ version: String,
                        latest: String? = nil, _ author: String, _ tokens: Int,
                        _ claude: LinkStatus, _ codex: LinkStatus, _ sourceUrl: String,
                        autoUpdate: Bool = false, cause: String? = nil) -> Entry {
            Entry(id: id, cap: cap(id, id, type, desc, version, author, tokens, claude, codex, cause: cause),
                  children: nil, sourceUrl: sourceUrl, latest: latest, autoUpdate: autoUpdate)
        }

        let entries: [Entry] = [
            bundle("feishu-suite", "飞书全家桶 · 1 CLI + 1 MCP + 6 项 skill", "1.2.0", latest: "1.3.0",
                   autoUpdate: true, "feishu", "github.com/feishu/lark-suite", 412_800, [
                cap("fs-lark-cli", "lark-cli", .cli, "飞书官方命令行", "2.4.0", "feishu", 0, .on, .on),
                cap("fs-mcp", "feishu-mcp", .mcp, "飞书 OpenAPI 接入", "0.3.1", "feishu", 24800, .on, .off),
                cap("fs-doc", "doc-skill", .skill, "云文档读写 + 摘要", "1.0.0", "feishu", 18200, .on, .on),
                cap("fs-cal", "calendar-skill", .skill, "日程 / 会议室检索", "1.0.0", "feishu", 8400, .on, .on),
                cap("fs-base", "base-skill", .skill, "多维表格 SQL-ish", "1.0.0", "feishu", 22600, .on, .on),
                cap("fs-msg", "message-skill", .skill, "群聊消息推送", "1.0.0", "feishu", 9400, .on, .on),
                cap("fs-approval", "approval-skill", .skill, "审批流单据", "0.9.0", "feishu", 6800, .on, .off),
                cap("fs-base-agent", "base-analyst", .agent, "多维表格分析师 persona", "0.4.0", "feishu", 14200, .stub, .off),
            ]),
            bundle("baoyu-collection", "宝玉的提示词宇宙 · 7 项 skill", "2.4.1", latest: "2.5.0",
                   "@dotey", "github.com/dotey/prompt-engineering", 386_100, [
                cap("by-comic", "baoyu-comic", .skill, "四格漫画 prompt", "2.4.1", "@dotey", 184_320, .on, .on),
                cap("by-translate", "baoyu-translate", .skill, "中英对照翻译 + 注释", "1.8.2", "@dotey", 62400, .on, .on),
                cap("by-summarize", "baoyu-summarize", .skill, "长文三段式摘要", "1.5.0", "@dotey", 41200, .on, .on),
                cap("by-rewrite", "wechat-rewrite", .skill, "公众号文风润色", "1.2.0", "@dotey", 12808, .on, .on),
                cap("by-podcast", "podcast-script", .skill, "音频脚本生成", "0.7.0", "@dotey", 18400, .on, .stub),
                cap("by-redbook", "xhs-style", .skill, "小红书爆款语气", "0.6.0", "@dotey", 9200, .stub, .off),
                cap("by-review", "design-review", .skill, "UI 评审 checklist", "1.1.0", "@dotey", 47800, .on, .broken, cause: "校验失败"),
            ]),
            bundle("guanyuan-bi", "观远 BI · npm 包 · 1 CLI + 4 项 skill", "3.1.0",
                   autoUpdate: true, "guandata", "npm:@guandata/bi-suite", 96400, [
                cap("gy-cli", "guanyuan-cli", .cli, "BI 项目脚手架 + 部署", "3.1.0", "guandata", 0, .on, .on),
                cap("gy-sql", "sql-query", .skill, "自然语言 → SQL", "2.0.0", "guandata", 38200, .on, .on),
                cap("gy-dashboard", "dashboard-author", .skill, "看板搭建 prompt", "1.4.0", "guandata", 22800, .on, .on),
                cap("gy-chart", "chart-recommend", .skill, "数据 → 图表类型建议", "1.2.0", "guandata", 18400, .on, .stub),
                cap("gy-report", "data-report", .skill, "周报 / 月报自动撰写", "1.0.0", "guandata", 17000, .on, .off),
            ]),
            standalone("op7418-design-review", .skill, "歸藏的 UI 评审 prompt", "1.8.0", "@op7418", 92110, .on, .off, "github.com/op7418/design-review"),
            standalone("excalidraw-sketch", .skill, "白板手绘 prompt", "0.9.3", "majia", 31044, .on, .on, "~/work/my-skills/excalidraw-sketch"),
            standalone("ppt-generator", .skill, "PPTX 大纲 → 编辑稿", "3.0.0", "majia", 220_500, .on, .stub, "~/work/my-skills/ppt-generator"),
            standalone("xhs-cover", .skill, "小红书封面文案", "0.6.0", "majia", 8420, .stub, .off, "~/work/my-skills/xhs-cover"),
            standalone("code-reviewer", .agent, "Senior 代码评审 persona", "1.4.0", "anthropic", 154_200, .on, .on, "github.com/anthropics/claude-skills", autoUpdate: true),
            standalone("pm-spec-writer", .agent, "PRD 起草 agent", "0.7.2", "majia", 47800, .on, .broken, "~/work/my-skills/pm-spec-writer", cause: "断链"),
            standalone("data-analyst", .agent, "SQL + 图表分析师", "2.1.0", "community", 88200, .on, .on, "github.com/community/data-analyst"),
            standalone("gh", .cli, "GitHub 官方 CLI", "2.62.0", "github", 0, .on, .on, "github.com/cli/cli", autoUpdate: true),
            standalone("ripgrep", .cli, "rg — 高性能搜索", "14.1.0", "burntsushi", 0, .on, .on, "github.com/BurntSushi/ripgrep", autoUpdate: true),
            standalone("fd-find", .cli, "现代化 find 替代品", "10.2.0", "sharkdp", 0, .on, .on, "github.com/sharkdp/fd", autoUpdate: true),
            standalone("mcp-fetch", .mcp, "HTTP 抓取服务", "0.4.2", "modelcontextprotocol", 22400, .on, .on, "npm:@modelcontextprotocol/server-fetch", autoUpdate: true),
            standalone("mcp-filesystem", .mcp, "本地文件读写", "0.5.0", "modelcontextprotocol", 18200, .on, .on, "npm:@modelcontextprotocol/server-filesystem", autoUpdate: true),
            standalone("mcp-puppeteer", .mcp, "浏览器自动化", "0.3.1", "modelcontextprotocol", 41200, .on, .off, "npm:@modelcontextprotocol/server-puppeteer"),
            standalone("linear-mcp", .mcp, "Linear issue 接入", "1.0.0", "linear", 6400, .off, .on, "npm:@linear/mcp"),
            standalone("context7", .mcp, "实时文档检索", "1.7.0", latest: "1.8.0", "upstash", 28800, .on, .on, "npm:@upstash/context7-mcp"),
        ]

        return (tools, entries)
    }
}
