import SwiftUI

struct PlaceholderView: View {
    let selection: SidebarSelection

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: selection.symbolName)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(selection.title)
                .font(.system(.largeTitle, weight: .bold))

            Text(statusText)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.popMainBackground)
    }

    private var statusText: String {
        switch selection {
        case .featured, .categories, .topCharts:
            "Discover scaffolding is next"
        case .updates, .backups, .recentlyUsed, .stubs:
            "Library filters are next"
        case .usage, .tokenSpend, .idleCandidates:
            "Transcript insights are next"
        case .settings:
            "Settings are next"
        case .installed:
            "Installed"
        }
    }
}
