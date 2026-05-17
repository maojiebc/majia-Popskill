import SwiftUI

/// Settings — collapsed to 4 cards for v0.3 to match the prototype:
///   1. 存储路径 — where SSOT, backups, and library live; reveal in Finder.
///   2. 同步 — iCloud / Git / WebDAV / None radio + per-provider config.
///      The non-Git providers are placeholder buttons (sidecar gates them).
///   3. 数据源管理 — count + jump to Sources view.
///   4. 重新引导 — re-run the 5-step Onboarding (S6) explicitly.
struct SettingsView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var syncProvider: SyncProvider = .git
    @State private var pendingSync: Bool = false
    @State private var syncMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PopskillPageHeader(
                    titleKey: "sidebar.settings",
                    subtitle: localization.string("settings.subtitle")
                )

                storageCard.padding(.horizontal, 28)
                syncCard.padding(.horizontal, 28)
                sourcesCard.padding(.horizontal, 28)
                onboardingCard.padding(.horizontal, 28)

                Color.clear.frame(height: 32)
            }
        }
        .popPageBackground()
        .onAppear {
            if let provider = SyncProvider(rawValue: store.lastSyncProvider) {
                syncProvider = provider
            }
        }
    }

    // MARK: Storage

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "settings.storage.title")
            pathRow(
                labelKey: "settings.storage.ssot",
                path: ssotPath,
                hintKey: "settings.storage.ssotHint"
            )
            pathRow(
                labelKey: "settings.storage.backups",
                path: backupsPath,
                hintKey: "settings.storage.backupsHint"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    private func pathRow(labelKey: String, path: String, hintKey: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                LocalizedText(labelKey)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.popLabel)
                Spacer()
                Button {
                    revealInFinder(path)
                } label: {
                    Label(localization.string("settings.storage.reveal"), systemImage: "folder")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(path)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color.popSecondaryLabel)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            LocalizedText(hintKey)
                .font(.caption2)
                .foregroundStyle(Color.popTertiaryLabel)
        }
    }

    private var ssotPath: String {
        // The actual SSOT path sidecar uses, as reported by `skill-cli health`.
        // v0.x ships on CC Switch's storage convention; the ~/.agents/skills
        // migration is planned for v1.1.x. Earlier copies of this string read
        // ".agents/skills" — that was aspirational, not real, and Reveal-in-
        // Finder jumped to a non-existent directory.
        (NSHomeDirectory() as NSString).appendingPathComponent(".cc-switch/skills")
    }

    private var backupsPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".popskill/backups")
    }

    private func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    // MARK: Sync

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "settings.sync.title")
            ForEach(SyncProvider.allCases) { provider in
                providerRow(provider)
            }
            HStack(spacing: 8) {
                Button {
                    Task { await runSync(.push) }
                } label: {
                    Label(localization.string("settings.sync.push"), systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(pendingSync || !syncProvider.actionable)

                Button {
                    Task { await runSync(.pull) }
                } label: {
                    Label(localization.string("settings.sync.pull"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(pendingSync || !syncProvider.actionable)

                if pendingSync {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            if let syncMessage {
                Text(syncMessage)
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    private func providerRow(_ provider: SyncProvider) -> some View {
        Button {
            syncProvider = provider
            store.lastSyncProvider = provider.rawValue
        } label: {
            HStack(spacing: 10) {
                Image(systemName: syncProvider == provider ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(syncProvider == provider ? Color.accentColor : Color.popTertiaryLabel)
                Image(systemName: provider.symbol)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(localization.string(provider.titleKey))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.popLabel)
                    Text(localization.string(provider.subtitleKey))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
                Spacer()
                if !provider.implemented {
                    Text(localization.string("settings.sync.soon"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.popStatusWarning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.popStatusWarning.opacity(0.14), in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func runSync(_ action: SyncAction) async {
        guard !pendingSync, syncProvider.actionable else { return }
        pendingSync = true
        syncMessage = nil
        defer { pendingSync = false }
        do {
            let result = try await store.client.sync(action: action.rawValue, provider: syncProvider.rawValue)
            syncMessage = result.message ?? localization.string("settings.sync.done", action.rawValue, syncProvider.rawValue)
            if result.ok == true {
                store.lastSyncAt = Date()
            }
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    // MARK: Sources card

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "settings.sources.title")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.string("settings.sources.summary", store.sources.filter(\.enabled).count, store.sources.count))
                        .font(.callout)
                        .foregroundStyle(Color.popLabel)
                    Text(localization.string("settings.sources.hint"))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
                Spacer()
                Button {
                    store.currentSelection = .sources
                } label: {
                    Text(localization.string("settings.sources.manage"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    // MARK: Onboarding re-run

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "settings.onboarding.title")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    LocalizedText("settings.onboarding.body")
                        .font(.callout)
                        .foregroundStyle(Color.popLabel)
                    LocalizedText("settings.onboarding.hint")
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
                Spacer()
                Button {
                    store.onboardingOpen = true
                } label: {
                    Text(localization.string("settings.onboarding.openButton"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.card)
    }
}

enum SyncProvider: String, CaseIterable, Identifiable, Codable {
    case icloud, git, webdav, none

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .icloud: return "settings.sync.icloud.title"
        case .git:    return "settings.sync.git.title"
        case .webdav: return "settings.sync.webdav.title"
        case .none:   return "settings.sync.none.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .icloud: return "settings.sync.icloud.subtitle"
        case .git:    return "settings.sync.git.subtitle"
        case .webdav: return "settings.sync.webdav.subtitle"
        case .none:   return "settings.sync.none.subtitle"
        }
    }

    var symbol: String {
        switch self {
        case .icloud: return "icloud"
        case .git:    return "chevron.left.forwardslash.chevron.right"
        case .webdav: return "externaldrive.connected.to.line.below"
        case .none:   return "nosign"
        }
    }

    /// `.git` shipped in v0.3, `.icloud` in v0.4 (rsync to iCloud Drive
    /// container). WebDAV stays "SOON" until v0.5 — the v0.4 timebox
    /// prioritized the native Mac sync path.
    var implemented: Bool {
        self == .git || self == .icloud
    }

    var actionable: Bool {
        implemented
    }
}

enum SyncAction: String {
    case push, pull, status
}
