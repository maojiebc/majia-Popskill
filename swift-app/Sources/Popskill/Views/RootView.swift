import SwiftUI

enum SidebarSelection: String, CaseIterable, Identifiable {
    case featured
    case repositories
    case installed
    case agents
    case updates
    case backups
    case recentlyUsed
    case usage
    case tokenSpend
    case idleCandidates
    case settings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .featured: "sidebar.featured"
        case .repositories: "sidebar.repositories"
        case .installed: "sidebar.installed"
        case .agents: "sidebar.agents"
        case .updates: "sidebar.updates"
        case .backups: "sidebar.backups"
        case .recentlyUsed: "sidebar.recentlyUsed"
        case .usage: "sidebar.usage"
        case .tokenSpend: "sidebar.tokenSpend"
        case .idleCandidates: "sidebar.idleCandidates"
        case .settings: "sidebar.settings"
        }
    }

    var symbolName: String {
        switch self {
        case .featured: "sparkles"
        case .repositories: "folder.badge.gearshape"
        case .installed: "shippingbox"
        case .agents: "person.crop.circle"
        case .updates: "arrow.down.circle"
        case .backups: "clock.arrow.circlepath"
        case .recentlyUsed: "clock"
        case .usage: "chart.xyaxis.line"
        case .tokenSpend: "creditcard"
        case .idleCandidates: "archivebox"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @State private var selection: SidebarSelection? = .featured
    @AppStorage("preferredLanguage") private var preferredLanguage = AppLanguage.system.rawValue
    @State private var discover = DiscoverViewModel()
    @State private var repositories = RepositoriesViewModel()
    @State private var library = LibraryViewModel()
    @State private var agents = AgentsViewModel()
    @State private var updates = UpdatesViewModel()
    @State private var backups = BackupsViewModel()
    @State private var insights = InsightsViewModel()
    @State private var settings = SettingsViewModel()

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
                    sidebarLink(.featured)
                    sidebarLink(.repositories, badge: repositories.repositories.isEmpty ? nil : repositories.enabledCount)
                } header: {
                    LocalizedText("section.discover")
                }

                Section {
                    sidebarLink(.installed, badge: library.skills.count)
                    sidebarLink(.agents, badge: agents.agents.isEmpty ? nil : agents.agents.count)
                    sidebarLink(.updates, badge: updates.updates.isEmpty ? nil : updates.updates.count)
                    sidebarLink(.backups, badge: backups.backups.isEmpty ? nil : backups.backups.count)
                    sidebarLink(.recentlyUsed)
                } header: {
                    LocalizedText("section.myLibrary")
                }

                Section {
                    sidebarLink(.usage)
                    sidebarLink(.tokenSpend)
                    sidebarLink(.idleCandidates)
                } header: {
                    LocalizedText("section.insights")
                }

                Section {
                    sidebarLink(.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            switch selection ?? .installed {
            case .featured:
                DiscoverView(
                    viewModel: discover,
                    repositorySummary: repositorySummary,
                    onManageRepositories: {
                        selection = .repositories
                    }
                ) {
                    await library.load()
                    await settings.load()
                }
            case .repositories:
                RepositoriesView(viewModel: repositories) {
                    if discover.hasLoadedOnce {
                        await discover.search()
                    }
                    await settings.load()
                }
            case .installed:
                LibraryView(viewModel: library) {
                    await backups.load()
                    await settings.load()
                }
            case .agents:
                AgentsView(viewModel: agents)
            case .updates:
                UpdatesView(viewModel: updates) {
                    await library.load()
                    await settings.load()
                }
            case .backups:
                BackupsView(viewModel: backups) {
                    await library.load()
                    await settings.load()
                } onBackupsChanged: {
                    await settings.load()
                }
            case .recentlyUsed:
                RecentActivityView(viewModel: insights)
            case .usage:
                InsightsView(viewModel: insights)
            case .tokenSpend:
                TokenSpendView(viewModel: insights)
            case .idleCandidates:
                IdleCandidatesView(viewModel: library, insightsViewModel: insights)
            case .settings:
                SettingsView(viewModel: settings)
            }
        }
        .task {
            await repositories.load()
            await library.load()
            await agents.load()
        }
    }

    private var repositorySummary: String {
        let totalCount = repositories.repositories.count
        let enabledCount = repositories.enabledCount

        guard totalCount > 0 else {
            return "Discover skills from enabled CC Switch repositories"
        }

        if enabledCount == totalCount {
            let noun = enabledCount == 1 ? "repository" : "repositories"
            return "Discover skills from \(enabledCount) enabled \(noun)"
        }

        return "Discover skills from \(enabledCount) enabled of \(totalCount) repositories"
    }

    @ViewBuilder
    private func sidebarLink(_ item: SidebarSelection, badge: Int? = nil) -> some View {
        let isSelected = selection == item

        Button {
            selection = item
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
