import Observation
import SwiftUI

@MainActor
@Observable
final class UpdatesViewModel {
    var updates: [SkillUpdateInfo] = []
    var isChecking = false
    var errorMessage: String?

    private let client = SkillCLIClient()
    private var updatingIDs: Set<String> = []

    func check() async {
        isChecking = true
        errorMessage = nil

        do {
            updates = try await client.checkUpdates()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }

        isChecking = false
    }

    func isUpdating(_ id: String) -> Bool {
        updatingIDs.contains(id)
    }

    func update(_ update: SkillUpdateInfo) async {
        guard !updatingIDs.contains(update.id) else {
            return
        }

        updatingIDs.insert(update.id)
        errorMessage = nil

        do {
            _ = try await client.update(skillID: update.id)
            updates.removeAll { $0.id == update.id }
        } catch {
            errorMessage = error.localizedDescription
        }

        updatingIDs.remove(update.id)
    }
}

struct UpdatesView: View {
    @Bindable var viewModel: UpdatesViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Updates")
                        .font(.system(.largeTitle, weight: .bold))
                    Text("\(viewModel.updates.count) available")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await viewModel.check() }
                } label: {
                    if viewModel.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .help("Check Updates")
                .disabled(viewModel.isChecking)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await viewModel.check() }
                }
                Divider()
            }

            List(viewModel.updates) { update in
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(update.name)
                            .font(.headline)
                        Text(update.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            HashBadge(title: "Local", hash: update.currentHash)
                            HashBadge(title: "Remote", hash: update.remoteHash)
                        }
                    }

                    Spacer()

                    Button {
                        Task { await viewModel.update(update) }
                    } label: {
                        if viewModel.isUpdating(update.id) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Update")
                    .disabled(viewModel.isUpdating(update.id))
                }
                .padding(.vertical, 8)
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isChecking && viewModel.updates.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                } else if viewModel.updates.isEmpty {
                    ContentUnavailableView("No Updates", systemImage: "checkmark.seal")
                }
            }
        }
        .background(Color.popMainBackground)
    }
}

struct HashBadge: View {
    let title: String
    let hash: String?

    var body: some View {
        Text("\(title) \(shortHash)")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.popHeaderBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    private var shortHash: String {
        guard let hash, !hash.isEmpty else {
            return "missing"
        }
        return String(hash.prefix(10))
    }
}
