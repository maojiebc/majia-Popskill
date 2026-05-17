import Foundation

/// Five capability modalities Popskill surfaces in the matrix. Order in
/// `CaseIterable` mirrors the type-filter chip row in `MatrixView` (skill →
/// agent → cli → mcp → config). v0.4 ships skill + agent fully; cli / mcp /
/// config are placeholders that the matrix renders an "empty for now" hint
/// for until later sprints wire their sidecar discovery.
enum CapabilityKind: String, Codable, CaseIterable, Identifiable {
    case skill
    case agent
    case cli
    case mcp
    case config

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .skill:  return "matrix.type.skill"
        case .agent:  return "matrix.type.agent"
        case .cli:    return "matrix.type.cli"
        case .mcp:    return "matrix.type.mcp"
        case .config: return "matrix.type.config"
        }
    }

    var symbol: String {
        switch self {
        case .skill:  return "square.grid.3x3.fill"
        case .agent:  return "person.crop.square"
        case .cli:    return "terminal"
        case .mcp:    return "rectangle.connected.to.line.below"
        case .config: return "slider.horizontal.3"
        }
    }
}

/// Unified row model the matrix renders against. Wraps `Skill` / `LocalAgent`
/// / future `CLITool` / `MCPServer` / `ConfigEntry` without exposing their
/// individual shapes to view code. Toggle actions look up the underlying
/// model through `underlyingSkillID` and `underlyingAgentID`.
struct MatrixCapability: Identifiable, Equatable {
    /// Namespaced id, e.g. "skill:xxx" or "agent:xxx" — avoids collisions when
    /// a skill and an agent happen to share the unprefixed id.
    let id: String
    let kind: CapabilityKind
    let name: String
    let summary: String?
    let sourceLabel: String
    let sourceType: String?
    let repoOwner: String?
    let repoName: String?
    let apps: SkillApps
    let deployment: SkillDeployment?
    let directory: String
    let installedAt: Int?
    let updatedAt: Int?
    let sizeBytes: UInt64?
    let triggerScenarios: [String]?
    let underlyingSkillID: String?
    let underlyingAgentID: String?

    /// Source URL is reusable across kinds — the matrix uses it for the
    /// "Open Source" menu item.
    var sourceURL: URL? {
        if let owner = repoOwner, let name = repoName, !owner.isEmpty, !name.isEmpty {
            return URL(string: "https://github.com/\(owner)/\(name)")
        }
        return nil
    }

    var isToggleable: Bool {
        // Skills have explicit per-app toggles (Claude / Codex switches).
        // Agents in v0.4 are Claude-Code-only and present-vs-absent; later
        // sprints may add a deploy/undeploy toggle but for now they show as
        // read-only "active on Claude".
        kind == .skill
    }

    static func capabilityID(kind: CapabilityKind, rawID: String) -> String {
        "\(kind.rawValue):\(rawID)"
    }

    static func skillCapabilityID(for skillID: String) -> String {
        capabilityID(kind: .skill, rawID: skillID)
    }

    static func agentCapabilityID(for agentID: String) -> String {
        capabilityID(kind: .agent, rawID: agentID)
    }

    static func toggleKey(capabilityID: String, app: TargetApp) -> String {
        "\(capabilityID)|\(app.rawValue)"
    }

    static func skillToggleKey(for skillID: String, app: TargetApp) -> String {
        toggleKey(capabilityID: skillCapabilityID(for: skillID), app: app)
    }
}

extension MatrixCapability {
    static func fromSkill(_ skill: Skill) -> MatrixCapability {
        MatrixCapability(
            id: skillCapabilityID(for: skill.id),
            kind: .skill,
            name: skill.name,
            summary: skill.capabilitySummary ?? (skill.description.isEmpty ? nil : skill.description),
            sourceLabel: skill.sourceLabel,
            sourceType: skill.sourceType,
            repoOwner: skill.repoOwner,
            repoName: skill.repoName,
            apps: skill.apps,
            deployment: skill.deployment,
            directory: skill.directory,
            installedAt: skill.installedAt,
            updatedAt: skill.updatedAt,
            sizeBytes: skill.sizeBytes,
            triggerScenarios: skill.triggerScenarios,
            underlyingSkillID: skill.id,
            underlyingAgentID: nil
        )
    }

    static func fromAgent(_ agent: LocalAgent) -> MatrixCapability {
        // Agents live under ~/.claude/agents — Claude Code only. We synthesize
        // a SkillApps with claude=true so the toggle column shows it as on
        // even though we can't currently toggle it off without deleting the
        // file (deferred to v0.5).
        let agentApps = SkillApps(claude: true, codex: false, gemini: false, opencode: false, hermes: false)
        return MatrixCapability(
            id: agentCapabilityID(for: agent.id),
            kind: .agent,
            name: agent.name,
            summary: agent.capabilitySummary ?? (agent.description.isEmpty ? nil : agent.description),
            sourceLabel: agent.categoryLabel,
            sourceType: "agent",
            repoOwner: nil,
            repoName: nil,
            apps: agentApps,
            deployment: nil,
            directory: agent.fileName,
            installedAt: nil,
            updatedAt: agent.lastModifiedAt,
            sizeBytes: agent.sizeBytes,
            triggerScenarios: agent.triggerScenarios,
            underlyingSkillID: nil,
            underlyingAgentID: agent.id
        )
    }
}
