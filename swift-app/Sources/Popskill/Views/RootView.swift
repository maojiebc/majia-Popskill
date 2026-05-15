import SwiftUI

enum SidebarSelection: String, CaseIterable, Identifiable {
    case repositories
    case installed
    case agents
    case backups
    case usage
    case idleCandidates
    case settings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .repositories: "sidebar.repositories"
        case .installed: "sidebar.installed"
        case .agents: "sidebar.agents"
        case .backups: "sidebar.backups"
        case .usage: "sidebar.usage"
        case .idleCandidates: "sidebar.idleCandidates"
        case .settings: "sidebar.settings"
        }
    }

    var symbolName: String {
        switch self {
        case .repositories: "folder.badge.gearshape"
        case .installed: "shippingbox"
        case .agents: "person.crop.circle"
        case .backups: "clock.arrow.circlepath"
        case .usage: "chart.xyaxis.line"
        case .idleCandidates: "archivebox"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @State private var selection: SidebarSelection?
    @AppStorage("preferredLanguage") private var preferredLanguage = AppLanguage.system.rawValue
    @State private var repositories = RepositoriesViewModel()
    @State private var library = LibraryViewModel()
    @State private var agents = AgentsViewModel()
    @State private var backups = BackupsViewModel()
    @State private var insights = InsightsViewModel()
    @State private var settings = SettingsViewModel()

    init() {
        let rawSelection = ProcessInfo.processInfo.environment["POPSKILL_INITIAL_SIDEBAR"]
        _selection = State(initialValue: rawSelection.flatMap(SidebarSelection.init(rawValue:)) ?? .installed)
    }

    var body: some View {
        let language = AppLanguage.fromStoredValue(preferredLanguage)

        content
            .environment(\.locale, language.locale)
            .environment(\.popskillLocalization, PopskillLocalization(language: language))
    }

    private var content: some View {
        NavigationSplitView {
            List {
                Section {
                    sidebarLink(.repositories, badge: repositories.repositories.isEmpty ? nil : repositories.enabledCount)
                } header: {
                    LocalizedText("section.discover")
                }

                Section {
                    sidebarLink(
                        .installed,
                        badge: library.skills.count,
                        updateBadge: library.updatableCount > 0 ? library.updatableCount : nil
                    )
                    sidebarLink(.agents, badge: agents.agents.isEmpty ? nil : agents.agents.count)
                    sidebarLink(.backups, badge: backups.backups.isEmpty ? nil : backups.backups.count)
                } header: {
                    LocalizedText("section.myLibrary")
                }

                Section {
                    sidebarLink(.usage)
                    sidebarLink(.idleCandidates)
                } header: {
                    LocalizedText("section.insights")
                }

                Section {
                    sidebarLink(.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            switch selection ?? .installed {
            case .repositories:
                RepositoriesView(viewModel: repositories) {
                    await settings.load()
                }
            case .installed:
                LibraryView(viewModel: library) {
                    await backups.load()
                    await settings.load()
                }
            case .agents:
                AgentsView(viewModel: agents)
            case .backups:
                BackupsView(viewModel: backups) {
                    await library.load()
                    await settings.load()
                } onBackupsChanged: {
                    await settings.load()
                }
            case .usage:
                InsightsView(viewModel: insights)
            case .idleCandidates:
                IdleCandidatesView(viewModel: library, insightsViewModel: insights)
            case .settings:
                SettingsView(viewModel: settings)
            }
        }
        .task {
            await repositories.load()
            await library.load()
            library.startAutomaticUpdateMonitoring()
            await agents.load()
        }
    }

    @ViewBuilder
    private func sidebarLink(_ item: SidebarSelection, badge: Int? = nil, updateBadge: Int? = nil) -> some View {
        SidebarLink(
            item: item,
            isSelected: selection == item,
            badge: badge,
            updateBadge: updateBadge,
            onSelect: { selection = item }
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

private struct SidebarLink: View {
    let item: SidebarSelection
    let isSelected: Bool
    let badge: Int?
    let updateBadge: Int?
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(iconForeground)
                    .frame(width: 18)

                LocalizedText(item.titleKey)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let badge {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.12)
                            )
                        )
                }

                if let updateBadge {
                    Text("↓\(updateBadge)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.popStatusWarning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.popStatusWarning.opacity(isSelected ? 0.18 : 0.12))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundFill)
            )
            .animation(.easeInOut(duration: 0.14), value: isHovering)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var iconForeground: Color {
        if isSelected {
            return Color.accentColor
        }
        return isHovering ? Color.popLabel : Color.secondary
    }

    private var backgroundFill: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return isHovering ? Color.accentColor.opacity(0.06) : Color.clear
    }
}
