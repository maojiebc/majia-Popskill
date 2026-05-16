import SwiftUI

/// Sources — GitHub / npm / ClawHub / local folder source management (S5).
struct SourcesView: View {
    let store: PopskillStore

    var body: some View {
        PlaceholderView(
            symbol: "shippingbox",
            titleKey: "sidebar.sources",
            sprintLabel: "S5 实现 · GitHub / npm / ClawHub / 本地"
        )
    }
}
