import Observation
import SwiftUI

@MainActor
@Observable
final class BackupsViewModel {
    var backups: [SkillBackup] = []
    var selectedRestoreApp: TargetApp = .codex
    var isLoading = false
    var hasLoadedOnce = false
    var errorMessage: String?

    private let client = SkillCLIClient()
    private var restoringIDs: Set<String> = []
    private var deletingIDs: Set<String> = []

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
            backups = try await client.listBackups()
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isRestoring(_ backupID: String) -> Bool {
        restoringIDs.contains(backupID)
    }

    func isDeleting(_ backupID: String) -> Bool {
        deletingIDs.contains(backupID)
    }

    func restore(_ backup: SkillBackup, onRestored: @escaping () async -> Void) async {
        guard !restoringIDs.contains(backup.backupId) else {
            return
        }

        restoringIDs.insert(backup.backupId)
        errorMessage = nil

        do {
            _ = try await client.restoreBackup(backupID: backup.backupId, app: selectedRestoreApp)
            await onRestored()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }

        restoringIDs.remove(backup.backupId)
    }

    @discardableResult
    func delete(_ backup: SkillBackup) async -> Bool {
        guard !deletingIDs.contains(backup.backupId) else {
            return false
        }

        deletingIDs.insert(backup.backupId)
        errorMessage = nil
        var didDelete = false

        do {
            _ = try await client.deleteBackup(backupID: backup.backupId)
            backups.removeAll { $0.backupId == backup.backupId }
            didDelete = true
        } catch {
            errorMessage = error.localizedDescription
        }

        deletingIDs.remove(backup.backupId)
        return didDelete
    }
}

struct BackupsView: View {
    @Bindable var viewModel: BackupsViewModel
    let onRestored: () async -> Void
    let onBackupsChanged: () async -> Void

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

            List(viewModel.backups) { backup in
                SkillBackupRow(
                    backup: backup,
                    restoreApp: viewModel.selectedRestoreApp,
                    isRestoring: viewModel.isRestoring(backup.backupId),
                    isDeleting: viewModel.isDeleting(backup.backupId)
                ) {
                    Task { await viewModel.restore(backup, onRestored: onRestored) }
                } onDelete: {
                    Task {
                        if await viewModel.delete(backup) {
                            await onBackupsChanged()
                        }
                    }
                }
                .listRowSeparator(.visible)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isLoading && viewModel.backups.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                } else if viewModel.backups.isEmpty {
                    ContentUnavailableView("No Backups", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .popPageBackground()
        .task {
            if !viewModel.hasLoadedOnce {
                await viewModel.load()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Backups")
                    .font(.system(.largeTitle, weight: .bold))
                Text("\(viewModel.backups.count) uninstall snapshots")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Restore In", selection: $viewModel.selectedRestoreApp) {
                ForEach(TargetApp.supported, id: \.id) { app in
                    Text(app.title).tag(app)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

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
            .buttonStyle(.borderedProminent)
            .help("Refresh")
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}

struct SkillBackupRow: View {
    let backup: SkillBackup
    let restoreApp: TargetApp
    let isRestoring: Bool
    let isDeleting: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var isConfirmingRestore = false
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(spacing: 14) {
            PackageAvatar(name: backup.skill.name, identifier: backup.backupId)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(backup.skill.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    StatusPill(title: createdAtText, color: .popStatusNeutral)
                }

                Text(backup.skill.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(backup.backupPath)
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)

            HStack(spacing: 8) {
                Button {
                    isConfirmingRestore = true
                } label: {
                    if isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRestoring || isDeleting)
                .help("Restore")
                .confirmationDialog(
                    "Restore \(backup.skill.name) to \(restoreApp.title)?",
                    isPresented: $isConfirmingRestore,
                    titleVisibility: .visible
                ) {
                    Button("Restore") {
                        onRestore()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Popskill will ask CC Switch to copy this backup into the managed skill store and enable it for \(restoreApp.title).")
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRestoring || isDeleting)
                .help("Delete Backup")
                .confirmationDialog(
                    "Delete backup for \(backup.skill.name)?",
                    isPresented: $isConfirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .frame(minHeight: 72)
    }

    private var createdAtText: String {
        Date(timeIntervalSince1970: TimeInterval(backup.createdAt))
            .formatted(date: .abbreviated, time: .shortened)
    }
}
