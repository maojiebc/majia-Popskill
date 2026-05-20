import Foundation

/// Capability modalities Popskill surfaces in the matrix. Order in
/// `CaseIterable` mirrors the type-filter chip row in `MatrixView`.
/// Bundles are first-class package rows backed by `package-list`; skill and
/// agent rows keep the existing direct management flows.
enum CapabilityKind: String, Codable, CaseIterable, Identifiable {
    case bundle
    case skill
    case agent
    case cli
    case mcp
    case config

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .bundle: return "matrix.type.bundle"
        case .skill:  return "matrix.type.skill"
        case .agent:  return "matrix.type.agent"
        case .cli:    return "matrix.type.cli"
        case .mcp:    return "matrix.type.mcp"
        case .config: return "matrix.type.config"
        }
    }

    var symbol: String {
        switch self {
        case .bundle: return "shippingbox.fill"
        case .skill:  return "square.grid.3x3.fill"
        case .agent:  return "person.crop.square"
        case .cli:    return "terminal"
        case .mcp:    return "rectangle.connected.to.line.below"
        case .config: return "slider.horizontal.3"
        }
    }
}

struct CapabilityAppCoverage: Equatable {
    let enabled: Int
    let total: Int

    var isEnabled: Bool { enabled > 0 }
    var label: String { "\(enabled)/\(total)" }
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
    let underlyingPackageID: String?
    let package: CapabilityPackage?
    let appCoverage: [TargetApp: CapabilityAppCoverage]

    init(
        id: String,
        kind: CapabilityKind,
        name: String,
        summary: String?,
        sourceLabel: String,
        sourceType: String?,
        repoOwner: String?,
        repoName: String?,
        apps: SkillApps,
        deployment: SkillDeployment?,
        directory: String,
        installedAt: Int?,
        updatedAt: Int?,
        sizeBytes: UInt64?,
        triggerScenarios: [String]?,
        underlyingSkillID: String?,
        underlyingAgentID: String?,
        underlyingPackageID: String? = nil,
        package: CapabilityPackage? = nil,
        appCoverage: [TargetApp: CapabilityAppCoverage] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.summary = summary
        self.sourceLabel = sourceLabel
        self.sourceType = sourceType
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.apps = apps
        self.deployment = deployment
        self.directory = directory
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.sizeBytes = sizeBytes
        self.triggerScenarios = triggerScenarios
        self.underlyingSkillID = underlyingSkillID
        self.underlyingAgentID = underlyingAgentID
        self.underlyingPackageID = underlyingPackageID
        self.package = package
        self.appCoverage = appCoverage
    }

