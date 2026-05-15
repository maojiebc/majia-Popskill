import Observation
import SwiftUI

@MainActor
@Observable
final class RepositoriesViewModel {
    var repositories: [SkillRepository] = []
    var searchText = ""
    var isLoading = false
    var hasLoadedOnce = false
    var errorMessage: String?

    private let client = SkillCLIClient()
    private var pendingIDs: Set<SkillRepository.ID> = []
    private var removingIDs: Set<SkillRepository.ID> = []
    private(set) var isAdding = false

    var enabledCount: Int {
        repositories.filter(\.enabled).count
    }

    /// Returns the current search query if non-empty, otherwise nil. Mirrors
    /// the helper on Library/Agents view models so view code stays uniform.
    var activeSearchQuery: String? {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }

    /// Repositories filtered by the toolbar search. Matches owner / name /
    /// branch / label (case-insensitive substring). Returns the existing sort
    /// order (already alphabetical by label after load) so users see stable
    /// rows when typing.
    var filteredRepositories: [SkillRepository] {
        guard let query = activeSearchQuery?.lowercased() else {
            return repositories
        }
        return repositories.filter { repository in
            repository.label.lowercased().contains(query)
                || repository.owner.lowercased().contains(query)
                || repository.name.lowercased().contains(query)
                || repository.branch.lowercased().contains(query)
        }
    }

    func load() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            repositories = try await client.listRepositories()
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isPending(_ repository: SkillRepository) -> Bool {
        pendingIDs.contains(repository.id)
    }

    func isRemoving(_ repository: SkillRepository) -> Bool {
        removingIDs.contains(repository.id)
    }

    @discardableResult
    func add(owner: String, name: String, branch: String, enabled: Bool) async -> Bool {
        guard !isAdding else {
            return false
        }

        guard let repositoryParts = Self.normalizedRepositoryParts(ownerInput: owner, nameInput: name) else {
            errorMessage = "Repository owner and name are required"
            return false
        }

        let branch = branch.trimmingCharacters(in: .whitespacesAndNewlines)

        isAdding = true
        errorMessage = nil

        do {
            let repository = try await client.addRepository(
                owner: repositoryParts.owner,
                name: repositoryParts.name,
                branch: branch.isEmpty ? "main" : branch,
                enabled: enabled
            )
            repositories.removeAll { $0.id == repository.id }
            repositories.append(repository)
            repositories.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            isAdding = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isAdding = false
            return false
        }
    }

    nonisolated static func normalizedRepositoryParts(
        ownerInput: String,
        nameInput: String
    ) -> (owner: String, name: String)? {
        let ownerInput = ownerInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameInput = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if !nameInput.isEmpty {
            let name = Self.strippingGitSuffix(from: nameInput)
            guard Self.isValidRepositorySegment(ownerInput), Self.isValidRepositorySegment(name) else {
                return nil
            }
            return (ownerInput, name)
        }

        let normalized = ownerInput
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "http://github.com/", with: "")
            .replacingOccurrences(of: "git@github.com:", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return nil
        }

        let owner = String(parts[0])
        let name = Self.strippingGitSuffix(from: String(parts[1]))
        guard Self.isValidRepositorySegment(owner), Self.isValidRepositorySegment(name) else {
            return nil
        }

        return (owner, name)
    }

    nonisolated private static func strippingGitSuffix(from value: String) -> String {
        guard value.hasSuffix(".git") else {
            return value
        }
        return String(value.dropLast(4))
    }

    nonisolated private static func isValidRepositorySegment(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains("/")
            && !value.contains(where: \.isWhitespace)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, for repository: SkillRepository) async -> Bool {
        guard let index = repositories.firstIndex(where: { $0.id == repository.id }) else {
            return false
        }
        guard !pendingIDs.contains(repository.id) else {
            return false
        }

        let previous = repositories[index]
        repositories[index].enabled = enabled
        pendingIDs.insert(repository.id)
        errorMessage = nil
        var didSave = false

        do {
            _ = try await client.setRepositoryEnabled(enabled, owner: repository.owner, name: repository.name)
            didSave = true
        } catch {
            repositories[index] = previous
            errorMessage = error.localizedDescription
        }

        pendingIDs.remove(repository.id)
        return didSave
    }

    @discardableResult
    func remove(_ repository: SkillRepository) async -> Bool {
        guard !removingIDs.contains(repository.id) else {
            return false
        }

        removingIDs.insert(repository.id)
        errorMessage = nil
        var didRemove = false

        do {
            _ = try await client.removeRepository(owner: repository.owner, name: repository.name)
            repositories.removeAll { $0.id == repository.id }
            didRemove = true
        } catch {
            errorMessage = error.localizedDescription
        }

        removingIDs.remove(repository.id)
        return didRemove
    }
}

