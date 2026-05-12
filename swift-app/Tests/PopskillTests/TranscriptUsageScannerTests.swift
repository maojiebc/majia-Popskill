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
            #"{"type":"user","sessionId":"s1","message":{"role":"user","content":"private text"}}"#,
            #"{"type":"assistant","sessionId":"s1","message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":3,"cache_read_input_tokens":7}}}"#,
            #"{"type":"assistant","sessionId":"s2","message":{"role":"assistant","usage":{"input_tokens":4,"output_tokens":6}}}"#,
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
    }
}
