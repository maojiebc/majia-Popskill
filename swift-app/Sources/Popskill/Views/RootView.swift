import SwiftUI

enum SidebarSelection: String, CaseIterable, Identifiable {
    case featured
    case repositories
    case installed
    case updates
    case backups
    case recentlyUsed
    case usage
    case tokenSpend
    case idleCandidates
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: "Featured"
        case .repositories: "Repositories"
        case .installed: "Installed"
        case .updates: "Updates"
        case .backups: "Backups"
        case .recentlyUsed: "Recently Used"
        case .usage: "Usage"
        case .tokenSpend: "Token Spend"
        case .idleCandidates: "Idle Candidates"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .featured: "sparkles"
        case .repositories: "folder.badge.gearshape"
        case .installed: "shippingbox"
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
    @State private var discover = DiscoverViewModel()
    @State private var repositories = RepositoriesViewModel()
    @State private var library = LibraryViewModel()
    @State private var updates = UpdatesViewModel()
    @State private var backups = BackupsViewModel()
    @State private var insights = InsightsViewModel()
    @State private var settings = SettingsViewModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Discover") {
                    sidebarLink(.featured)
                    sidebarLink(.repositories, badge: repositories.repositories.isEmpty ? nil : repositories.enabledCount)
                }

                Section("My Library") {
                    sidebarLink(.installed, badge: library.skills.count)
                    sidebarLink(.updates, badge: updates.updates.isEmpty ? nil : updates.updates.count)
                    sidebarLink(.backups, badge: backups.backups.isEmpty ? nil : backups.backups.count)
                    sidebarLink(.recentlyUsed)
                }

                Section("Insights") {
                    sidebarLink(.usage)
                    sidebarLink(.tokenSpend)
                    sidebarLink(.idleCandidates)
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
        if let badge {
            Label(item.title, systemImage: item.symbolName)
                .badge(badge)
                .tag(item)
        } else {
            Label(item.title, systemImage: item.symbolName)
                .tag(item)
        }
    }
}
