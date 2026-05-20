import Foundation
@testable import Popskill
import Testing

struct TranscriptUsageScannerTests {
    @Test
    func aggregatesUsageWithoutReadingMessageText() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let transcript = project.appendingPathComponent("session.jsonl")
        let lines = [
            #"{"type":"user","sessionId":"s1","timestamp":"2026-05-12T01:00:00.000Z","message":{"role":"user","content":"private text"}}"#,
            #"{"type":"assistant","sessionId":"s1","timestamp":"2026-05-12T01:01:00.000Z","message":{"role":"assistant","model":"claude-opus","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":3,"cache_read_input_tokens":7}}}"#,
            #"{"type":"assistant","sessionId":"s2","timestamp":"2026-05-12T02:00:00.000Z","message":{"role":"assistant","model":"claude-sonnet","usage":{"input_tokens":4,"output_tokens":6}}}"#,
        ]
        try lines.joined(separator: "\n").write(to: transcript, atomically: true, encoding: .utf8)

        let summary = try TranscriptUsageScanner(projectsURL: root).scan()

        #expect(summary.filesScanned == 1)
        #expect(summary.sessions == 2)
        #expect(summary.usageEvents == 2)
        #expect(summary.inputTokens == 14)
        #expect(summary.outputTokens == 11)
        #expect(summary.cacheCreationTokens == 3)
        #expect(summary.cacheReadTokens == 7)
        #expect(summary.totalTokens == 35)
        #expect(summary.modelStats.map(\.model) == ["claude-opus", "claude-sonnet"])
        #expect(summary.modelStats.first?.totalTokens == 25)
        #expect(summary.recentSessions.map(\.sessionID) == ["s2", "s1"])
        #expect(summary.recentSessions.first?.totalTokens == 10)
        #expect(summary.recentSessions.first?.usageEvents == 1)
        #expect(summary.recentSessions.last?.projectName == "project")
    }

    @Test
    func derivesReadableProjectNameFromEncodedClaudePath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("-Users-majia-projects-popskill", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let transcript = project.appendingPathComponent("session.jsonl")
        let line = #"{"type":"user","sessionId":"s1","timestamp":"2026-05-12T01:00:00.000Z","message":{"role":"user","content":"private text"}}"#
        try line.write(to: transcript, atomically: true, encoding: .utf8)

        let summary = try TranscriptUsageScanner(projectsURL: root).scan()

        #expect(summary.recentSessions.first?.projectName == "projects/popskill")
    }

    @Test
    func prefersCWDForReadableProjectName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("-Users-majia-projects-skill-creator", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let transcript = project.appendingPathComponent("session.jsonl")
        let line = #"{"type":"user","sessionId":"s1","timestamp":"2026-05-12T01:00:00.000Z","cwd":"/Users/example/projects/skill-creator","message":{"role":"user","content":"private text"}}"#
        try line.write(to: transcript, atomically: true, encoding: .utf8)

        let summary = try TranscriptUsageScanner(projectsURL: root).scan()

        #expect(summary.recentSessions.first?.projectName == "projects/skill-creator")
    }

    @Test
    func aggregatesSkillAttributionWithoutReadingMessageText() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let transcript = project.appendingPathComponent("session.jsonl")
        let lines = [
            #"{"type":"assistant","sessionId":"s1","timestamp":"2026-05-12T01:01:00.000Z","attributionSkill":"baoyu-image-gen","attributionPlugin":"baoyu-skills","message":{"role":"assistant","model":"claude-opus","content":"private text","usage":{"input_tokens":10,"output_tokens":5}}}"#,
            #"{"type":"assistant","sessionId":"s1","timestamp":"2026-05-12T01:05:00.000Z","attributionSkill":"baoyu-image-gen","attributionPlugin":"baoyu-skills","message":{"role":"assistant","model":"claude-opus","content":"more private text","usage":{"input_tokens":3,"output_tokens":2,"cache_read_input_tokens":4}}}"#,
            #"{"type":"assistant","sessionId":"s1","timestamp":"2026-05-12T01:08:00.000Z","message":{"role":"assistant","model":"claude-opus","usage":{"input_tokens":7,"output_tokens":1}}}"#,
            #"{"type":"assistant","sessionId":"s1","timestamp":"2026-05-12T01:09:00.000Z","attributionSkill":"ignored-no-usage","message":{"role":"assistant","content":"private text"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: transcript, atomically: true, encoding: .utf8)

        let summary = try TranscriptUsageScanner(projectsURL: root).scan()

        #expect(summary.usageEvents == 3)
        #expect(summary.attributedSkillUsageEvents == 2)
        #expect(summary.unattributedUsageEvents == 1)
        #expect(summary.skillStats.map(\.skillID) == ["baoyu-image-gen"])

        let stat = try #require(summary.skillStats.first)
        #expect(stat.sourcePlugin == "baoyu-skills")
        #expect(stat.usageEvents == 2)
        #expect(stat.inputTokens == 13)
        #expect(stat.outputTokens == 7)
        #expect(stat.cacheReadTokens == 4)
        #expect(stat.totalTokens == 24)
        #expect(stat.lastUsedAt != nil)
    }

    @Test
    func recentThirtyDayWindowAggregatesOnlyRecentUsage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let transcript = project.appendingPathComponent("session.jsonl")
        let lines = [
            #"{"type":"assistant","sessionId":"recent","timestamp":"2026-05-12T01:01:00.000Z","attributionSkill":"recent-skill","message":{"role":"assistant","model":"claude-opus","usage":{"input_tokens":10,"output_tokens":5}}}"#,
            #"{"type":"assistant","sessionId":"recent","timestamp":"2026-05-13T02:01:00.000Z","attributionSkill":"recent-skill","message":{"role":"assistant","model":"claude-opus","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            #"{"type":"assistant","sessionId":"old","timestamp":"2026-03-01T01:01:00.000Z","attributionSkill":"old-skill","message":{"role":"assistant","model":"claude-sonnet","usage":{"input_tokens":90,"output_tokens":10}}}"#
        ]
        try lines.joined(separator: "\n").write(to: transcript, atomically: true, encoding: .utf8)

        let referenceDate = try #require(Self.iso8601.date(from: "2026-05-20T00:00:00Z"))
        let summary = try TranscriptUsageScanner(projectsURL: root, referenceDate: referenceDate).scan()

        #expect(summary.usageEvents == 3)
        #expect(summary.totalTokens == 117)
        #expect(summary.skillStats.map(\.skillID) == ["old-skill", "recent-skill"])
        #expect(summary.recent30Days?.days == 30)
        #expect(summary.recent30Days?.usageEvents == 2)
        #expect(summary.recent30Days?.totalTokens == 17)
        #expect(summary.recent30Days?.skillStats.map(\.skillID) == ["recent-skill"])
        #expect(summary.recent30Days?.modelStats.map(\.model) == ["claude-opus"])

        let dailyStats = try #require(summary.recent30Days?.dailyStats)
        #expect(dailyStats.map(\.usageEvents) == [1, 1])
        #expect(dailyStats.map(\.totalTokens) == [15, 2])

        let skillDailyStats = try #require(summary.recent30Days?.skillStats.first?.dailyStats)
        #expect(skillDailyStats.map(\.usageEvents) == [1, 1])
        #expect(skillDailyStats.map(\.totalTokens) == [15, 2])
    }

    @Test
    func streamsCRLFLinesAndSkipsMalformedRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let transcript = project.appendingPathComponent("session.jsonl")
        let lines = [
            #"{"type":"assistant","sessionId":"s1","timestamp":"2026-05-12T01:01:00.000Z","message":{"role":"assistant","model":"claude-opus","usage":{"input_tokens":2,"output_tokens":3}}}"#,
            #"not json"#,
            #"{"type":"assistant","sessionId":"s1","timestamp":"2026-05-12T01:02:00.000Z","message":{"role":"assistant","model":"claude-opus","usage":{"input_tokens":4,"output_tokens":5}}}"#,
        ]
        try lines.joined(separator: "\r\n").write(to: transcript, atomically: true, encoding: .utf8)

        let summary = try TranscriptUsageScanner(projectsURL: root).scan()

        #expect(summary.filesScanned == 1)
        #expect(summary.sessions == 1)
        #expect(summary.usageEvents == 2)
        #expect(summary.inputTokens == 6)
        #expect(summary.outputTokens == 8)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
