@testable import Popskill
import Testing

struct SpotlightActionTests {
    @Test
    func spotlightActionsExposeUsageScan() {
        #expect(SpotlightAction.all.map(\.id).contains("usage-scan"))

        let usageScan = SpotlightAction.all.first { $0.id == "usage-scan" }
        #expect(usageScan?.titleKey == "spotlight.action.usageScan.title")
        #expect(usageScan?.subtitleKey == "spotlight.action.usageScan.subtitle")
    }
}
