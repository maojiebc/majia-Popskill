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
        var modelStats: [String: ModelUsageStat] = [:]
        var skillStats: [String: SkillUsageStat] = [:]
        var sessionStats: [String: SessionUsageStat] = [:]

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
                modelStats: &modelStats,
                skillStats: &skillStats,
                sessionStats: &sessionStats
            )
        }

        summary.sessions = sessionStats.count
        summary.modelStats = modelStats.values.sorted {
            if $0.totalTokens == $1.totalTokens {
                return $0.model < $1.model
            }
            return $0.totalTokens > $1.totalTokens
        }
        summary.skillStats = skillStats.values.sorted {
            if $0.totalTokens == $1.totalTokens {
                return $0.skillID < $1.skillID
            }
            return $0.totalTokens > $1.totalTokens
        }
        summary.recentSessions = sessionStats.values.sorted {
            switch ($0.lastActivityAt, $1.lastActivityAt) {
            case let (left?, right?):
                if left == right {
                    return $0.sessionID < $1.sessionID
                }
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return $0.sessionID < $1.sessionID
            }
        }
        return summary
    }

    private func scan(
        fileURL: URL,
        summary: inout UsageSummary,
        modelStats: inout [String: ModelUsageStat],
        skillStats: inout [String: SkillUsageStat],
        sessionStats: inout [String: SessionUsageStat]
    ) throws {
        let projectName = projectName(for: fileURL)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var buffer = Data()
        while true {
            let chunk = try handle.read(upToCount: Self.readChunkSize) ?? Data()
            if chunk.isEmpty { break }

            buffer.append(chunk)
            while let newlineRange = buffer.firstRange(of: Self.newlineData) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                parseLine(
                    lineData,
                    projectName: projectName,
                    summary: &summary,
                    modelStats: &modelStats,
                    skillStats: &skillStats,
                    sessionStats: &sessionStats
                )
                buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
            }
        }

        if !buffer.isEmpty {
            parseLine(
                buffer,
                projectName: projectName,
                summary: &summary,
                modelStats: &modelStats,
                skillStats: &skillStats,
                sessionStats: &sessionStats
            )
        }
    }

    private func parseLine(
        _ rawLineData: Data,
        projectName: String,
        summary: inout UsageSummary,
        modelStats: inout [String: ModelUsageStat],
        skillStats: inout [String: SkillUsageStat],
        sessionStats: inout [String: SessionUsageStat]
    ) {
        if rawLineData.isEmpty { return }

        var lineData = rawLineData
        if lineData.last == Self.carriageReturnByte {
            lineData.removeLast()
        }

        guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return
        }

        let sessionID = object["sessionId"] as? String
        let timestamp = dateValue(object["timestamp"])
        let cwdProjectName = projectNameFromCWD(object["cwd"] as? String)
        if let sessionID {
            var session = sessionStats[sessionID] ?? SessionUsageStat(
                sessionID: sessionID,
                projectName: cwdProjectName ?? projectName,
                startedAt: nil,
                lastActivityAt: nil,
                usageEvents: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            )
            if let cwdProjectName {
                session.projectName = cwdProjectName
            }
            session.observe(timestamp: timestamp)
            sessionStats[sessionID] = session
        }

        guard let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else {
            return
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

        if let sessionID {
            var session = sessionStats[sessionID] ?? SessionUsageStat(
                sessionID: sessionID,
                projectName: cwdProjectName ?? projectName,
                startedAt: timestamp,
                lastActivityAt: timestamp,
                usageEvents: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            )
            if let cwdProjectName {
                session.projectName = cwdProjectName
            }
            session.observe(timestamp: timestamp)
            session.addUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens
            )
            sessionStats[sessionID] = session
        }

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

        if let attributionSkill = attributionIdentifier(object["attributionSkill"]) {
            summary.attributedSkillUsageEvents += 1
            var skillStat = skillStats[attributionSkill] ?? SkillUsageStat(
                skillID: attributionSkill,
                sourcePlugin: stringValue(object["attributionPlugin"]),
                usageEvents: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0,
                lastUsedAt: nil
            )
            if skillStat.sourcePlugin == nil {
                skillStat.sourcePlugin = stringValue(object["attributionPlugin"])
            }
            skillStat.addUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens,
                timestamp: timestamp
            )
            skillStats[attributionSkill] = skillStat
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

    private func dateValue(_ value: Any?) -> Date? {
        guard let timestamp = value as? String else {
            return nil
        }

        if let date = Self.iso8601WithFractionalSeconds.date(from: timestamp) {
            return date
        }
        return Self.iso8601.date(from: timestamp)
    }

    private func attributionIdentifier(_ value: Any?) -> String? {
        if let value = stringValue(value) {
            return value
        }

        guard let object = value as? [String: Any] else {
            return nil
        }

        return stringValue(object["id"])
            ?? stringValue(object["name"])
            ?? stringValue(object["command"])
            ?? stringValue(object["path"])
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func projectName(for fileURL: URL) -> String {
        let folderName = fileURL.deletingLastPathComponent().lastPathComponent
        let parts = folderName
            .split(separator: "-")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard parts.count >= 2 else {
            return folderName
        }

        return parts.suffix(2).joined(separator: "/")
    }

    private func projectNameFromCWD(_ cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: cwd)
        let project = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        if parent.isEmpty {
            return project
        }
        return "\(parent)/\(project)"
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let readChunkSize = 64 * 1024
    private static let newlineData = Data([0x0A])
    private static let carriageReturnByte: UInt8 = 0x0D
}
