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
    var recent30Days: UsageWindowSummary?

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var unattributedUsageEvents: Int {
        max(0, usageEvents - attributedSkillUsageEvents)
    }

    var thirtyDayTotalTokens: Int64 {
        recent30Days?.totalTokens ?? totalTokens
    }

    var thirtyDaySkillStats: [SkillUsageStat] {
        recent30Days?.skillStats ?? skillStats
    }
}

struct UsageWindowSummary: Equatable {
    let days: Int
    let startedAt: Date
    let endedAt: Date
    var usageEvents = 0
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cacheCreationTokens: Int64 = 0
    var cacheReadTokens: Int64 = 0
    var attributedSkillUsageEvents = 0
    var modelStats: [ModelUsageStat] = []
    var skillStats: [SkillUsageStat] = []
    var dailyStats: [UsageBucketStat] = []

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var unattributedUsageEvents: Int {
        max(0, usageEvents - attributedSkillUsageEvents)
    }

    mutating func addUsage(
        inputTokens: Int64,
        outputTokens: Int64,
        cacheCreationTokens: Int64,
        cacheReadTokens: Int64,
        dayStart: Date
    ) {
        usageEvents += 1
        self.inputTokens += inputTokens
        self.outputTokens += outputTokens
        self.cacheCreationTokens += cacheCreationTokens
        self.cacheReadTokens += cacheReadTokens
        Self.mergeDailyStat(
            UsageBucketStat(
                dayStart: dayStart,
                usageEvents: 1,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens
            ),
            into: &dailyStats
        )
    }

    static func mergeDailyStat(_ stat: UsageBucketStat, into stats: inout [UsageBucketStat]) {
        if let index = stats.firstIndex(where: { $0.dayStart == stat.dayStart }) {
            stats[index].add(stat)
        } else {
            stats.append(stat)
        }
        stats.sort { $0.dayStart < $1.dayStart }
    }
}

struct UsageBucketStat: Identifiable, Equatable {
    var id: Date { dayStart }

    let dayStart: Date
    var usageEvents: Int
    var inputTokens: Int64
    var outputTokens: Int64
    var cacheCreationTokens: Int64
    var cacheReadTokens: Int64

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    mutating func add(_ stat: UsageBucketStat) {
        usageEvents += stat.usageEvents
        inputTokens += stat.inputTokens
        outputTokens += stat.outputTokens
        cacheCreationTokens += stat.cacheCreationTokens
        cacheReadTokens += stat.cacheReadTokens
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
    var dailyStats: [UsageBucketStat] = []

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    mutating func addUsage(
        inputTokens: Int64,
        outputTokens: Int64,
        cacheCreationTokens: Int64,
        cacheReadTokens: Int64,
        timestamp: Date?,
        dayStart: Date? = nil
    ) {
        usageEvents += 1
        self.inputTokens += inputTokens
        self.outputTokens += outputTokens
        self.cacheCreationTokens += cacheCreationTokens
        self.cacheReadTokens += cacheReadTokens

        if let dayStart {
            UsageWindowSummary.mergeDailyStat(
                UsageBucketStat(
                    dayStart: dayStart,
                    usageEvents: 1,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheCreationTokens: cacheCreationTokens,
                    cacheReadTokens: cacheReadTokens
                ),
                into: &dailyStats
            )
        }

        guard let timestamp else {
            return
        }
        if lastUsedAt.map({ timestamp > $0 }) ?? true {
            lastUsedAt = timestamp
        }
    }
}

struct SkillUsageSnapshot: Equatable {
    var usageEvents = 0
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cacheCreationTokens: Int64 = 0
    var cacheReadTokens: Int64 = 0
    var lastUsedAt: Date?
    var dailyStats: [UsageBucketStat] = []

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var hasUsage: Bool {
        usageEvents > 0 || totalTokens > 0
    }

    mutating func add(_ stat: SkillUsageStat) {
        usageEvents += stat.usageEvents
        inputTokens += stat.inputTokens
        outputTokens += stat.outputTokens
        cacheCreationTokens += stat.cacheCreationTokens
        cacheReadTokens += stat.cacheReadTokens
        mergeDailyStats(stat.dailyStats)

        guard let date = stat.lastUsedAt else {
            return
        }
        if lastUsedAt.map({ date > $0 }) ?? true {
            lastUsedAt = date
        }
    }

    mutating func mergeDailyStats(_ stats: [UsageBucketStat]) {
        for stat in stats {
            UsageWindowSummary.mergeDailyStat(stat, into: &dailyStats)
        }
    }
}

struct MatrixUsageIndex: Equatable {
    let hasSummary: Bool
    private var skillSnapshotsByID: [String: SkillUsageSnapshot] = [:]
    private var packageSnapshotsByID: [String: PackageUsageSnapshot] = [:]
    private var packageComponentStatsByID: [String: [String: PackageComponentUsageStat]] = [:]

