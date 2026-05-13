import Observation
import SwiftUI

@MainActor
@Observable
final class DiscoverViewModel {
    var skills: [CatalogSkill] = []
    var query = ""
    var selectedInstallApp: TargetApp = .claude {
        didSet {
            if selectedInstallApp != oldValue {
                installPlans.removeAll()
            }
        }
    }
    var isLoading = false
    var hasLoadedOnce = false
    var errorMessage: String?

    private let client = SkillCLIClient()
    private var installPlans: [CatalogSkill.ID: InstallPlan] = [:]
    private var planningKeys: Set<String> = []
    private var installingKeys: Set<String> = []
    private var shouldSearchAgain = false

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
}

struct DiscoverView: View {
    @Bindable var viewModel: DiscoverViewModel
    let repositorySummary: String
    let onManageRepositories: () -> Void
    let onInstalled: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await viewModel.search() }
                }
                Divider()
            }

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
        .popPageBackground()
        .task {
            if !viewModel.hasLoadedOnce {
                await viewModel.search()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Featured")
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

                Picker("Install In", selection: $viewModel.selectedInstallApp) {
                    ForEach(TargetApp.allCases, id: \.id) { app in
                        Text(app.title).tag(app)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            HStack(spacing: 10) {
                TextField("Search by name, repo, or description", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await viewModel.search() }
                    }

                Button {
                    Task { await viewModel.search() }
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

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "sparkles")
        } description: {
            Text(description)
        } actions: {
            HStack(spacing: 10) {
                Button(actionTitle, action: onSearch)
                    .buttonStyle(.borderedProminent)

                Button {
                    onManageRepositories()
                } label: {
                    Label("Repositories", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var description: String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if !hasLoadedOnce {
            return "Search enabled skill repositories for installable skills."
        }

        if !trimmedQuery.isEmpty {
            return "No enabled repository returned a skill matching \"\(trimmedQuery)\"."
        }

        return "No installable skills were returned from the enabled repositories."
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

            if let url = skill.sourceURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
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
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
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
                } else {
                    Image(systemName: skill.installed ? "checkmark.circle.fill" : "arrow.down.circle")
                }
            }
            .buttonStyle(.bordered)
            .disabled(skill.installed || isInstalling)
            .help(skill.installed ? "Installed" : "Install")
        }
        .frame(minHeight: 68)
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
