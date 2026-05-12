import Foundation

struct TranscriptUsageScanner {
    private let projectsURL: URL

    init(projectsURL: URL? = nil) {
        self.projectsURL = projectsURL
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".claude")
                .appendingPathComponent("projects")
    }

    func scan() throws -> UsageSummary {
        var summary = UsageSummary()
        var sessionIDs = Set<String>()
        var modelStats: [String: ModelUsageStat] = [:]

        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return summary
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            summary.filesScanned += 1
            try scan(
                fileURL: fileURL,
                summary: &summary,
                sessionIDs: &sessionIDs,
                modelStats: &modelStats
            )
        }

        summary.sessions = sessionIDs.count
        summary.modelStats = modelStats.values.sorted {
            if $0.totalTokens == $1.totalTokens {
                return $0.model < $1.model
            }
            return $0.totalTokens > $1.totalTokens
        }
        return summary
    }

    private func scan(
        fileURL: URL,
        summary: inout UsageSummary,
        sessionIDs: inout Set<String>,
        modelStats: inout [String: ModelUsageStat]
    ) throws {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard let content = String(data: data, encoding: .utf8) else {
            return
        }

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                continue
            }

            if let sessionID = object["sessionId"] as? String {
                sessionIDs.insert(sessionID)
            }

            guard let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else {
                continue
            }

            summary.usageEvents += 1
            let inputTokens = int64Value(usage["input_tokens"])
            let outputTokens = int64Value(usage["output_tokens"])
            let cacheCreationTokens = int64Value(usage["cache_creation_input_tokens"])
            let cacheReadTokens = int64Value(usage["cache_read_input_tokens"])

            summary.inputTokens += inputTokens
            summary.outputTokens += outputTokens
            summary.cacheCreationTokens += cacheCreationTokens
            summary.cacheReadTokens += cacheReadTokens

            let model = (message["model"] as? String) ?? "unknown"
            var stat = modelStats[model] ?? ModelUsageStat(
                model: model,
                usageEvents: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            )
            stat.usageEvents += 1
            stat.inputTokens += inputTokens
            stat.outputTokens += outputTokens
            stat.cacheCreationTokens += cacheCreationTokens
            stat.cacheReadTokens += cacheReadTokens
            modelStats[model] = stat
        }
    }

    private func int64Value(_ value: Any?) -> Int64 {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        return 0
    }
}
