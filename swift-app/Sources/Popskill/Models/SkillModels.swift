import Foundation

enum TargetApp: String, CaseIterable, Identifiable, Codable {
    case claude
    case codex
    case gemini
    case opencode
    case hermes

    var id: String { rawValue }

    var title: String {
        definition.displayName
    }

    var symbolName: String {
        definition.symbolName
    }

    var definition: TargetAppDefinition {
        TargetAppRegistry.definition(for: self)
    }

    static var supported: [TargetApp] {
        TargetAppRegistry.all.map(\.app)
    }

    static var quickToggleSupported: [TargetApp] {
        TargetAppRegistry.quickToggle.map(\.app)
    }
}

struct TargetAppDefinition: Identifiable, Equatable {
    var id: String { app.rawValue }

    let app: TargetApp
    let displayName: String
    let symbolName: String
    let quickToggle: Bool
    let skillDirectory: String
    let detectPath: String
    let cliCommands: [String]
    let note: String?
}

enum TargetAppRegistry {
    static let all: [TargetAppDefinition] = [
        TargetAppDefinition(
            app: .claude,
            displayName: "Claude",
            symbolName: "sparkles",
            quickToggle: true,
            skillDirectory: ".claude/skills",
            detectPath: ".claude",
            cliCommands: ["claude"],
            note: "Claude Code skill directory"
        ),
        TargetAppDefinition(
            app: .codex,
            displayName: "Codex",
            symbolName: "chevron.left.forwardslash.chevron.right",
            quickToggle: true,
            skillDirectory: ".codex/skills",
            detectPath: ".codex",
            cliCommands: ["codex"],
            note: "Codex skill directory"
        ),
        TargetAppDefinition(
            app: .gemini,
            displayName: "Gemini",
            symbolName: "diamond",
            quickToggle: true,
            skillDirectory: ".gemini/skills",
            detectPath: ".gemini",
            cliCommands: ["gemini"],
            note: "Gemini skill directory"
        ),
        TargetAppDefinition(
            app: .opencode,
            displayName: "OpenCode",
            symbolName: "terminal",
            quickToggle: false,
            skillDirectory: ".config/opencode/skills",
            detectPath: ".config/opencode",
            cliCommands: ["opencode"],
            note: "OpenCode XDG skill directory"
        ),
        TargetAppDefinition(
            app: .hermes,
            displayName: "Hermes",
            symbolName: "h.circle",
            quickToggle: false,
            skillDirectory: ".hermes/skills",
            detectPath: ".hermes",
            cliCommands: ["hermes"],
            note: "Hermes skill directory"
        )
    ]

    static var quickToggle: [TargetAppDefinition] {
        all.filter(\.quickToggle)
    }

    static func definition(for app: TargetApp) -> TargetAppDefinition {
        all.first { $0.app == app } ?? TargetAppDefinition(
            app: app,
            displayName: app.rawValue,
            symbolName: "circle",
            quickToggle: false,
            skillDirectory: "",
            detectPath: "",
            cliCommands: [],
            note: nil
        )
    }
}

