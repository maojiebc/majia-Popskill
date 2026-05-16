import SwiftUI

/// Updates — list of skills with newer upstream content (S5).
struct UpdatesView: View {
    let store: PopskillStore

    var body: some View {
        PlaceholderView(
            symbol: "arrow.down.circle",
            titleKey: "sidebar.updates",
            sprintLabel: "S5 实现 · 上游更新列表 + 单条/全部更新"
        )
    }
}
