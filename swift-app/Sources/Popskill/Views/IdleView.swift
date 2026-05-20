import SwiftUI

/// Idle — skills that are toggled off across every app **and** haven't been
/// touched (install / update / use) for ≥ 60 days. Surfaces the standard
/// majia "卸载也安全" three-strategy decision per row.
@MainActor
struct IdleView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var thresholdDays: Int = 60
    @State private var pendingMutation: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            PopskillPageHeader(
                titleKey: "sidebar.idle",
                subtitle: localization.string("idle.subtitle", idleCandidates.count, thresholdDays)
            ) {
                Picker("", selection: $thresholdDays) {
                    Text(localization.string("idle.threshold.30")).tag(30)
                    Text(localization.string("idle.threshold.60")).tag(60)
                    Text(localization.string("idle.threshold.90")).tag(90)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            if idleCandidates.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .popPageBackground()
    }

    private var idleCandidates: [Skill] {
        store.skills.filter { $0.isIdleCandidate(thresholdDays: thresholdDays) }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(idleCandidates, id: \.id) { skill in
                    row(skill)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private func row(_ skill: Skill) -> some View {
        HStack(spacing: 12) {
            InitialAvatarView(name: skill.name, identifier: skill.id)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.popLabel)
                if let ts = skill.lastLifecycleTimestamp {
                    Text(localization.string("idle.row.lastSeen", Self.daysAgo(ts)))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                } else {
                    Text(localization.string("idle.row.neverTouched"))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
            }
            Spacer(minLength: 8)
            if pendingMutation.contains(skill.id) {
                ProgressView().controlSize(.small)
            } else {
                actionsMenu(skill)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .popCard(cornerRadius: PopskillRadius.smallCard, shadowOpacity: 0.02)
    }

    private func actionsMenu(_ skill: Skill) -> some View {
        Menu {
            Button {
                store.currentSelection = .matrix
                store.selectSkill(skill.id)
            } label: {
                Label(localization.string("idle.row.inspect"), systemImage: "sidebar.right")
            }
            Button {
                Task { await stub(skill) }
            } label: {
                Label(localization.string("idle.row.stub"), systemImage: "archivebox")
            }
            Button(role: .destructive) {
                Task { await uninstall(skill, strategy: .backup) }
            } label: {
                Label(localization.string("idle.row.uninstall"), systemImage: "trash")
            }
        } label: {
            HStack(spacing: 4) {
                Text(localization.string("idle.row.action"))
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wind")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            LocalizedText("idle.empty.title")
                .font(.title3.weight(.semibold))
            LocalizedText("idle.empty.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    @MainActor
    private func stub(_ skill: Skill) async {
        guard !pendingMutation.contains(skill.id) else { return }
        pendingMutation.insert(skill.id)
        defer { pendingMutation.remove(skill.id) }

        do {
            let stub = try await store.client.stub(skillID: skill.id)
            store.stubs.append(stub)
            store.skills.removeAll { $0.id == skill.id }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func uninstall(_ skill: Skill, strategy: UninstallStrategy) async {
        guard !pendingMutation.contains(skill.id) else { return }
        pendingMutation.insert(skill.id)
        defer { pendingMutation.remove(skill.id) }

        do {
            let result = try await store.client.uninstall(skillID: skill.id, strategy: strategy)
            // The sidecar may return the surviving skill (when strategy=.keep)
            // or just a backup pointer (when strategy=.backup/.delete).
            if let survivor = result.skill {
                if let idx = store.skills.firstIndex(where: { $0.id == survivor.id }) {
                    store.skills[idx] = survivor
                }
            } else {
                store.skills.removeAll { $0.id == skill.id }
            }
            if strategy == .backup {
                await refreshBackups()
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshBackups() async {
        do {
            store.backups = try await store.client.listBackups()
        } catch {
            // Non-fatal — backup refresh is a UI nicety.
        }
    }

    private static func daysAgo(_ ts: Int) -> Int {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        return max(0, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0)
    }
}