struct Skill: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let directory: String
    let repoOwner: String?
    let repoName: String?
    let readmeUrl: String?
    var apps: SkillApps
    let installedAt: Int?
    let updatedAt: Int?
    let contentHash: String?
    var capabilitySummary: String? = nil
    var triggerScenarios: [String]? = nil
    var lastUsedAt: Int? = nil
    var sizeBytes: UInt64? = nil

    var sourceLabel: String {
        if let repoOwner, let repoName, !repoOwner.isEmpty, !repoName.isEmpty {
            return "\(repoOwner)/\(repoName)"
        }
        return directory
    }

    var sourceURL: URL? {
        explicitOrRepositoryURL(readmeUrl: readmeUrl, repoOwner: repoOwner, repoName: repoName)
    }

    var markdownURL: URL? {
        let url = localStoreURL.appendingPathComponent("SKILL.md")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var enabledAppCount: Int {
        TargetApp.supported.filter { apps.isEnabled($0) }.count
    }

    var localStoreURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cc-switch")
            .appendingPathComponent("skills")
            .appendingPathComponent(directory)
    }

    var lastLifecycleTimestamp: Int? {
        [installedAt, updatedAt]
            .compactMap { value -> Int? in
                guard let value, value > 0 else {
                    return nil
                }
                return value
            }
            .max()
    }

    func isIdleCandidate(referenceDate: Date = Date(), thresholdDays: Int = 60) -> Bool {
        guard enabledAppCount == 0 else {
            return false
        }

        guard let lastLifecycleTimestamp else {
            return true
        }

        let threshold = TimeInterval(max(0, thresholdDays)) * 24 * 60 * 60
        let cutoff = Int(referenceDate.addingTimeInterval(-threshold).timeIntervalSince1970)
        return lastLifecycleTimestamp <= cutoff
    }

    func matchesAttributionSkill(_ identifier: String) -> Bool {
        let normalizedIdentifier = Self.normalizedAttributionIdentifier(identifier)
        guard !normalizedIdentifier.isEmpty else {
            return false
        }

        let identifierSuffix = normalizedIdentifier
            .split(separator: ":", maxSplits: 1)
            .last
            .map(String.init) ?? normalizedIdentifier

        let candidates = [
            id,
            name,
            directory,
            id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id
        ].map(Self.normalizedAttributionIdentifier)

        return candidates.contains(normalizedIdentifier) || candidates.contains(identifierSuffix)
    }

    private static func normalizedAttributionIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct LocalAgent: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let fileName: String
    let path: String
    let category: String
    let tools: [String]
    let model: String?
    let lastModifiedAt: Int?
    let sizeBytes: UInt64

    var fileURL: URL {
        URL(fileURLWithPath: path)
    }

    var categoryLabel: String {
        category.isEmpty ? "local" : category
    }

    var toolSummary: String {
        tools.isEmpty ? "Default Claude Code tools" : tools.joined(separator: ", ")
    }
}

struct AgentTarget: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let scope: String
    let format: String
    let paths: [String]
    let detected: Bool
    let source: String
    let note: String?

    var primaryPath: String {
        paths.first ?? ""
    }

    var statusLabel: String {
        detected ? "Detected" : "Missing"
    }

    var pathSummary: String {
        if paths.isEmpty {
            return ""
        }
        if paths.count == 1 {
            return paths[0]
        }
        return paths.prefix(2).joined(separator: "\n")
    }

    var symbolName: String {
        definition.symbolName
    }

    var definition: TargetAgentDefinition {
        TargetAgentRegistry.definition(for: id, fallbackName: name)
    }

    var linkedApp: TargetApp? {
        definition.linkedApp
    }

    var expectedPathSummary: String? {
        let paths = definition.detectPaths
        guard !paths.isEmpty else {
            return nil
        }
        return paths.joined(separator: ", ")
    }

    var cliCommandSummary: String? {
        guard !definition.cliCommands.isEmpty else {
            return nil
        }
        return definition.cliCommands.joined(separator: ", ")
    }

    var appBundleSummary: String? {
        guard !definition.appBundleNames.isEmpty else {
            return nil
        }
        return definition.appBundleNames.joined(separator: ", ")
    }

    var isRegistryTarget: Bool {
        TargetAgentRegistry.isKnown(id: id)
    }

    var isImportedTarget: Bool {
        !isRegistryTarget || source != TargetAgentRegistry.defaultSource
    }
}

struct TargetAgentDefinition: Identifiable, Equatable {
    var id: String { targetID }

    let targetID: String
    let displayName: String
    let symbolName: String
    let linkedApp: TargetApp?
    let detectPaths: [String]
    let cliCommands: [String]
    let appBundleNames: [String]
    let note: String?
}

enum TargetAgentRegistry {
    static let defaultSource = "agency-agents"

