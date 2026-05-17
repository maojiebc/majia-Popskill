import SwiftUI

/// Updates — lists every skill whose remote content hash differs from local.
/// On `.task` we re-run `client.checkUpdates()` so the badge in the sidebar
/// reflects the latest scan; the user can also trigger a manual re-scan.
struct UpdatesView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var loading: Bool = false
    @State private var pendingUpdate: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            PopskillPageHeader(
                titleKey: "sidebar.updates",
                subtitle: subtitle
            ) {
                HStack(spacing: 8) {
                    Button {
                        Task { await rescan(force: true) }
                    } label: {
                        Label(localization.string("updates.rescan"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(loading)
                    Button {
                        Task { await updateAll() }
                    } label: {
                        Label(localization.string("updates.updateAll"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    // Also disable while a scan or per-row update is in
                    // flight — clicking "全部更新" mid-scan stacks two
                    // concurrent rescans and confuses pendingUpdate state.
                    .disabled(store.updates.isEmpty || loading || !pendingUpdate.isEmpty)
                }
            }

            if loading && store.updates.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.updates.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .popPageBackground()
        .task {
            // Cached helper short-circuits if last scan < 30s. The "Re-scan"
            // button passes force: true to bypass.
            if store.updates.isEmpty && store.lastUpdatesRefreshAt == nil {
                await rescan(force: false)
            }
        }
    }

    private var subtitle: String {
        if loading {
            return localization.string("updates.subtitleScanning", store.updates.count)
        }
        if let lastScanAt = store.lastUpdatesRefreshAt {
            return localization.string(
                "updates.subtitle",
                store.updates.count,
                Self.relativeScanFormatter.localizedString(for: lastScanAt, relativeTo: Date())
            )
        }
        return localization.string("updates.subtitleNoScan", store.updates.count)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.updates) { update in
                    row(update)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private func row(_ update: SkillUpdateInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(update.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.popLabel)
                if let current = update.currentHash {
                    Text("\(shortHash(current)) → \(shortHash(update.remoteHash))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.popSecondaryLabel)
                } else {
                    Text(localization.string("updates.row.firstSync"))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
            }
            Spacer(minLength: 8)
            if pendingUpdate.contains(update.id) {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await applyUpdate(update) }
                } label: {
                    Text(localization.string("updates.row.update"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .popCard(cornerRadius: PopskillRadius.smallCard, shadowOpacity: 0.02)
    }

    private func shortHash(_ hash: String) -> String {
        String(hash.prefix(7))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.popStatusOK)
            LocalizedText("updates.empty.title")
                .font(.title3.weight(.semibold))
            LocalizedText("updates.empty.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    @MainActor
    private func rescan(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        // Cached helper writes store.updates + store.lastUpdatesRefreshAt
        // and reports errors via store.errorMessage (now shown by the global
        // toast in RootView).
        await store.refreshUpdates(force: force)
    }

    @MainActor
    private func applyUpdate(_ update: SkillUpdateInfo) async {
        guard !pendingUpdate.contains(update.id) else { return }
        pendingUpdate.insert(update.id)
        defer { pendingUpdate.remove(update.id) }

        do {
            let refreshed = try await store.client.update(skillID: update.id)
            if let idx = store.skills.firstIndex(where: { $0.id == refreshed.id }) {
                store.skills[idx] = refreshed
            }
            store.updates.removeAll { $0.id == update.id }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func updateAll() async {
        guard pendingUpdate.isEmpty else { return }
        let pending = store.updates
        for update in pending {
            await applyUpdate(update)
        }
    }

    private static let relativeScanFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
