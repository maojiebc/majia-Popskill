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
        if let repoOwner, let repoName {
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
        if let repoOwner, let repoName {
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
    if let readmeUrl, let url = URL(string: readmeUrl) {
        return url
    }

    guard let repoOwner, let repoName else {
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

struct SkillUninstallResult: Codable, Equatable {
    let backupPath: String?
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