    static let all: [TargetAgentDefinition] = [
        TargetAgentDefinition(
            targetID: "claude-code",
            displayName: "Claude Code",
            symbolName: "sparkles",
            linkedApp: .claude,
            detectPaths: [".claude", ".claude/agents"],
            cliCommands: ["claude"],
            appBundleNames: [],
            note: "Uses ~/.claude roots for skills and local agents."
        ),
        TargetAgentDefinition(
            targetID: "copilot",
            displayName: "GitHub Copilot",
            symbolName: "network",
            linkedApp: nil,
            detectPaths: [],
            cliCommands: ["copilot"],
            appBundleNames: ["GitHub Copilot"],
            note: nil
        ),
        TargetAgentDefinition(
            targetID: "antigravity",
            displayName: "Antigravity",
            symbolName: "arrow.up.circle",
            linkedApp: nil,
            detectPaths: [],
            cliCommands: ["antigravity"],
            appBundleNames: [],
            note: nil
        ),
        TargetAgentDefinition(
            targetID: "gemini-cli",
            displayName: "Gemini CLI",
            symbolName: "diamond",
            linkedApp: .gemini,
            detectPaths: [".gemini", ".gemini/agents"],
            cliCommands: ["gemini"],
            appBundleNames: [],
            note: "Shares ~/.gemini root with Popskill skill toggles."
        ),
        TargetAgentDefinition(
            targetID: "opencode",
            displayName: "OpenCode",
            symbolName: "terminal",
            linkedApp: .opencode,
            detectPaths: [".config/opencode"],
            cliCommands: ["opencode"],
            appBundleNames: [],
            note: "XDG-based target rooted at ~/.config/opencode."
        ),
        TargetAgentDefinition(
            targetID: "openclaw",
            displayName: "OpenClaw",
            symbolName: "hammer",
            linkedApp: nil,
            detectPaths: [],
            cliCommands: ["openclaw"],
            appBundleNames: ["OpenClaw"],
            note: nil
        ),
        TargetAgentDefinition(
            targetID: "cursor",
            displayName: "Cursor",
            symbolName: "cursorarrow",
            linkedApp: nil,
            detectPaths: [],
            cliCommands: ["cursor"],
            appBundleNames: ["Cursor"],
            note: nil
        ),
        TargetAgentDefinition(
            targetID: "aider",
            displayName: "Aider",
            symbolName: "text.book.closed",
            linkedApp: nil,
            detectPaths: [],
            cliCommands: ["aider"],
            appBundleNames: [],
            note: nil
        ),
        TargetAgentDefinition(
            targetID: "windsurf",
            displayName: "Windsurf",
            symbolName: "wind",
            linkedApp: nil,
            detectPaths: [],
            cliCommands: ["windsurf"],
            appBundleNames: ["Windsurf"],
            note: nil
        ),
        TargetAgentDefinition(
            targetID: "qwen",
            displayName: "Qwen Code",
            symbolName: "q.circle",
            linkedApp: nil,
            detectPaths: [],
            cliCommands: ["qwen"],
            appBundleNames: [],
            note: nil
        ),
        TargetAgentDefinition(
            targetID: "kimi",
            displayName: "Kimi Code",
            symbolName: "k.circle",
            linkedApp: nil,
            detectPaths: [],
            cliCommands: ["kimi"],
            appBundleNames: [],
            note: nil
        )
    ]

    static func definition(for id: String, fallbackName: String) -> TargetAgentDefinition {
        guard let definition = all.first(where: { $0.targetID == id }) else {
            return TargetAgentDefinition(
                targetID: id,
                displayName: fallbackName,
                symbolName: "person.crop.circle",
                linkedApp: nil,
                detectPaths: [],
                cliCommands: [],
                appBundleNames: [],
                note: nil
            )
        }
        return definition
    }

    static func isKnown(id: String) -> Bool {
        all.contains(where: { $0.targetID == id })
    }

    static func sort(_ targets: [AgentTarget]) -> [AgentTarget] {
        targets.sorted(by: areInOrder)
    }

    private static func areInOrder(_ left: AgentTarget, _ right: AgentTarget) -> Bool {
        let leftRank = rank(for: left)
        let rightRank = rank(for: right)
        if leftRank != rightRank {
            return leftRank < rightRank
        }

        if left.detected != right.detected {
            return left.detected && !right.detected
        }

        let sourceOrder = left.source.localizedCaseInsensitiveCompare(right.source)
        if sourceOrder != .orderedSame {
            return sourceOrder == .orderedAscending
        }

        let nameOrder = left.name.localizedCaseInsensitiveCompare(right.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return left.id < right.id
    }

    private static func rank(for target: AgentTarget) -> Int {
        all.firstIndex(where: { $0.targetID == target.id }) ?? all.count + 20
    }
}

struct CatalogAgent: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let path: String
    let category: String
    let repoOwner: String
    let repoName: String
    let repoBranch: String
    let readmeUrl: String
    let rawUrl: String
    let tools: [String]
    let model: String?
    let source: String
}

struct AgentInstallPlan: Codable, Equatable {
    let agentId: String
    let name: String
    let targetId: String
    let targetName: String
    let targetFormat: String
    let source: AgentInstallSource
    let writes: [String]
    let conflict: AgentInstallConflict?
    let requiresConversion: Bool
    let steps: [String]
}

