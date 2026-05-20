import SwiftUI

/// Backups — snapshots created by the safe-by-default uninstall strategy (#12
/// in 麦麦 13-项校准: "保护用户原数据是最高优先级"). v0.3 lists them flat
/// with date headers and per-row restore / delete. Restore picks Claude by
/// default since most users only have Claude wired; v0.4 will add a target
/// chooser.
@MainActor
struct BackupsView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var loading: Bool = false
    @State private var pendingRestore: Set<String> = []
    @State private var pendingDelete: Set<String> = []
    @State private var pendingDeleteConfirmation: SkillBackup?

    var body: some View {
        VStack(spacing: 0) {
            PopskillPageHeader(
                titleKey: "sidebar.backups",
                subtitle: localization.string("backups.subtitle", store.backups.count)
            ) {
                Button {
                    Task { await refresh(force: true) }
                } label: {
                    Label(localization.string("backups.refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(loading)
            }

            if loading && store.backups.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.backups.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .popPageBackground()
        .task {
            // Cached helper avoids redundant sidecar round-trips when the
            // user toggles back and forth between sidebar entries within
            // the 30s TTL window. Manual refresh button uses force: true.
            await refresh(force: false)
        }
        .confirmationDialog(
            localization.string("backups.row.delete.confirm.title"),
            isPresented: deleteDialogPresented,
            titleVisibility: .visible
        ) {
            if let pendingDeleteConfirmation {
                Button(localization.string("backups.row.delete.confirm.button"), role: .destructive) {
                    Task { await deleteBackup(pendingDeleteConfirmation) }
                }
            }
            Button(localization.string("sources.add.cancel"), role: .cancel) {
                pendingDeleteConfirmation = nil
            }
        } message: {
            if let pendingDeleteConfirmation {
                Text(localization.string("backups.row.delete.confirm.message", pendingDeleteConfirmation.skill.name))
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedByDay, id: \.day) { bucket in
                    Section {
                        ForEach(bucket.backups) { backup in
                            row(backup)
                        }
                    } header: {
                        Text(bucket.day)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.popTertiaryLabel)
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 6)
                            .background(.thinMaterial)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private struct BackupBucket {
        let day: String
        let backups: [SkillBackup]
    }

    private var groupedByDay: [BackupBucket] {
        let buckets = Dictionary(grouping: store.backups) { backup -> String in
            Self.dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(backup.createdAt)))
        }
        return buckets
            .map { key, value in BackupBucket(day: key, backups: value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { lhs, rhs in
                let l = lhs.backups.first?.createdAt ?? 0
                let r = rhs.backups.first?.createdAt ?? 0
                return l > r
            }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteConfirmation = nil
                }
            }
        )
    }

    private func row(_ backup: SkillBackup) -> some View {
        HStack(spacing: 12) {
            InitialAvatarView(name: backup.skill.name, identifier: backup.skill.id)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(backup.skill.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.popLabel)
                Text(Self.formatTimestamp(backup.createdAt))
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer(minLength: 8)
            if pendingRestore.contains(backup.backupId) || pendingDelete.contains(backup.backupId) {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await restore(backup) }
                } label: {
                    Text(localization.string("backups.row.restore"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Menu {
                    Button(role: .destructive) {
                        pendingDeleteConfirmation = backup
                    } label: {
                        Label(localization.string("backups.row.delete"), systemImage: "trash")
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .popCard(cornerRadius: PopskillRadius.smallCard, shadowOpacity: 0.02)
        .padding(.horizontal, 28)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            LocalizedText("backups.empty.title")
                .font(.title3.weight(.semibold))
            LocalizedText("backups.empty.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    @MainActor
    private func refresh(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        // Cached helper short-circuits within the TTL window and reports
        // failures via store.errorMessage (now shown by the global toast).
        await store.refreshBackups(force: force)
    }

    @MainActor
    private func restore(_ backup: SkillBackup) async {
        guard !pendingRestore.contains(backup.backupId) else { return }
        pendingRestore.insert(backup.backupId)
        defer { pendingRestore.remove(backup.backupId) }
        do {
            let restored = try await store.client.restoreBackup(backupID: backup.backupId, app: .claude)
            if let idx = store.skills.firstIndex(where: { $0.id == restored.id }) {
                store.skills[idx] = restored
            } else {
                store.skills.append(restored)
            }
            store.backups.removeAll { $0.backupId == backup.backupId }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteBackup(_ backup: SkillBackup) async {
        guard !pendingDelete.contains(backup.backupId) else { return }
        pendingDeleteConfirmation = nil
        pendingDelete.insert(backup.backupId)
        defer { pendingDelete.remove(backup.backupId) }
        do {
            let result = try await store.client.deleteBackup(backupID: backup.backupId)
            store.backups.removeAll { $0.backupId == result.backupId }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private static func formatTimestamp(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        return timestampFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
