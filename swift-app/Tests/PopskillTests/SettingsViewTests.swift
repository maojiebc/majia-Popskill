@testable import Popskill
import Testing

struct SettingsViewTests {
    @Test
    func syncProviderActionableOnlyAllowsImplementedProviders() {
        #expect(SyncProvider.git.actionable)
        #expect(SyncProvider.icloud.actionable)
        #expect(!SyncProvider.webdav.actionable)
        #expect(!SyncProvider.none.actionable)
    }

    @Test
    func syncSummaryUsesStderrAndExitCodeForCommandFailures() {
        let result = SyncResult(
            provider: "icloud",
            action: "push",
            ok: false,
            exitCode: 23,
            stdout: "",
            stderr: "rsync: permission denied\n",
            message: nil
        )

        let summary = result.summary(successMessage: "Done", emptyMessage: "No details")

        #expect(summary.state == .failure)
        #expect(summary.message == "rsync: permission denied")
        #expect(summary.details == [.exitCode(23)])
    }

    @Test
    func syncSummarySurfacesICloudStatusEndpoints() {
        let result = SyncResult(
            provider: "icloud",
            action: "status",
            ok: true,
            localPath: "/Users/me/.cc-switch/skills",
            remotePath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Popskill/skills",
            localCount: 8,
            remoteCount: 6
        )

        let summary = result.summary(successMessage: "Status checked", emptyMessage: "No details")

        #expect(summary.state == .success)
        #expect(summary.message == "Status checked")
        #expect(summary.details == [
            .localEndpoint(path: "/Users/me/.cc-switch/skills", count: 8),
            .remoteEndpoint(path: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Popskill/skills", count: 6)
        ])
    }

    @Test
    func syncSummaryTreatsUnimplementedProviderAsUnavailable() {
        let result = SyncResult(
            provider: "webdav",
            action: "push",
            message: "WebDAV sync is not available",
            implemented: false
        )

        let summary = result.summary(successMessage: "Done", emptyMessage: "No details")

        #expect(summary.state == .unavailable)
        #expect(summary.message == "WebDAV sync is not available")
        #expect(summary.details.isEmpty)
    }
}