struct AgentInstallSource: Codable, Equatable {
    let repoOwner: String
    let repoName: String
    let repoBranch: String
    let path: String
    let rawUrl: String
}

struct AgentInstallConflict: Codable, Equatable {
    let paths: [String]
}

enum CapabilityPackageType: String, Codable, Equatable {
    case composite
    case standalone

    var title: String {
        switch self {
        case .composite: "Composite"
        case .standalone: "Standalone"
        }
    }
}

enum CapabilityPackageHealth: String, Equatable {
    case active
    case partial
    case inactive
    case blocked

    var title: String {
        switch self {
        case .active: "Active"
        case .partial: "Partial"
        case .inactive: "Inactive"
        case .blocked: "Blocked"
        }
    }
}

struct CapabilityPackage: Identifiable, Codable, Equatable {
    let id: String
    let type: CapabilityPackageType
    let name: String
    let vendor: String?
    let summary: String
    let source: PackageSource
    let components: PackageComponents
    let configSchema: [PackageConfigField]
    let installed: Bool
    let lifecycle: PackageLifecycle?

    var componentCount: Int {
        components.all.count
    }

    var installedComponentCount: Int {
        components.all.filter(\.installed).count
    }

    var requiredComponentCount: Int {
        components.all.filter(\.required).count
    }

    var typeLabel: String {
        type.title
    }

    var health: CapabilityPackageHealth {
        if installedComponentCount == 0 {
            return .inactive
        }
        if missingRequiredComponentCount > 0 {
            return .blocked
        }
        if missingComponentCount > 0 {
            return .partial
        }
        return .active
    }

    var sourceLabel: String {
        if let vendor, !vendor.isEmpty {
            return vendor
        }
        return source.location
    }

    var sourceURL: URL? {
        return explicitOrRepositoryURL(
            readmeUrl: source.readmeUrl ?? source.location,
            repoOwner: source.repoOwner,
            repoName: source.repoName
        )
    }

    var missingComponentCount: Int {
        components.all.filter { !$0.installed }.count
    }

    var missingRequiredComponentCount: Int {
        components.all.filter { $0.required && !$0.installed }.count
    }

    var recoverableMissingComponentCount: Int {
        components.all.filter { !$0.installed && $0.isRecoverable }.count
    }

    var primaryComponentKindsLabel: String {
        let kinds = components.all.map { $0.kind.lowercased() }
        let orderedKinds = ["skill", "cli", "mcp", "agent"]
        let labels = orderedKinds.filter { kinds.contains($0) }.map(\.capitalized)
        return labels.isEmpty ? "Unknown" : labels.joined(separator: " + ")
    }

    var componentGroupSummaries: [PackageComponentGroupSummary] {
        [
            PackageComponentGroupSummary(kind: "skill", title: "Skills", components: components.skills),
            PackageComponentGroupSummary(kind: "cli", title: "CLI", components: components.cli),
            PackageComponentGroupSummary(kind: "mcp", title: "MCP", components: components.mcp),
            PackageComponentGroupSummary(kind: "agent", title: "Agents", components: components.agents)
        ].filter { $0.total > 0 }
    }

    var lastLifecycleTimestamp: Int? {
        [lifecycle?.installedAt, lifecycle?.updatedAt]
            .compactMap { value -> Int? in
                guard let value, value > 0 else {
                    return nil
                }
                return value
            }
            .max()
    }