struct RepositoriesView: View {
    @Bindable var viewModel: RepositoriesViewModel
    let onRepositoriesChanged: () async -> Void
    @State private var isShowingAddSheet = false
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await viewModel.load() }
                }
                Divider()
            }

            List(viewModel.filteredRepositories) { repository in
                RepositoryRow(
                    repository: repository,
                    isPending: viewModel.isPending(repository),
                    isRemoving: viewModel.isRemoving(repository),
                    searchQuery: viewModel.activeSearchQuery
                ) { enabled in
                    Task {
                        if await viewModel.setEnabled(enabled, for: repository) {
                            await onRepositoriesChanged()
                        }
                    }
                } onRemove: {
                    Task {
                        if await viewModel.remove(repository) {
                            await onRepositoriesChanged()
                        }
                    }
                }
                .listRowSeparator(.visible)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            }
            .listStyle(.plain)
            .searchable(
                text: $viewModel.searchText,
                placement: .toolbar,
                prompt: Text(localization.string("Search Repositories"))
            )
            .overlay {
                if viewModel.isLoading && viewModel.repositories.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                } else if viewModel.filteredRepositories.isEmpty {
                    if viewModel.activeSearchQuery != nil {
                        ContentUnavailableView {
                            Label(localization.string("No Matching Repositories"), systemImage: "folder.badge.gearshape")
                        } description: {
                            Text(localization.string("repositories.search.emptyHint"))
                        }
                    } else {
                        ContentUnavailableView(localization.string("No Repositories"), systemImage: "folder.badge.gearshape")
                    }
                }
            }
        }
        .popPageBackground()
        .sheet(isPresented: $isShowingAddSheet) {
            AddRepositorySheet(
                isAdding: viewModel.isAdding,
                errorMessage: viewModel.errorMessage,
                onCancel: {
                    isShowingAddSheet = false
                },
                onAdd: { owner, name, branch, enabled in
                    Task {
                        if await viewModel.add(owner: owner, name: name, branch: branch, enabled: enabled) {
                            isShowingAddSheet = false
                            await onRepositoriesChanged()
                        }
                    }
                }
            )
        }
        .task {
            if !viewModel.hasLoadedOnce {
                await viewModel.load()
            }
        }
    }

    private var header: some View {
        PopskillPageHeader(
            titleKey: "sidebar.repositories",
            subtitle: localization.string(
                "repositories.summary",
                viewModel.enabledCount,
                viewModel.repositories.count
            )
        ) {
            HStack(spacing: 12) {
                Button {
                    viewModel.errorMessage = nil
                    isShowingAddSheet = true
                } label: {
                    Label(localization.string("Add Repository"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .help("Add Repository")

                Button {
                    Task { await viewModel.load() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .help("Refresh")
                .disabled(viewModel.isLoading)
            }
        }
    }
}

struct AddRepositorySheet: View {
    let isAdding: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onAdd: (String, String, String, Bool) -> Void

    @State private var owner = ""
    @State private var name = ""
    @State private var branch = "main"
    @State private var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Repository")
                .font(.title2.weight(.bold))

            if let errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.popStatusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Owner, owner/repo, or GitHub URL", text: $owner)
                TextField("Repository name", text: $name)
                TextField("Branch", text: $branch)
                Toggle("Enabled", isOn: $enabled)
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onAdd(owner, name, branch, enabled)
                } label: {
                    if isAdding {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isAdding || RepositoriesViewModel.normalizedRepositoryParts(ownerInput: owner, nameInput: name) == nil)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct RepositoryRow: View {
    let repository: SkillRepository
    let isPending: Bool
    let isRemoving: Bool
    var searchQuery: String? = nil
    let onToggle: (Bool) -> Void
    let onRemove: () -> Void

    @State private var isConfirmingRemove = false

    var body: some View {
        HStack(spacing: 14) {
            PackageAvatar(name: repository.name, identifier: repository.id)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(highlightedSearchString(repository.label, query: searchQuery))
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    StatusPill(
                        title: repository.enabled ? "Enabled" : "Disabled",
                        color: repository.enabled ? .popStatusOK : .popStatusNeutral
                    )
                }

                Text(highlightedSearchString("Branch \(repository.branch)", query: searchQuery))
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)

            Toggle("Enabled", isOn: Binding(
                get: { repository.enabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(isPending || isRemoving)
            .help(repository.enabled ? "Disable repository" : "Enable repository")

            Link(destination: repositoryURL) {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .help("Open Repository")

            Button(role: .destructive) {
                isConfirmingRemove = true
            } label: {
                if isRemoving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isPending || isRemoving)
            .help("Remove Repository")
            .confirmationDialog(
                "Remove \(repository.label)?",
                isPresented: $isConfirmingRemove,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    onRemove()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Popskill will remove this repository from CC Switch discovery sources. Installed skills are not uninstalled.")
            }
        }
        .frame(minHeight: 68)
    }

    private var repositoryURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repository.owner)/\(repository.name)"
        return components.url ?? URL(fileURLWithPath: "/")
    }
}
