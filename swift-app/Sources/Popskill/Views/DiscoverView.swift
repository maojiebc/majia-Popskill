import Observation
import SwiftUI

@MainActor
@Observable
final class DiscoverViewModel {
    var skills: [CatalogSkill] = []
    var query = ""
    var selectedInstallApp: TargetApp = .claude
    var isLoading = false
    var hasLoadedOnce = false
    var errorMessage: String?

    private let client = SkillCLIClient()
    private var installingKeys: Set<String> = []

    func search() async {
        isLoading = true
        errorMessage = nil

        do {
            skills = try await client.discover(query: query, limit: 80)
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
                    isInstalling: viewModel.isInstalling(skill.key)
                ) {
                    Task {
                        await viewModel.install(skill, onInstalled: onInstalled)
                    }
                }
                .listRowSeparator(.visible)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isLoading && viewModel.skills.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                } else if viewModel.skills.isEmpty {
                    ContentUnavailableView("Search Skills", systemImage: "sparkles")
                }
            }
        }
        .background(Color.popMainBackground)
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
}

struct CatalogSkillRow: View {
    let skill: CatalogSkill
    let isInstalling: Bool
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
            }

            Spacer(minLength: 20)

            if let readmeUrl = skill.readmeUrl, let url = URL(string: readmeUrl) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .help("Open Source")
            }

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
