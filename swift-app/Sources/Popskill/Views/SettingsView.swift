import SwiftUI

/// Settings — general / sync / data / diagnostics / about / danger zone (S5).
struct SettingsView: View {
    let store: PopskillStore

    var body: some View {
        PlaceholderView(
            symbol: "gearshape",
            titleKey: "sidebar.settings",
            sprintLabel: "S5 实现 · 6 卡片 · 含 iCloud / Git / WebDAV 4 provider 同步"
        )
    }
}