    var trackedContentHash: String? {
        lifecycle?.contentHash?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

struct PackageComponentGroupSummary: Identifiable, Equatable {
    let kind: String
    let title: String
    let total: Int
    let installed: Int
    let missing: Int
    let missingRequired: Int
    let recoverableMissing: Int

    var id: String { kind }

    init(kind: String, title: String, components: [PackageComponent]) {
        self.kind = kind
        self.title = title
        total = components.count
        installed = components.filter(\.installed).count
        missing = max(0, total - installed)
        missingRequired = components.filter { !$0.installed && $0.required }.count
        recoverableMissing = components.filter { !$0.installed && $0.isRecoverable }.count
    }
}

struct PackageSource: Codable, Equatable {
    let kind: String
    let location: String
    let updateStrategy: String
    let repoOwner: String?
    let repoName: String?
    let repoBranch: String?
    let readmeUrl: String?
}

struct PackageLifecycle: Codable, Equatable {
    let installedAt: Int?
    let updatedAt: Int?
    let contentHash: String?

    static let untracked = PackageLifecycle(
        installedAt: nil,
        updatedAt: nil,
        contentHash: nil
    )
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct PackageComponents: Codable, Equatable {
    let cli: [PackageComponent]
    let skills: [PackageComponent]
    let mcp: [PackageComponent]
    let agents: [PackageComponent]

    var all: [PackageComponent] {
        cli + skills + mcp + agents
    }
}

struct PackageComponent: Codable, Equatable {
    let id: String
    let name: String
    let kind: String
    let required: Bool
    let installed: Bool
    let status: String
    let location: String?

    var displayKey: String {
        "\(kind):\(id)"
    }

    var isRecoverable: Bool {
        switch status.lowercased() {
        case "available", "declared", "stub", "registry-reference":
            return true
        default:
            return false
        }
    }
}

struct PackageConfigField: Identifiable, Codable, Equatable {
    let id: String
    let label: String
    let required: Bool
    let secret: Bool
    let storage: String
}

struct PackageInstallResult: Codable, Equatable {
    let packageId: String
    let status: String
    let summary: String
    let steps: [String]
}

struct PackageConfigResult: Codable, Equatable {
    let packageId: String
    let key: String
    let storage: String
    let status: String
    let message: String
}

struct CatalogSkill: Identifiable, Codable, Equatable {
    var id: String { key }

    let key: String
    let name: String
    let description: String
    let directory: String
    let readmeUrl: String?
    let installed: Bool
    let repoOwner: String?
    let repoName: String?
    let repoBranch: String?

    var sourceLabel: String {
        if let repoOwner, let repoName, !repoOwner.isEmpty, !repoName.isEmpty {
            let label = "\(repoOwner)/\(repoName)"
            if let repoBranch, !repoBranch.isEmpty, repoBranch != "main" {
                return "\(label)@\(repoBranch)"
            }
            return label
        }
        return directory
    }

    var sourceURL: URL? {
        explicitOrRepositoryURL(readmeUrl: readmeUrl, repoOwner: repoOwner, repoName: repoName)
    }
}

private func explicitOrRepositoryURL(readmeUrl: String?, repoOwner: String?, repoName: String?) -> URL? {
    if let readmeUrl,
       let url = URL(string: readmeUrl),
       let scheme = url.scheme?.lowercased(),
       ["http", "https"].contains(scheme) {
        return url
    }

    guard let repoOwner, let repoName, !repoOwner.isEmpty, !repoName.isEmpty else {
        return nil
    }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/\(repoOwner)/\(repoName)"
    return components.url
}

private func githubRepositoryURL(from ownerRepo: String) -> URL? {
    let parts = ownerRepo.split(separator: "/", omittingEmptySubsequences: true)
    guard parts.count == 2 else {
        return nil
    }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/\(parts[0])/\(parts[1])"
    return components.url
}

struct SkillRepository: Identifiable, Codable, Equatable {
    var id: String { "\(owner)/\(name)" }

    let owner: String
    let name: String
    let branch: String
    var enabled: Bool

    var label: String {
        "\(owner)/\(name)"
    }
}

struct SkillRepositoryToggleResult: Codable, Equatable {
    let owner: String
    let name: String
    let enabled: Bool
}

struct SkillRepositoryRemoveResult: Codable, Equatable {
    let owner: String
    let name: String
}

struct InstallPlan: Codable, Equatable {
    let skillKey: String
    let name: String
    let description: String
    let targetApp: String
    let installDirectory: String
    let source: InstallPlanSource
    let existingSkillId: String?
    let writes: InstallPlanWrites
    let securityGate: String
    let steps: [String]
}

struct InstallPlanSource: Codable, Equatable {
    let repoOwner: String
    let repoName: String
    let repoBranch: String
    let readmeUrl: String?
}

struct InstallPlanWrites: Codable, Equatable {
    let ssotPath: String
    let appSkillPath: String?
}

struct SkillUninstallResult: Codable, Equatable {
    let backupPath: String?
}

struct StubbedSkill: Identifiable, Codable, Equatable {
    var id: String { skill.id }

    let skill: Skill
    let backupId: String
    let backupPath: String
    let stubbedAt: Int
}

struct SkillBackup: Identifiable, Codable, Equatable {
    var id: String { backupId }

    let backupId: String
    let backupPath: String
    let createdAt: Int
    let skill: Skill
}

struct SkillBackupDeleteResult: Codable, Equatable {
    let backupId: String
}

struct SidecarHealth: Codable, Equatable {
    let sidecarVersion: String
    let installedCount: Int
    let unmanagedCount: Int
    let backupCount: Int
    let repositoryCount: Int
    let enabledRepositoryCount: Int
    let skillStorePath: String
    let skillBackupPath: String
}

struct WebDAVStatus: Codable, Equatable {
    let configured: Bool
    let enabled: Bool?
    let autoSync: Bool?
    let baseUrl: String?
    let username: String?
    let remoteRoot: String?
    let profile: String?
    let status: WebDAVSyncStatus?
}

struct WebDAVConfiguration: Equatable {
    let enabled: Bool
    let autoSync: Bool
    let baseUrl: String
    let username: String
    let password: String
    let remoteRoot: String
    let profile: String
}

struct WebDAVSyncStatus: Codable, Equatable {
    let lastSyncAt: Int?
    let lastError: String?
    let lastErrorSource: String?
    let lastRemoteEtag: String?
    let lastLocalManifestHash: String?
    let lastRemoteManifestHash: String?
}

struct WebDAVRemoteInfo: Codable, Equatable {
    let empty: Bool?
    let deviceName: String?
    let createdAt: Int?
    let snapshotId: String?
    let version: Int?
    let protocolVersion: Int?
    let dbCompatVersion: Int?
    let compatible: Bool?
    let artifacts: [String]?
    let layout: String?
    let remotePath: String?
}

struct WebDAVSyncPlan: Codable, Equatable {
    let available: Bool
    let readiness: String
    let summary: String
    let blockedBy: [String]
    let safeActions: [String]
    let requiresSubmoduleApi: Bool
}

enum SecurityScanStatus: String, Codable, Equatable {
    case verified
    case warning
    case blocked
    case unavailable
}

struct SecurityScanResult: Codable, Equatable {
    let scanner: String
    let status: SecurityScanStatus
    let summary: String
    let exitCode: Int?
    let stdout: String
    let stderr: String
    let scannedAt: Int
}

struct SecurityScanRecord: Codable, Equatable {
    let skillId: String
    let skillDirectory: String
    let result: SecurityScanResult
}

struct SkillApps: Codable, Equatable {
    var claude: Bool
    var codex: Bool
    var gemini: Bool
    var opencode: Bool
    var hermes: Bool

    func isEnabled(_ app: TargetApp) -> Bool {
        switch app {
        case .claude: claude
        case .codex: codex
        case .gemini: gemini
        case .opencode: opencode
        case .hermes: hermes
        }
    }

    mutating func setEnabled(_ enabled: Bool, for app: TargetApp) {
        switch app {
        case .claude: claude = enabled
        case .codex: codex = enabled
        case .gemini: gemini = enabled
        case .opencode: opencode = enabled
        case .hermes: hermes = enabled
        }
    }
}

struct UnmanagedSkill: Identifiable, Codable, Equatable {
    var id: String { directory }

    let directory: String
    let name: String
    let description: String
    let foundIn: [String]
    let path: String
}

struct SkillUpdateInfo: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let currentHash: String?
    let remoteHash: String
}

extension SkillUpdateInfo {
    var normalizedIdentifierCandidates: Set<String> {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedID.isEmpty else {
            return []
        }

        var candidates: Set<String> = [normalizedID]
        if let scopedSuffix = normalizedID.split(separator: ":").last {
            candidates.insert(String(scopedSuffix))
        }
        if let pathSuffix = normalizedID.split(separator: "/").last {
            candidates.insert(String(pathSuffix))
        }
        return candidates
    }
}

extension PackageComponent {
    func matchesSkillUpdate(_ update: SkillUpdateInfo) -> Bool {
        guard kind.caseInsensitiveCompare("skill") == .orderedSame else {
            return false
        }

        let candidates = update.normalizedIdentifierCandidates
        let componentID = id.lowercased()
        if candidates.contains(componentID) {
            return true
        }

        if let location = location?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !location.isEmpty,
           candidates.contains(location) {
            return true
        }

        return name.caseInsensitiveCompare(update.name) == .orderedSame
    }
}

extension CapabilityPackage {
    func matchingSkillComponent(for update: SkillUpdateInfo) -> PackageComponent? {
        components.skills.first { $0.matchesSkillUpdate(update) }
    }
}

struct CLIResponse<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: CLIErrorPayload?
}

struct CLIErrorPayload: Decodable, Equatable, LocalizedError {
    let code: String
    let message: String

    var errorDescription: String? {
        message
    }
}
