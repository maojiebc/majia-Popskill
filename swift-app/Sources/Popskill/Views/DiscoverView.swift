import Observation
import SwiftUI

@MainActor
@Observable
final class DiscoverViewModel {
    var skills: [CatalogSkill] = []
    var packages: [CapabilityPackage] = []
    var query = ""
    var selectedContent: DiscoverContentFilter = .packages
    var selectedInstallApp: TargetApp = .claude {
        didSet {
            if selectedInstallApp != oldValue {
                installPlans.removeAll()
            }
        }
    }
    var isLoading = false
    var hasLoadedOnce = false
    var hasLoadedPackagesOnce = false
    var errorMessage: String?

    private let client = SkillCLIClient()
    private var installPlans: [CatalogSkill.ID: InstallPlan] = [:]
    private var planningKeys: Set<String> = []
    private var installingKeys: Set<String> = []
    private var shouldSearchAgain = false

    var filteredPackages: [CapabilityPackage] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return packages.filter { package in
            normalizedQuery.isEmpty
                || package.name.lowercased().contains(normalizedQuery)
                || package.summary.lowercased().contains(normalizedQuery)
                || package.sourceLabel.lowercased().contains(normalizedQuery)
                || package.components.all.contains { component in
                    component.id.lowercased().contains(normalizedQuery)
                        || component.name.lowercased().contains(normalizedQuery)
                        || component.kind.lowercased().contains(normalizedQuery)
                }
        }
    }

    func refreshSelectedContent() async {
        switch selectedContent {
        case .packages:
            await loadPackages()
        case .standaloneSkills:
            await search()
        }
    }

    func loadPackages() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedPackagesOnce = true
        }

        do {
            packages = try await client.listPackages()
                .sorted(by: packageSort)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search() async {
        if isLoading {
            shouldSearchAgain = true
            return
        }

        repeat {
            shouldSearchAgain = false
            isLoading = true
            errorMessage = nil

            do {
                skills = try await client.discover(query: query, limit: 80)
                hasLoadedOnce = true
            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
        } while shouldSearchAgain
    }

    func planInstall(_ skill: CatalogSkill) async {
        guard !planningKeys.contains(skill.key), !skill.installed else {
            return
        }

        planningKeys.insert(skill.key)
        errorMessage = nil

        do {
            installPlans[skill.key] = try await client.installPlan(skillKey: skill.key, app: selectedInstallApp)
        } catch {
            errorMessage = error.localizedDescription
        }

        planningKeys.remove(skill.key)
    }

    func install(_ skill: CatalogSkill, onInstalled: @escaping () async -> Void) async {
        guard !installingKeys.contains(skill.key), !skill.installed else {
            return
        }

        installingKeys.insert(skill.key)
        errorMessage = nil

        do {
            _ = try await client.install(skillKey: skill.key, app: selectedInstallApp)
            if let index = skills.firstIndex(where: { $0.key == skill.key }) {
                let current = skills[index]
                skills[index] = CatalogSkill(
                    key: current.key,
                    name: current.name,
                    description: current.description,
                    directory: current.directory,
                    readmeUrl: current.readmeUrl,
                    installed: true,
                    repoOwner: current.repoOwner,
                    repoName: current.repoName,
                    repoBranch: current.repoBranch
                )
            }
            await onInstalled()
        } catch {
            errorMessage = error.localizedDescription
        }

        installingKeys.remove(skill.key)
    }

    func isInstalling(_ key: String) -> Bool {
        installingKeys.contains(key)
    }

    func isPlanning(_ key: String) -> Bool {
        planningKeys.contains(key)
    }

    func installPlan(for key: String) -> InstallPlan? {
        guard let plan = installPlans[key],
              plan.targetApp.lowercased() == selectedInstallApp.rawValue
        else {
            return nil
        }
        return plan
    }

    private func packageSort(_ left: CapabilityPackage, _ right: CapabilityPackage) -> Bool {
        let leftRank = packageSortRank(left)
        let rightRank = packageSortRank(right)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        let nameOrder = left.name.localizedCaseInsensitiveCompare(right.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return left.id < right.id
    }

    private func packageSortRank(_ package: CapabilityPackage) -> Int {
        switch package.type {
        case .composite:
            return 0
        case .standalone:
            return package.source.kind == "builtin" ? 1 : 2
        }
    }
}

enum DiscoverContentFilter: String, CaseIterable, Identifiable {
    case packages
    case standaloneSkills

    var id: String { rawValue }

    var title: String {
        switch self {
        case .packages: "Capability Packages"
        case .standaloneSkills: "Standalone Skills"
        }
    }
}

struct DiscoverView: View {
    @Bindable var viewModel: DiscoverViewModel
    let repositorySummary: String
    let onManageRepositories: () -> Void
    let onInstalled: () async -> Void
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await viewModel.refreshSelectedContent() }
                }
                Divider()
            }

            if viewModel.selectedContent == .packages {
                List(viewModel.filteredPackages) { package in
                    PackageRow(package: package)
                        .listRowSeparator(.visible)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .listStyle(.plain)
                .overlay {
                    if viewModel.isLoading && viewModel.packages.isEmpty {
                        ProgressView()
                            .controlSize(.large)
                    } else if viewModel.filteredPackages.isEmpty {
                        DiscoverEmptyState(
                            title: emptyStateTitle,
                            hasLoadedOnce: viewModel.hasLoadedPackagesOnce,
                            query: viewModel.query,
                            onSearch: {
                                Task { await viewModel.loadPackages() }
                            },
                            onManageRepositories: onManageRepositories
                        )
                    }
                }
            } else {
                List(viewModel.skills) { skill in
                    CatalogSkillRow(
                        skill: skill,
                        installPlan: viewModel.installPlan(for: skill.key),
                        isPlanning: viewModel.isPlanning(skill.key),
                        isInstalling: viewModel.isInstalling(skill.key),
                        onPlan: {
                            Task {
                                await viewModel.planInstall(skill)
                            }
                        },
                        onInstall: {
                            Task {
                                await viewModel.install(skill, onInstalled: onInstalled)
                            }
                        }
                    )
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .listStyle(.plain)
                .overlay {
                    if viewModel.isLoading && viewModel.skills.isEmpty {
                        ProgressView()
                            .controlSize(.large)
                    } else if viewModel.skills.isEmpty {
                        DiscoverEmptyState(
                            title: emptyStateTitle,
                            hasLoadedOnce: viewModel.hasLoadedOnce,
                            query: viewModel.query,
                            onSearch: {
                                Task { await viewModel.search() }
                            },
                            onManageRepositories: onManageRepositories
                        )
                    }
                }
            }
        }
        .popPageBackground()
        .task {
            if !viewModel.hasLoadedPackagesOnce {
                await viewModel.loadPackages()
            }
            if !viewModel.hasLoadedOnce {
                await viewModel.search()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("Featured")
                        .font(.system(.largeTitle, weight: .bold))
                    Text(repositorySummary)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onManageRepositories()
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)
                .help("Manage Repositories")

                if viewModel.selectedContent == .standaloneSkills {
                    Picker("Install In", selection: $viewModel.selectedInstallApp) {
                        ForEach(TargetApp.allCases, id: \.id) { app in
                            Text(app.title).tag(app)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }

            Picker("Catalog", selection: $viewModel.selectedContent) {
                ForEach(DiscoverContentFilter.allCases) { filter in
                    Text(localization.string(filter.title)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 340)

            HStack(spacing: 10) {
                TextField(localization.string("Search by name, repo, or description"), text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await viewModel.refreshSelectedContent() }
                    }

                Button {
                    Task { await viewModel.refreshSelectedContent() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
                .help("Search")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var emptyStateTitle: String {
        if viewModel.selectedContent == .packages {
            if !viewModel.hasLoadedPackagesOnce {
                return "Load Packages"
            }

            if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "No Packages"
            }

            return "No Matching Packages"
        }

        if !viewModel.hasLoadedOnce {
            return "Search Skills"
        }

        if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Skills Found"
        }

        return "No Matching Skills"
    }
}

struct DiscoverEmptyState: View {
    let title: String
    let hasLoadedOnce: Bool
    let query: String
    let onSearch: () -> Void
    let onManageRepositories: () -> Void
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(localization.string(title))
            } icon: {
                Image(systemName: "sparkles")
            }
        } description: {
            Text(description)
        } actions: {
            HStack(spacing: 10) {
                Button(action: onSearch) {
                    Text(localization.string(actionTitle))
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onManageRepositories()
                } label: {
                    LocalizedLabel(title: "Repositories", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var description: String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if !hasLoadedOnce {
            return localization.string("discover.empty.notLoaded")
        }

        if !trimmedQuery.isEmpty {
            return localization.string("discover.empty.noMatch", trimmedQuery)
        }

        return localization.string("discover.empty.noSkills")
    }

    private var actionTitle: String {
        hasLoadedOnce ? "Search Again" : "Search"
    }
}

struct CatalogSkillRow: View {
    let skill: CatalogSkill
    let installPlan: InstallPlan?
    let isPlanning: Bool
    let isInstalling: Bool
    let onPlan: () -> Void
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            InitialAvatarView(name: skill.name, identifier: skill.key)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(skill.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)

                    if skill.installed {
                        StatusPill(title: "Installed", color: .popStatusOK)
                    }
                }

                Text(skill.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(skill.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
                    .lineLimit(1)

                if let installPlan {
                    InstallPlanPreview(plan: installPlan)
                }
            }

            Spacer(minLength: 20)

            HStack(spacing: 8) {
                if let url = skill.sourceURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .frame(width: 16)
                    }
                    .buttonStyle(.bordered)
                    .help("Open Source")
                }

                Button {
                    onPlan()
                } label: {
                    if isPlanning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 58)
                    } else {
                        CatalogActionLabel(title: "Plan", systemImage: "doc.text.magnifyingglass", minWidth: 58)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(skill.installed || isPlanning || isInstalling)
                .help("Preview Install")

                Button {
                    onInstall()
                } label: {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 74)
                    } else {
                        CatalogActionLabel(
                            title: skill.installed ? "Installed" : "Install",
                            systemImage: skill.installed ? "checkmark.circle.fill" : "arrow.down.circle",
                            minWidth: skill.installed ? 82 : 74
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(skill.installed || isInstalling)
                .help(skill.installed ? "Installed" : "Install")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 68)
    }
}

private struct CatalogActionLabel: View {
    let title: String
    let systemImage: String
    let minWidth: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            LocalizedText(title)
        }
        .font(.caption.weight(.semibold))
        .frame(minWidth: minWidth)
    }
}

struct InstallPlanPreview: View {
    let plan: InstallPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusPill(title: targetAppTitle, color: .popSectionBlue)
                StatusPill(title: securityGateLabel, color: securityGateColor)
                    .help(plan.securityGate)
            }

            Text("Writes to \(plan.writes.ssotPath)")
                .font(.caption)
                .foregroundStyle(Color.popTertiaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)

            if let appSkillPath = plan.writes.appSkillPath, !appSkillPath.isEmpty {
                Text("Links \(targetAppTitle) to \(appSkillPath)")
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if !plan.steps.isEmpty {
                Label(stepSummary, systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.popHeaderBackground.opacity(0.45), in: RoundedRectangle(cornerRadius: PopskillRadius.smallCard))
    }

    private var targetAppTitle: String {
        TargetApp(rawValue: plan.targetApp.lowercased())?.title ?? plan.targetApp.capitalized
    }

    private var securityGateLabel: String {
        if plan.securityGate.lowercased().contains("rollback") {
            return "AgentShield rollback"
        }
        if plan.securityGate.lowercased().contains("block") {
            return "AgentShield blocks"
        }
        return "AgentShield"
    }

    private var securityGateColor: Color {
        plan.securityGate.lowercased().contains("rollback") ? .popStatusWarning : .popStatusNeutral
    }

    private var stepSummary: String {
        plan.steps.map(humanReadableStep).joined(separator: " -> ")
    }

    private func humanReadableStep(_ step: String) -> String {
        switch step {
        case "downloadFromRepository":
            return "download"
        case "runAgentShield":
            return "scan"
        default:
            return step
        }
    }
}
