import Foundation

struct UsageSummary: Equatable {
    var filesScanned = 0
    var sessions = 0
    var usageEvents = 0
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cacheCreationTokens: Int64 = 0
    var cacheReadTokens: Int64 = 0
    var attributedSkillUsageEvents = 0
    var modelStats: [ModelUsageStat] = []
    var skillStats: [SkillUsageStat] = []
    var recentSessions: [SessionUsageStat] = []

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var unattributedUsageEvents: Int {
        max(0, usageEvents - attributedSkillUsageEvents)
    }
}

struct ModelUsageStat: Identifiable, Equatable {
    var id: String { model }

    let model: String
    var usageEvents: Int
    var inputTokens: Int64
    var outputTokens: Int64
    var cacheCreationTokens: Int64
    var cacheReadTokens: Int64

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}

struct SessionUsageStat: Identifiable, Equatable {
    var id: String { sessionID }

    let sessionID: String
    var projectName: String
    var startedAt: Date?
    var lastActivityAt: Date?
    var usageEvents: Int
    var inputTokens: Int64
    var outputTokens: Int64
    var cacheCreationTokens: Int64
    var cacheReadTokens: Int64

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    mutating func observe(timestamp: Date?) {
        guard let timestamp else {
            return
        }

        if startedAt.map({ timestamp < $0 }) ?? true {
            startedAt = timestamp
        }
        if lastActivityAt.map({ timestamp > $0 }) ?? true {
            lastActivityAt = timestamp
        }
    }

    mutating func addUsage(
        inputTokens: Int64,
        outputTokens: Int64,
        cacheCreationTokens: Int64,
        cacheReadTokens: Int64
    ) {
        usageEvents += 1
        self.inputTokens += inputTokens
        self.outputTokens += outputTokens
        self.cacheCreationTokens += cacheCreationTokens
        self.cacheReadTokens += cacheReadTokens
    }
}

struct SkillUsageStat: Identifiable, Equatable {
    var id: String { skillID }

    let skillID: String
    var sourcePlugin: String?
    var usageEvents: Int
    var inputTokens: Int64
    var outputTokens: Int64
    var cacheCreationTokens: Int64
    var cacheReadTokens: Int64
    var lastUsedAt: Date?

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    mutating func addUsage(
        inputTokens: Int64,
        outputTokens: Int64,
        cacheCreationTokens: Int64,
        cacheReadTokens: Int64,
        timestamp: Date?
    ) {
        usageEvents += 1
        self.inputTokens += inputTokens
        self.outputTokens += outputTokens
        self.cacheCreationTokens += cacheCreationTokens
        self.cacheReadTokens += cacheReadTokens

        guard let timestamp else {
            return
        }
        if lastUsedAt.map({ timestamp > $0 }) ?? true {
            lastUsedAt = timestamp
        }
    }
}
