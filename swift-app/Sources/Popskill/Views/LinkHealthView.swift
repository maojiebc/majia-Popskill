import SwiftUI

/// Link health — symlink status across every installed skill (S5, new view).
struct LinkHealthView: View {
    let store: PopskillStore

    var body: some View {
        PlaceholderView(
            symbol: "checkmark.shield",
            titleKey: "sidebar.health",
            sprintLabel: "S5 实现 · 链接健康表 · 全部修复 / 单条修复"
        )
    }
}
