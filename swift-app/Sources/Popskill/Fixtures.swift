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
            return Entry(id: id, cap: head, children: children, bundleKind: .directory,
                         sourceUrl: sourceUrl, latest: latest, autoUpdate: autoUpdate)
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

        // PATCH-01：capId → 文档摘要（psReadmes 1:1 翻译）
        let withReadmes = entries.map { e -> Entry in
            var e = e
            e.cap.readme = readmes[e.cap.id]
            e.children = e.children?.map { c in
                var c = c
                c.readme = readmes[c.id]
                return c
            }
            return e
        }
        return (tools, withReadmes)
    }

    static let readmes: [String: String] = [
        "fs-lark-cli": "二进制 CLI，无 SKILL.md。提供 lark auth / lark docs / lark im 等子命令，首次使用需 lark auth login 完成 OAuth。",
        "fs-mcp": "接入飞书 OpenAPI 的 MCP server。暴露 doc.read / doc.write / im.send 等 14 个工具，需要在环境变量配置 app_id / app_secret。",
        "fs-doc": "云文档读写技能：按 URL 拉取文档转 Markdown，支持在指定标题下追加内容与生成全文摘要；大于 50k token 的文档自动分段。",
        "fs-cal": "日程技能：查空闲 / 订会议室 / 拉取与会人本周日程；输出统一为表格，冲突时给出候选时段。",
        "fs-base": "多维表格技能：用类 SQL 语法查询/聚合 Base 表，支持 join 视图与批量写入；写操作默认 dry-run。",
        "fs-msg": "群聊消息技能：按群名/群 ID 推送富文本卡片，支持 @成员与定时发送；附带消息模板库。",
        "fs-approval": "审批流技能：读取待办审批、草拟单据、追踪审批进度；提交类操作需二次确认。",
        "fs-base-agent": "多维表格分析师 persona：拿到表链接后自动识别字段类型、生成分析计划并输出结论 + 图表建议。依赖 base-skill。",
        "by-comic": "四格漫画 prompt：输入一个概念或对话，输出分镜脚本 + 画面描述，附风格参考图库；适合配合生图模型使用。",
        "by-translate": "中英对照翻译：逐段对照 + 术语表 + 译注，专有名词首次出现时保留原文；适合技术文章与论文。",
        "by-summarize": "长文三段式摘要：一句话结论 → 三点论据 → 关键引文；超过 30k token 自动分块归并。",
        "by-rewrite": "公众号文风润色：口语化、短句、小标题分段，保留原意不改事实；附标题党检测清单。",
        "by-podcast": "音频脚本生成：把文章/大纲转双人对谈脚本，含语气标注与时长估算；支持指定主持人设。",
        "by-redbook": "小红书爆款语气：标题 + 正文 + 话题标签三件套，emoji 密度与句长有硬性规则；附 20 个爆款案例。",
        "by-review": "UI 评审 checklist：按层级（布局/密度/对比/可达性）逐项检查截图，输出问题清单 + 修改建议，附评分标准。",
        "gy-cli": "二进制 CLI，无 SKILL.md。提供 gy init / gy deploy / gy datasource 等子命令，面向观远 BI 项目脚手架与部署。",
        "gy-sql": "自然语言转 SQL：结合数据字典生成可执行查询，输出前先列出用到的表与字段；默认 LIMIT 1000。",
        "gy-dashboard": "看板搭建 prompt：按业务问题推导指标体系 → 生成看板结构 JSON；适配观远看板 DSL。",
        "gy-chart": "图表类型建议：根据字段类型与基数推荐图表，给出反例警告（饼图>6类、双轴滥用等）。",
        "gy-report": "周报/月报撰写：拉取指定看板数据，按「结论先行 + 异动归因」模板生成报告；支持对比上期。",
        "op7418-design-review": "歸藏的 UI 评审 prompt：先判断设计意图，再从层级/间距/色彩/文案四轴逐项评分，输出可直接执行的修改建议；附大量好/坏对比案例。",
        "excalidraw-sketch": "白板手绘 prompt：把概念/架构描述转成 Excalidraw JSON，手绘风格，支持分组与连线语义；生成后可直接粘贴到 excalidraw.com。",
        "ppt-generator": "PPTX 生成：大纲 → 逐页讲稿 + 版式建议 → 调用脚本输出可编辑 .pptx；内置三套版式主题，支持品牌色替换。",
        "xhs-cover": "小红书封面文案：主标题≤10字 + 副标题带钩子，输出 5 组候选 + 字体排版建议。",
        "code-reviewer": "Senior 代码评审 persona：先理解变更意图再逐文件评审，区分 blocking / nit；覆盖安全、性能、可读性三类规则，附各语言专项 checklist。",
        "pm-spec-writer": "PRD 起草 agent：七步引导（背景 → 目标 → 非目标 → 方案 → 边界 → 指标 → 发布计划）把模糊想法收敛为可评审的 PRD；内置模板与反例库。",
        "data-analyst": "SQL + 图表分析师：探索性提问 → 生成查询 → 解读结果 → 给出下一步假设；输出始终区分「事实」与「推断」。",
        "gh": "GitHub 官方 CLI，无 SKILL.md。gh pr / gh issue / gh run 等子命令覆盖完整 GitHub 工作流；首次使用需 gh auth login。",
        "ripgrep": "二进制 CLI，无 SKILL.md。rg — 高性能正则搜索，默认遵守 .gitignore，是 agent 检索代码库的事实标准工具。",
        "fd-find": "二进制 CLI，无 SKILL.md。fd — 现代化 find：直觉语法、默认忽略隐藏文件与 .gitignore，速度快一个量级。",
        "mcp-fetch": "HTTP 抓取 MCP server：fetch 工具拉取网页并转 Markdown，支持分页与内容截断控制；适合联网检索场景。",
        "mcp-filesystem": "本地文件读写 MCP server：read/write/list/search 工具，可配置允许访问的目录白名单；越界访问直接拒绝。",
        "mcp-puppeteer": "浏览器自动化 MCP server：导航/截图/点击/表单填写，基于无头 Chromium；适合端到端验证与抓取动态页面。",
        "linear-mcp": "Linear 接入 MCP server：查询/创建/更新 issue，支持按周期与标签过滤；需要 LINEAR_API_KEY。",
        "context7": "实时文档检索 MCP server：按库名 + 版本拉取最新官方文档片段注入上下文，避免模型用过时 API 写代码。",
    ]
}
