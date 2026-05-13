import Foundation

enum TargetApp: String, CaseIterable, Identifiable, Codable {
    case claude
    case codex
    case gemini
    case opencode
    case hermes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .opencode: "OpenCode"
        case .hermes: "Hermes"
        }
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

    var sourceLabel: String {
        if let repoOwner, let repoName, !repoOwner.isEmpty, !repoName.isEmpty {
            return "\(repoOwner)/\(repoName)"
        }
        return directory
    }

    var sourceURL: URL? {
        explicitOrRepositoryURL(readmeUrl: readmeUrl, repoOwner: repoOwner, repoName: repoName)
    }

    var enabledAppCount: Int {
        TargetApp.allCases.filter { apps.isEnabled($0) }.count
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
