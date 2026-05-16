import SwiftUI

/// Idle candidates — 60+ days no use (S5).
struct IdleView: View {
    let store: PopskillStore

    var body: some View {
        PlaceholderView(
            symbol: "pause.circle",
            titleKey: "sidebar.idle",
            sprintLabel: "S5 实现 · 闲置卡片 · 保留 / 变 stub / 卸载"
        )
    }
}