    init(summary: UsageSummary?, skills: [Skill], packages: [CapabilityPackage]) {
        guard let summary else {
            hasSummary = false
            return
        }

        hasSummary = true

        for skill in skills {
            skillSnapshotsByID[skill.id] = skill.usageSnapshot(using: summary)
        }

        for package in packages {
            guard let snapshot = package.usageSnapshot(using: summary, skills: skills) else {
                continue
            }
            packageSnapshotsByID[package.id] = snapshot
            packageComponentStatsByID[package.id] = Dictionary(
                uniqueKeysWithValues: snapshot.componentStats.map { ($0.componentID, $0) }
            )
        }
    }

    func skillSnapshot(for skillID: String?) -> SkillUsageSnapshot? {
        guard hasSummary, let skillID else {
            return nil
        }
        return skillSnapshotsByID[skillID] ?? SkillUsageSnapshot()
    }

    func packageSnapshot(for packageID: String?) -> PackageUsageSnapshot? {
        guard hasSummary, let packageID else {
            return nil
        }
        return packageSnapshotsByID[packageID] ?? PackageUsageSnapshot()
    }

    func packageComponentStat(packageID: String?, componentID: String) -> PackageComponentUsageStat? {
        guard hasSummary, let packageID else {
            return nil
        }
        return packageComponentStatsByID[packageID]?[componentID]
    }
}

enum UsageDisplayFormatter {
    static func compactTokens(_ value: Int64) -> String {
        compact(Int(value))
    }

    static func compactCount(_ value: Int) -> String {
        compact(value)
    }

    private static func compact(_ value: Int) -> String {
        if value < 1_000 {
            return integerFormatter.string(from: NSNumber(value: value)) ?? "0"
        }
        if value < 1_000_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        if value < 1_000_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        return String(format: "%.2fB", Double(value) / 1_000_000_000.0)
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

struct PackageUsageSnapshot: Equatable {
    var matchedSkillCount = 0
    var usageEvents = 0
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cacheCreationTokens: Int64 = 0
    var cacheReadTokens: Int64 = 0
    var lastUsedAt: Date?
    var componentStats: [PackageComponentUsageStat] = []
    var dailyStats: [UsageBucketStat] = []

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var hasUsage: Bool {
        usageEvents > 0 || totalTokens > 0
    }

    mutating func add(_ stat: SkillUsageStat, component: PackageComponent) {
        matchedSkillCount += 1
        usageEvents += stat.usageEvents
        inputTokens += stat.inputTokens
        outputTokens += stat.outputTokens
        cacheCreationTokens += stat.cacheCreationTokens
        cacheReadTokens += stat.cacheReadTokens
        for bucket in stat.dailyStats {
            UsageWindowSummary.mergeDailyStat(bucket, into: &dailyStats)
        }
        upsertComponentStat(stat, component: component)

        guard let date = stat.lastUsedAt else {
            return
        }
        if lastUsedAt.map({ date > $0 }) ?? true {
            lastUsedAt = date
        }
    }

    private mutating func upsertComponentStat(_ stat: SkillUsageStat, component: PackageComponent) {
        if let index = componentStats.firstIndex(where: { $0.componentID == component.id }) {
            componentStats[index].add(stat)
        } else {
            componentStats.append(PackageComponentUsageStat(component: component, stat: stat))
        }

        componentStats.sort { lhs, rhs in
            if lhs.usageEvents != rhs.usageEvents { return lhs.usageEvents > rhs.usageEvents }
            if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
            return lhs.componentName.localizedCaseInsensitiveCompare(rhs.componentName) == .orderedAscending
        }
    }
}

struct PackageComponentUsageStat: Identifiable, Equatable {
    var id: String { componentID }

    let componentID: String
    let componentName: String
    let componentKind: String
    let installed: Bool
    var usageEvents: Int
    var inputTokens: Int64
    var outputTokens: Int64
    var cacheCreationTokens: Int64
    var cacheReadTokens: Int64
    var lastUsedAt: Date?
    var dailyStats: [UsageBucketStat]

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    init(component: PackageComponent, stat: SkillUsageStat) {
        componentID = component.id
        componentName = component.name
        componentKind = component.kind
        installed = component.installed
        usageEvents = stat.usageEvents
        inputTokens = stat.inputTokens
        outputTokens = stat.outputTokens
        cacheCreationTokens = stat.cacheCreationTokens
        cacheReadTokens = stat.cacheReadTokens
        lastUsedAt = stat.lastUsedAt
        dailyStats = stat.dailyStats
    }

    mutating func add(_ stat: SkillUsageStat) {
        usageEvents += stat.usageEvents
        inputTokens += stat.inputTokens
        outputTokens += stat.outputTokens
        cacheCreationTokens += stat.cacheCreationTokens
        cacheReadTokens += stat.cacheReadTokens
        for bucket in stat.dailyStats {
            UsageWindowSummary.mergeDailyStat(bucket, into: &dailyStats)
        }

        guard let date = stat.lastUsedAt else {
            return
        }
        if lastUsedAt.map({ date > $0 }) ?? true {
            lastUsedAt = date
        }
    }
}
