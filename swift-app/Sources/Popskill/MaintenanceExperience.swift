import Foundation

/// CLI 维护中心使用的轻量目录。
///
/// 和技能精选目录一样，这些说明属于产品内容而不是界面文案：中英文在数据层并存，
/// 不塞进 xcstrings。精确命中才允许批量升级；关键词猜中的未知工具只展示、只允许单行手动升级。
enum AgentCliRole: String, Equatable, Sendable {
    case codingAgent
    case orchestration
    case companion
    case utility

    var label: String {
        switch self {
        case .codingAgent: maintenanceText("编码 Agent", "Coding agent")
        case .orchestration: maintenanceText("Agent 编排", "Agent orchestration")
        case .companion: maintenanceText("能力配套", "Capability companion")
        case .utility: maintenanceText("AI 工具", "AI utility")
        }
    }
}

struct AgentCliDefinition: Equatable, Sendable {
    let id: String
    let displayName: String
    let role: AgentCliRole
    let zh: String
    let en: String
    let aliases: Set<String>
    let safeAutomaticUpgrade: Bool

    var summary: String { maintenanceText(zh, en) }
}

enum AgentCliCatalog {
    static let definitions: [AgentCliDefinition] = [
        AgentCliDefinition(
            id: "claude-code", displayName: "Claude Code", role: .codingAgent,
            zh: "Anthropic 的终端编码 Agent，可读写项目、运行命令并调用 Skills。",
            en: "Anthropic's terminal coding agent for editing projects, running commands, and using Skills.",
            aliases: ["@anthropic-ai/claude-code", "claude", "claude-code"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "codex", displayName: "Codex CLI", role: .codingAgent,
            zh: "OpenAI 的终端编码 Agent，面向仓库理解、代码修改和任务执行。",
            en: "OpenAI's terminal coding agent for repository reasoning, code changes, and task execution.",
            aliases: ["@openai/codex", "codex"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "gemini-cli", displayName: "Gemini CLI", role: .codingAgent,
            zh: "Google 的开源终端 Agent，支持代码任务、工具调用和扩展。",
            en: "Google's open-source terminal agent for coding tasks, tools, and extensions.",
            aliases: ["@google/gemini-cli", "gemini", "gemini-cli"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "qwen-code", displayName: "Qwen Code", role: .codingAgent,
            zh: "通义千问的终端编码 Agent，提供项目操作、工具调用和多渠道能力。",
            en: "Qwen's terminal coding agent with project operations, tools, and multi-channel capabilities.",
            aliases: ["@qwen-code/qwen-code", "qwen", "qwen-code"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "opencode", displayName: "OpenCode", role: .codingAgent,
            zh: "面向终端的开源编码 Agent，可连接多种模型与开发工具。",
            en: "An open-source terminal coding agent that works with multiple models and developer tools.",
            aliases: ["opencode"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "pi", displayName: "Pi", role: .codingAgent,
            zh: "轻量可扩展的终端编码 Agent，强调提示词、工具和扩展组合。",
            en: "A lightweight extensible terminal coding agent built around prompts, tools, and extensions.",
            aliases: ["@earendil-works/pi-coding-agent", "pi", "pi-coding-agent"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "aider", displayName: "Aider", role: .codingAgent,
            zh: "以 Git 为中心的 AI 结对编程工具，适合在现有仓库中持续改代码。",
            en: "A Git-oriented AI pair programmer for making iterative changes in existing repositories.",
            aliases: ["aider", "aider-chat"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "open-interpreter", displayName: "Open Interpreter", role: .codingAgent,
            zh: "让模型在本机执行代码与系统任务的终端 Agent。",
            en: "A terminal agent that lets models execute code and system tasks locally.",
            aliases: ["interpreter", "open-interpreter"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "agent-reach", displayName: "Agent Reach", role: .orchestration,
            zh: "为 Agent 提供外部信息获取与触达能力的命令行工具。",
            en: "A command-line companion that gives agents external discovery and reach capabilities.",
            aliases: ["agent-reach"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "lark-cli", displayName: "Lark CLI", role: .companion,
            zh: "飞书开放平台命令行工具，为文档、消息和组织能力提供入口。",
            en: "Lark's command-line toolkit for documents, messaging, and organization capabilities.",
            aliases: ["@larksuite/cli", "lark-cli"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "guanskill", displayName: "GuanSkill", role: .companion,
            zh: "观远数据能力安装与维护 CLI，负责生成和更新本地 Skill。",
            en: "The GuanData CLI for installing and maintaining local Skills.",
            aliases: ["@guandata/guanskill", "guanskill"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "getnote", displayName: "Getnote CLI", role: .companion,
            zh: "笔记与内容工作流的命令行入口，可作为 Agent 的资料获取工具。",
            en: "A command-line entry point for note and content workflows used by agents.",
            aliases: ["@getnote/cli", "getnote"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "clawhub", displayName: "ClawHub", role: .orchestration,
            zh: "OpenClaw 生态的能力发现与安装工具。",
            en: "A discovery and installation tool for the OpenClaw ecosystem.",
            aliases: ["clawhub"],
            safeAutomaticUpgrade: true
        ),
        AgentCliDefinition(
            id: "mcporter", displayName: "MCPorter", role: .orchestration,
            zh: "MCP 服务发现、连接与调试工具。",
            en: "A utility for discovering, connecting, and debugging MCP servers.",
            aliases: ["mcporter"],
            safeAutomaticUpgrade: true
        ),
    ]

    private static let hintTokens = [
        "agent", "claude", "codex", "gemini", "grok", "qwen", "aider",
        "opencode", "copilot", "interpreter", "claw", "mcp", "skill",
    ]

    static func definition(for cli: GlobalCli) -> AgentCliDefinition? {
        let candidates = Set([
            cli.name.lowercased(),
            cli.displayName.lowercased(),
            cliBinName(cli.name).lowercased(),
        ])
        return definitions.first { !candidates.isDisjoint(with: $0.aliases) }
    }

    static func looksLikeAgent(_ cli: GlobalCli) -> Bool {
        if definition(for: cli) != nil { return true }
        let haystack = "\(cli.name) \(cli.displayName) \(cliBinName(cli.name))".lowercased()
        return hintTokens.contains { haystack.contains($0) }
    }
}

extension GlobalCli {
    var agentDefinition: AgentCliDefinition? { AgentCliCatalog.definition(for: self) }
    var looksLikeAgent: Bool { AgentCliCatalog.looksLikeAgent(self) }
    var maintenanceName: String { agentDefinition?.displayName ?? displayName }
    var maintenanceSummary: String {
        if let summary = agentDefinition?.summary { return summary }
        return looksLikeAgent
            ? maintenanceText("疑似 Agent CLI；已识别安装位置，但暂无内置说明。", "Likely an agent CLI; its installation is detected but no built-in description is available yet.")
            : maintenanceText("本机全局命令行工具。", "A globally installed command-line tool.")
    }
    var maintenanceRole: String {
        agentDefinition?.role.label
            ?? (looksLikeAgent ? maintenanceText("待确认 Agent", "Unverified agent") : maintenanceText("其它工具", "Other tool"))
    }
    /// 批量升级只接收目录精确命中且明确允许的 Agent；猜中的未知包留给用户逐行确认。
    var safeRecognizedAgentUpdate: Bool {
        hasUpdate && agentDefinition?.safeAutomaticUpgrade == true
    }
}

func maintenanceText(_ zh: String, _ en: String) -> String {
    l10nIsChinese ? zh : en
}

/// 本地路径没有可验证的远端版本，不纳入「全部来源自动更新」。
/// Marketplace 生命周期归宿主管理，也不能被 Popskill 接管。
func supportsBulkAutomaticUpdate(sourceUrl: String?, managedExternally: Bool) -> Bool {
    guard !managedExternally, let sourceUrl, !sourceUrl.isEmpty else { return false }
    switch SourceKind.of(sourceUrl) {
    case .github, .npm, .wellKnown: return true
    case .local: return false
    }
}