    /// Source URL is reusable across kinds — the matrix uses it for the
    /// "Open Source" menu item.
    var sourceURL: URL? {
        if let packageURL = package?.sourceURL {
            return packageURL
        }
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

    var hasBrokenLink: Bool {
        deployment?.hasBrokenLink == true
    }

    func hasBrokenLinks(in skills: [Skill]) -> Bool {
        hasBrokenLink || package?.hasBrokenLinks(in: skills) == true
    }

    func matchesSearch(query: SearchTextKey) -> Bool {
        guard !query.isEmpty else { return true }

        if Self.matches(searchFields, query: query) {
            return true
        }

        guard let package else {
            return false
        }

        return Self.matches(package.searchFields, query: query)
            || package.components.all.contains { component in
                Self.matches(component.searchFields, query: query)
            }
            || package.configSchema.contains { field in
                Self.matches(field.searchFields, query: query)
            }
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

    static func packageCapabilityID(for packageID: String) -> String {
        capabilityID(kind: .bundle, rawID: packageID)
    }

    static func toggleKey(capabilityID: String, app: TargetApp) -> String {
        "\(capabilityID)|\(app.rawValue)"
    }

    static func skillToggleKey(for skillID: String, app: TargetApp) -> String {
        toggleKey(capabilityID: skillCapabilityID(for: skillID), app: app)
    }

    private var searchFields: [String] {
        var fields = [
            id,
            kind.rawValue,
            name,
            summary ?? "",
            sourceLabel,
            sourceType ?? "",
            repoOwner ?? "",
            repoName ?? "",
            directory
        ]
        fields.append(contentsOf: kind.searchAliases)
        fields.append(contentsOf: triggerScenarios ?? [])
        fields.append(contentsOf: TargetApp.supported.flatMap { app in
            apps.isEnabled(app) ? app.searchAliases : []
        })
        return fields
    }

    private static func matches(_ fields: [String], query: SearchTextKey) -> Bool {
        fields.contains { SearchTextNormalizer.matches($0, query: query) }
    }
}

extension MatrixCapability {
    static func fromPackage(_ package: CapabilityPackage, skills: [Skill]) -> MatrixCapability {
        let coverage = package.appCoverage(using: skills)
        let appState = SkillApps(
            claude: coverage[.claude]?.isEnabled == true,
            codex: coverage[.codex]?.isEnabled == true,
            gemini: coverage[.gemini]?.isEnabled == true,
            opencode: coverage[.opencode]?.isEnabled == true,
            hermes: coverage[.hermes]?.isEnabled == true
        )

        return MatrixCapability(
            id: packageCapabilityID(for: package.id),
            kind: .bundle,
            name: package.name,
            summary: package.summary,
            sourceLabel: package.sourceLabel,
            sourceType: package.source.kind,
            repoOwner: package.source.repoOwner,
            repoName: package.source.repoName,
            apps: appState,
            deployment: nil,
            directory: package.source.location,
            installedAt: package.lifecycle?.installedAt,
            updatedAt: package.lifecycle?.updatedAt,
            sizeBytes: nil,
            triggerScenarios: nil,
            underlyingSkillID: nil,
            underlyingAgentID: nil,
            underlyingPackageID: package.id,
            package: package,
            appCoverage: coverage
        )
    }

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

private extension CapabilityKind {
    var searchAliases: [String] {
        switch self {
        case .bundle: ["bundle", "package", "suite", "套装", "能力包"]
        case .skill: ["skill", "技能", "能力"]
        case .agent: ["agent", "智能体"]
        case .cli: ["cli", "command line", "命令行"]
        case .mcp: ["mcp", "server", "服务"]
        case .config: ["config", "settings", "配置", "设置"]
        }
    }
}

private extension TargetApp {
    var searchAliases: [String] {
        switch self {
        case .claude: ["Claude", "Claude Code", "CC"]
        case .codex: ["Codex", "CDX"]
        case .gemini: ["Gemini"]
        case .opencode: ["OpenCode"]
        case .hermes: ["Hermes"]
        }
    }
}

private extension CapabilityPackage {
    var searchFields: [String] {
        [
            id,
            type.rawValue,
            type.title,
            health.rawValue,
            health.title,
            name,
            vendor ?? "",
            summary,
            source.kind,
            source.location,
            source.updateStrategy,
            source.repoOwner ?? "",
            source.repoName ?? "",
            source.repoBranch ?? "",
            source.readmeUrl ?? "",
            installed ? "installed 已装 active" : "missing 未装 inactive",
            "components 组件"
        ]
    }
}

private extension PackageComponent {
    var searchFields: [String] {
        [
            id,
            name,
            kind,
            status,
            statusAliases,
            required ? "required 必需" : "optional 可选",
            installed ? "installed 已装" : "missing 未装",
            location ?? ""
        ]
    }

    private var statusAliases: String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "stub": "stub 占位"
        case "registry-reference": "registry reference 注册表"
        case "detected": "detected 检测到"
        case "installed": "installed 已装"
        case "declared": "declared 声明"
        case "available": "available 可用"
        default: ""
        }
    }
}

private extension PackageConfigField {
    var searchFields: [String] {
        [
            id,
            label,
            storage,
            required ? "required 必需" : "optional 可选",
            secret ? "secret 密钥" : ""
        ]
    }
}
