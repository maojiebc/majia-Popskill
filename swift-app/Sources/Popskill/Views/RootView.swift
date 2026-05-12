import SwiftUI

enum SidebarSelection: String, CaseIterable, Identifiable {
    case featured
    case categories
    case topCharts
    case installed
    case updates
    case backups
    case recentlyUsed
    case stubs
    case usage
    case tokenSpend
    case idleCandidates
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: "Featured"
        case .categories: "Categories"
        case .topCharts: "Top Charts"
        case .installed: "Installed"
        case .updates: "Updates"
        case .backups: "Backups"
        case .recentlyUsed: "Recently Used"
        case .stubs: "Stubs"
        case .usage: "Usage"
        case .tokenSpend: "Token Spend"
        case .idleCandidates: "Idle Candidates"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .featured: "sparkles"
        case .categories: "folder"
        case .topCharts: "chart.bar"
        case .installed: "shippingbox"
        case .updates: "arrow.down.circle"
        case .backups: "clock.arrow.circlepath"
        case .recentlyUsed: "clock"
        case .stubs: "icloud"
        case .usage: "chart.xyaxis.line"
        case .tokenSpend: "creditcard"
        case .idleCandidates: "archivebox"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @State private var selection: SidebarSelection? = .installed
    @State private var discover = DiscoverViewModel()
    @State private var library = LibraryViewModel()
    @State private var updates = UpdatesViewModel()
    @State private var backups = BackupsViewModel()
    @State private var insights = InsightsViewModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Discover") {
                    sidebarLink(.featured)
                    sidebarLink(.categories)
                    sidebarLink(.topCharts)
                }

                Section("My Library") {
                    sidebarLink(.installed, badge: library.skills.count)
                    sidebarLink(.updates, badge: updates.updates.isEmpty ? nil : updates.updates.count)
                    sidebarLink(.backups, badge: backups.backups.isEmpty ? nil : backups.backups.count)
                    sidebarLink(.recentlyUsed)
                    sidebarLink(.stubs)
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
                DiscoverView(viewModel: discover) {
                    await library.load()
                }
            case .installed:
                LibraryView(viewModel: library)
            case .updates:
                UpdatesView(viewModel: updates)
            case .backups:
                BackupsView(viewModel: backups) {
                    await library.load()
                }
            case .recentlyUsed:
                RecentActivityView(viewModel: insights)
            case .usage:
                InsightsView(viewModel: insights)
            case .tokenSpend:
                TokenSpendView(viewModel: insights)
            default:
                PlaceholderView(selection: selection ?? .installed)
            }
        }
        .task {
            await library.load()
        }
    }

    @ViewBuilder
    private func sidebarLink(_ item: SidebarSelection, badge: Int? = nil) -> some View {
        let label = Label(item.title, systemImage: item.symbolName)
            .tag(item)

        if let badge {
            label.badge(badge)
        } else {
            label
        }
    }
}
