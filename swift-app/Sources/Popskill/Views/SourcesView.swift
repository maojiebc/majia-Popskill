import SwiftUI

/// Sources — lists the catalog repositories that feed the matrix. v0.3 ships
/// enable/disable + remove + a small `addOpen` popover for adding a new
/// `owner/name@branch`. Full multi-type wizard (npm / brew / folder / zip) is
/// scheduled for v0.4 and surfaces as the disabled buttons here.
struct SourcesView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var addOpen: Bool = false
    @State private var loading: Bool = false
    @State private var pendingMutation: Set<String> = []
    @State private var pendingRemoval: SkillRepository?

    var body: some View {
        VStack(spacing: 0) {
            PopskillPageHeader(
                titleKey: "sidebar.sources",
                subtitle: subtitle
            ) {
                HStack(spacing: 8) {
                    Button {
                        Task { await refresh(force: true) }
                    } label: {
                        Label(localization.string("sources.refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(loading)

                    if loading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        addOpen = true
                    } label: {
                        Label(localization.string("sources.add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .popover(isPresented: $addOpen) {
                        AddSourcePopover(store: store, isPresented: $addOpen)
                    }
                }
            }

            if loading && store.sources.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.sources.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .popPageBackground()
        .task {
            // Cached helper short-circuits when last refresh < 30s ago. The
            // manual refresh button above passes force: true to bypass.
            await refresh(force: false)
        }
        .confirmationDialog(
            localization.string("sources.row.remove.confirm.title"),
            isPresented: removalDialogPresented,
            titleVisibility: .visible
        ) {
            if let pendingRemoval {
                Button(localization.string("sources.row.remove.confirm.button"), role: .destructive) {
                    Task { await remove(pendingRemoval) }
                }
            }
            Button(localization.string("sources.add.cancel"), role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            if let pendingRemoval {
                Text(localization.string("sources.row.remove.confirm.message", pendingRemoval.label))
            }
        }
    }

    private var subtitle: String {
        let total = store.sources.count
        let enabled = store.sources.filter(\.enabled).count
        return localization.string("sources.subtitle", enabled, total)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.sources) { repo in
                    sourceRow(repo)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private var removalDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRemoval = nil
                }
            }
        )
    }

    private func sourceRow(_ repo: SkillRepository) -> some View {
        HStack(spacing: 12) {
            Image(systemName: repo.enabled ? "shippingbox.fill" : "shippingbox")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(repo.enabled ? Color.accentColor : Color.popTertiaryLabel)
                .frame(width: 32, height: 32)
                .background(
                    (repo.enabled ? Color.accentColor : Color.popTertiaryLabel).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(repo.label)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.popLabel)
                Text(localization.string("sources.row.branch", repo.branch))
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
            }

            Spacer(minLength: 8)

            if pendingMutation.contains(repo.id) {
                ProgressView().controlSize(.small)
            } else {
                Toggle("", isOn: Binding(
                    get: { repo.enabled },
                    set: { newValue in
                        Task { await setEnabled(repo, enabled: newValue) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Menu {
                if let url = githubURL(for: repo) {
                    Link(destination: url) {
                        Label(localization.string("sources.row.openGithub"), systemImage: "arrow.up.right.square")
                    }
                }
                Button(role: .destructive) {
                    pendingRemoval = repo
                } label: {
                    Label(localization.string("sources.row.remove"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 26)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .popCard(cornerRadius: PopskillRadius.smallCard, shadowOpacity: 0.02)
    }

    private func githubURL(for repo: SkillRepository) -> URL? {
        URL(string: "https://github.com/\(repo.owner)/\(repo.name)")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            LocalizedText("sources.empty.title")
                .font(.title3.weight(.semibold))
            LocalizedText("sources.empty.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { addOpen = true } label: {
                Label(localization.string("sources.add"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    @MainActor
    private func refresh(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        // Delegate to the cached helper on PopskillStore. `force: true` from
        // the manual refresh button; `force: false` from .task on appearance.
        await store.refreshSources(force: force)
    }

    @MainActor
    private func setEnabled(_ repo: SkillRepository, enabled: Bool) async {
        let key = repo.id
        guard !pendingMutation.contains(key) else { return }
        pendingMutation.insert(key)
        defer { pendingMutation.remove(key) }

        do {
            let result = try await store.client.setRepositoryEnabled(
                enabled,
                owner: repo.owner,
                name: repo.name
            )
            if let idx = store.sources.firstIndex(where: { $0.owner == result.owner && $0.name == result.name }) {
                store.sources[idx].enabled = result.enabled
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func remove(_ repo: SkillRepository) async {
        let key = repo.id
        guard !pendingMutation.contains(key) else { return }
        pendingRemoval = nil
        pendingMutation.insert(key)
        defer { pendingMutation.remove(key) }

        do {
            let result = try await store.client.removeRepository(owner: repo.owner, name: repo.name)
            store.sources.removeAll {
                $0.owner == result.owner && $0.name == result.name
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

/// Inline `owner/name@branch` parser. Keeps the AddSource popover dumb — the
/// view just needs to surface enable/disable on a Submit button.
struct AddSourceInput: Equatable {
    let owner: String
    let name: String
    let branch: String

    static func parse(_ raw: String) -> AddSourceInput? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Optional URL prefix tolerated: github.com/owner/name(@branch)
        let stripped = trimmed
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")

        let (path, branch): (String, String) = {
            if let atIndex = stripped.firstIndex(of: "@") {
                let p = String(stripped[..<atIndex])
                let b = String(stripped[stripped.index(after: atIndex)...])
                return (p, b.isEmpty ? "main" : b)
            }
            return (stripped, "main")
        }()

        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }

        return AddSourceInput(
            owner: String(parts[0]),
            name: String(parts[1]),
            branch: branch
        )
    }
}

private struct AddSourcePopover: View {
    @Bindable var store: PopskillStore
    @Binding var isPresented: Bool
    @Environment(\.popskillLocalization) private var localization

    @State private var raw: String = ""
    @State private var isAdding: Bool = false
    @State private var localError: String?

    private var parsed: AddSourceInput? { AddSourceInput.parse(raw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText("sources.add.title")
                .font(.headline)
            LocalizedText("sources.add.help")
                .font(.caption)
                .foregroundStyle(Color.popSecondaryLabel)
            TextField("anthropics/skills", text: $raw)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await submit() } }
                .disabled(isAdding)
            if let parsed {
                Label(
                    "\(parsed.owner)/\(parsed.name) · \(parsed.branch)",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(Color.popStatusOK)
            }
            if let localError {
                Label(localError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.popStatusWarning)
            }
            HStack {
                Spacer()
                Button(localization.string("sources.add.cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                .disabled(isAdding)
                Button {
                    Task { await submit() }
                } label: {
                    if isAdding {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text(localization.string("sources.add.submit"))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsed == nil || isAdding)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    @MainActor
    private func submit() async {
        guard let parsed, !isAdding else { return }
        isAdding = true
        localError = nil
        defer { isAdding = false }

        do {
            let repo = try await store.client.addRepository(
                owner: parsed.owner,
                name: parsed.name,
                branch: parsed.branch,
                enabled: true
            )
            if let idx = store.sources.firstIndex(where: { $0.id == repo.id }) {
                store.sources[idx] = repo
            } else {
                store.sources.append(repo)
            }
            raw = ""
            isPresented = false
        } catch {
            localError = error.localizedDescription
        }
    }
}
