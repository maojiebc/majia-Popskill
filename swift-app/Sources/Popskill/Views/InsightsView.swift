import SwiftUI

/// Insights — transcript-derived token / call usage (S5).
struct InsightsView: View {
    let store: PopskillStore

    var body: some View {
        PlaceholderView(
            symbol: "chart.bar",
            titleKey: "sidebar.insights",
            sprintLabel: "S5 实现 · 4 hero metric + Top 10 + Claude vs Codex split"
        )
    }
}
