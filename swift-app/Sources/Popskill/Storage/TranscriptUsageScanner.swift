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

        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return summary
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            summary.filesScanned += 1
            try scan(fileURL: fileURL, summary: &summary, sessionIDs: &sessionIDs)
        }

        summary.sessions = sessionIDs.count
        return summary
    }

    private func scan(fileURL: URL, summary: inout UsageSummary, sessionIDs: inout Set<String>) throws {
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
            summary.inputTokens += int64Value(usage["input_tokens"])
            summary.outputTokens += int64Value(usage["output_tokens"])
            summary.cacheCreationTokens += int64Value(usage["cache_creation_input_tokens"])
            summary.cacheReadTokens += int64Value(usage["cache_read_input_tokens"])
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
