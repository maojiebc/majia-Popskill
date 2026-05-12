import Foundation

struct UsageSummary: Equatable {
    var filesScanned = 0
    var sessions = 0
    var usageEvents = 0
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cacheCreationTokens: Int64 = 0
    var cacheReadTokens: Int64 = 0
    var modelStats: [ModelUsageStat] = []

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
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
