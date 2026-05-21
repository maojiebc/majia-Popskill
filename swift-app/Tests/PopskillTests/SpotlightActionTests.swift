@testable import Popskill
import Testing

struct SpotlightActionTests {
    @Test
    func spotlightActionsExposeUsageScan() {
        #expect(SpotlightAction.all.map(\.id).contains("usage-scan"))
        #expect(SpotlightAction.all.map(\.id).contains("show-bundles"))
        #expect(SpotlightAction.all.map(\.id).contains("show-skills"))
        #expect(SpotlightAction.all.map(\.id).contains("show-cli"))
        #expect(SpotlightAction.all.map(\.id).contains("show-mcp"))
        #expect(SpotlightAction.all.map(\.id).contains("show-broken-links"))
        #expect(SpotlightAction.all.map(\.id).contains("show-inactive"))

        let usageScan = SpotlightAction.all.first { $0.id == "usage-scan" }
        #expect(usageScan?.titleKey == "spotlight.action.usageScan.title")
        #expect(usageScan?.subtitleKey == "spotlight.action.usageScan.subtitle")
    }

    @MainActor
    @Test
    func spotlightMatrixFilterActionsOpenExpectedMatrixViews() {
        let store = PopskillStore()

        store.searchText = "baoyu"
        SpotlightAction.all.first { $0.id == "show-bundles" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixTypeFilter == .bundle)
        #expect(store.matrixFilter == .all)
        #expect(store.searchText.isEmpty)

        SpotlightAction.all.first { $0.id == "show-skills" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixTypeFilter == .skill)
        #expect(store.matrixFilter == .all)

        SpotlightAction.all.first { $0.id == "show-cli" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixTypeFilter == .cli)
        #expect(store.matrixFilter == .all)

        SpotlightAction.all.first { $0.id == "show-mcp" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixTypeFilter == .mcp)
        #expect(store.matrixFilter == .all)

        SpotlightAction.all.first { $0.id == "show-broken-links" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixFilter == .brokenLinks)
        #expect(store.matrixTypeFilter == .allTypes)

        SpotlightAction.all.first { $0.id == "show-inactive" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixFilter == .inactive)
        #expect(store.matrixTypeFilter == .allTypes)
    }
}
