import SwiftUI

/// One skill row inside the matrix. Layout mirrors `matrixColumnHeader` in
/// `MatrixView.swift`: capability column (flexible), Claude toggle (100pt),
/// Codex toggle (100pt), source label (220pt), action menu (56pt).
struct MatrixRow: View {
    let skill: Skill
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    private var isSelected: Bool {
        store.selectedSkillID == skill.id
    }

    private var hasUpdate: Bool {
        store.updates.contains { $0.id == skill.id }
    }

    var body: some View {
        HStack(spacing: 0) {
            capabilityCell
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.vertical, 8)

            appToggleCell(for: .claude)
                .frame(width: 100)
            appToggleCell(for: .codex)
                .frame(width: 100)

            sourceCell
                .frame(width: 220, alignment: .leading)

            actionCell
                .frame(width: 56)
        }
        .contentShape(Rectangle())
        .background(rowBackground)
        .onTapGesture {
            store.selectSkill(skill.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(skill.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Cells

    private var capabilityCell: some View {
        HStack(alignment: .center, spacing: 10) {
            InitialAvatarView(name: skill.name, identifier: skill.id)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)
                    if hasUpdate {
                        Text(localization.string("matrix.row.updateBadge"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.16), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(capabilitySummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
            }
        }
    }

    private var capabilitySummary: String {
        if let summary = skill.capabilitySummary, !summary.isEmpty { return summary }
        if !skill.description.isEmpty { return skill.description }
        return localization.string("matrix.row.noSummary")
    }

    private func appToggleCell(for app: TargetApp) -> some View {
        HStack {
            Spacer(minLength: 0)
            AppToggle(
                app: app,
                isOn: skill.apps.isEnabled(app),
                isPending: store.pendingToggles.contains(toggleKey(app)),
                onChange: { newValue in
                    Task { await toggle(app: app, enabled: newValue) }
                },
                size: 26
            )
            Spacer(minLength: 0)
        }
    }

    private func toggleKey(_ app: TargetApp) -> String { "\(skill.id)|\(app.rawValue)" }

    @MainActor
    private func toggle(app: TargetApp, enabled: Bool) async {
        let key = toggleKey(app)
        guard !store.pendingToggles.contains(key) else { return }
        store.pendingToggles.insert(key)
        defer { store.pendingToggles.remove(key) }

        do {
            try await store.client.toggle(skillID: skill.id, app: app, enabled: enabled)
            if let idx = store.skills.firstIndex(where: { $0.id == skill.id }) {
                store.skills[idx].apps.setEnabled(enabled, for: app)
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var sourceCell: some View {
        HStack(spacing: 6) {
            Image(systemName: sourceSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.popSecondaryLabel)
            Text(skill.sourceLabel)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.popSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var sourceSymbol: String {
        switch (skill.sourceType ?? "").lowercased() {
        case "github": return "chevron.left.forwardslash.chevron.right"
        case "npm": return "shippingbox"
        case "brew": return "mug"
        case "pip": return "cube.box"
        case "builtin": return "house"
        case "folder": return "folder"
        case "zip": return "doc.zipper"
        case "url": return "link"
        case "md": return "doc.text"
        default: return "circle.grid.2x2"
        }
    }

    private var actionCell: some View {
        Menu {
            Button {
                store.selectSkill(skill.id)
            } label: {
                Label(localization.string("matrix.row.menu.inspect"), systemImage: "sidebar.right")
            }
            if let url = skill.sourceURL {
                Link(destination: url) {
                    Label(localization.string("matrix.row.menu.openSource"), systemImage: "arrow.up.right.square")
                }
            }
            if FileManager.default.fileExists(atPath: skill.localStoreURL.path) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([skill.localStoreURL])
                } label: {
                    Label(localization.string("matrix.row.menu.revealInFinder"), systemImage: "folder")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.popSecondaryLabel)
                .frame(width: 28, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(localization.string("matrix.row.menu.help"))
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.10)
            } else {
                Color.clear
            }
        }
    }
}

/// Sticky header above each repo bucket. Clicking the chevron collapses /
/// expands the bucket. The right side shows aggregate "%d enabled on Claude /
/// Codex" so users can see coverage without scanning every row.
struct MatrixGroupHeader: View {
    let group: MatrixGroup
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    private var isCollapsed: Bool {
        store.collapsedGroups.contains(group.id)
    }

    private var claudeOn: Int { group.skills.filter { $0.apps.claude }.count }
    private var codexOn: Int { group.skills.filter { $0.apps.codex }.count }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                toggleCollapse()
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Text(groupTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.popLabel)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("\(group.skills.count)")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.popSecondaryLabel)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.05), in: Capsule())

            Spacer(minLength: 8)

            coverageChip(symbol: "sparkles", label: "Claude", enabled: claudeOn, total: group.skills.count)
            coverageChip(symbol: "chevron.left.forwardslash.chevron.right", label: "Codex", enabled: codexOn, total: group.skills.count)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.025))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleCollapse()
        }
    }

    private var groupTitle: String {
        group.isUngrouped ? localization.string("matrix.group.ungrouped") : group.label
    }

    private func toggleCollapse() {
        if isCollapsed {
            store.collapsedGroups.remove(group.id)
        } else {
            store.collapsedGroups.insert(group.id)
        }
    }

    private func coverageChip(symbol: String, label: String, enabled: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
            Text("\(enabled)/\(total)")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(enabled > 0 ? Color.accentColor : Color.popTertiaryLabel)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            (enabled > 0 ? Color.accentColor.opacity(0.10) : Color.black.opacity(0.04)),
            in: Capsule()
        )
        .help("\(label): \(enabled)/\(total)")
    }
}
