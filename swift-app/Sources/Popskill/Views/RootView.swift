import SwiftUI

/// New v0.3 RootView — replaces the 11→7 sidebar single-flat list of v0.1-v0.2
/// with 3 sectioned groups (操控台 / 来源 / 维护) + Settings + Spotlight trigger.
/// Each detail-area view is its own file and pulls data straight off the
/// shared `PopskillStore`.
struct RootView: View {
    @State private var store = PopskillStore()
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailArea
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await store.bootstrap()
        }
        .background(PopskillCanvasBackground())
        .frame(minWidth: 1180, minHeight: 720)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: Binding(
            get: { store.currentSelection },
            set: { if let new = $0 { store.currentSelection = new } }
        )) {
            Section {
                row(.matrix)
            } header: { sectionHeader(.control) }

            Section {
                row(.sources)
            } header: { sectionHeader(.sources) }

            Section {
                row(.updates, badge: store.pendingUpdateCount, warning: true)
                row(.backups, badge: store.backups.count)
                row(.idle)
                row(.insights)
                row(.health, badge: store.brokenLinkCount, warning: store.brokenLinkCount > 0)
            } header: { sectionHeader(.maintenance) }

            Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
    }

    @ViewBuilder
    private func sectionHeader(_ group: SidebarGroup) -> some View {
        if let key = group.titleKey {
            LocalizedText(key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.popTertiaryLabel)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    @ViewBuilder
    private func row(_ item: SidebarSelection, badge: Int? = nil, warning: Bool = false) -> some View {
        NavigationLink(value: item) {
            HStack(spacing: 9) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18)
                LocalizedText(item.titleKey)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(warning ? Color.popStatusWarning : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                (warning ? Color.popStatusWarning : Color.secondary).opacity(0.14)
                            )
                        )
                }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detailArea: some View {
        switch store.currentSelection {
        case .matrix:   MatrixView(store: store)
        case .sources:  SourcesView(store: store)
        case .updates:  UpdatesView(store: store)
        case .backups:  BackupsView(store: store)
        case .idle:     IdleView(store: store)
        case .insights: InsightsView(store: store)
        case .health:   LinkHealthView(store: store)
        case .settings: SettingsView(store: store)
        }
    }
}
