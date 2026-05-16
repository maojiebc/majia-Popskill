import SwiftUI

/// Backups — uninstall snapshots grouped by time (S5).
struct BackupsView: View {
    let store: PopskillStore

    var body: some View {
        PlaceholderView(
            symbol: "clock.arrow.circlepath",
            titleKey: "sidebar.backups",
            sprintLabel: "S5 实现 · 按时间分组 · 恢复 / 查看 / 删除"
        )
    }
}
