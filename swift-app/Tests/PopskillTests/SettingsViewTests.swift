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
}
