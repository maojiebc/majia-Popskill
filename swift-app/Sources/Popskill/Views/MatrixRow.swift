import SwiftUI

/// One capability row inside the matrix. Layout mirrors `matrixColumnHeader`
/// in `MatrixView.swift`: capability column (flexible), tool coverage,
/// source, version identity, usage metrics, and action menu.
/// Renders Skill / Agent / CLI / MCP / Config via the unified
/// `MatrixCapability` model; non-toggleable kinds (anything but skill) show
/// a read-only "on" icon instead of the interactive switch.
@MainActor
struct MatrixRow: View {
    let capability: MatrixCapability
    @Bindable var store: PopskillStore
    let usageIndex: MatrixUsageIndex
    @Environment(\.popskillLocalization) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var isSelected: Bool {
        store.selectedSkillID == capability.id
    }

    private var hasUpdate: Bool {
        store.hasPendingUpdate(for: capability)
    }

    var body: some View {
        HStack(spacing: 0) {
            capabilityCell
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.vertical, 6)

            appToggleCell(for: .claude)
                .frame(width: MatrixTableLayout.appColumnWidth)
            appToggleCell(for: .codex)
                .frame(width: MatrixTableLayout.appColumnWidth)

            sourceCell
                .frame(width: MatrixTableLayout.sourceColumnWidth, alignment: .leading)
            versionCell
                .frame(width: MatrixTableLayout.versionColumnWidth, alignment: .leading)

            tokensCell
                .frame(width: MatrixTableLayout.tokensColumnWidth, alignment: .trailing)
            callsCell
                .frame(width: MatrixTableLayout.callsColumnWidth, alignment: .trailing)

            actionCell
                .frame(width: MatrixTableLayout.actionColumnWidth)
        }
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .onTapGesture {
            store.selectCapability(capability.id)
        }
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isHovering)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(capability.name))
        .accessibilityHint(Text(summary))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Cells

    private var capabilityCell: some View {
        HStack(alignment: .center, spacing: 10) {
            InitialAvatarView(name: capability.name, identifier: capability.id, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(capability.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)
                    kindBadge
                    if capability.hasBrokenLinks(in: store.skills) {
                        MatrixBrokenLinkBadge()
                    }
                    if hasUpdate {
                        Text(localization.string("matrix.row.updateBadge"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.16), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
            }
        }
    }

    /// Small chip next to the row name when the row isn't a Skill. Skill rows
    /// stay un-badged because they're the matrix default and the chip would
    /// just add noise.
    @ViewBuilder
    private var kindBadge: some View {
        if capability.kind != .skill {
            HStack(spacing: 2) {
                Image(systemName: capability.kind.symbol)
                    .font(.system(size: 8, weight: .semibold))
                Text(localization.string(capability.kind.titleKey).uppercased())
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color.popSecondaryLabel)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.popControlFill, in: Capsule())
        }
    }

    private var summary: String {
        if let summary = capability.summary, !summary.isEmpty { return summary }
        return localization.string("matrix.row.noSummary")
    }

    @ViewBuilder
    private func appToggleCell(for app: TargetApp) -> some View {
        HStack {
            Spacer(minLength: 0)
            if capability.isToggleable {
                AppToggle(
                    app: app,
                    isOn: capability.apps.isEnabled(app),
                    isPending: store.pendingToggles.contains(toggleKey(app)),
                    onChange: { newValue in
                        Task { await toggle(app: app, enabled: newValue) }
                    },
                    size: 22
                )
            } else {
                readOnlyAppBadge(app: app, isOn: capability.apps.isEnabled(app))
            }
            Spacer(minLength: 0)
        }
    }

    /// Non-skill capabilities (agents in v0.4) can't be toggled per-app yet.
    /// Render a flat icon that conveys "this lives on Claude" without the
    /// affordance of a button. Codex column shows a muted dash.
    private func readOnlyAppBadge(app: TargetApp, isOn: Bool) -> some View {
        Group {
            if isOn {
                Image(systemName: app.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
            } else {
                Text("—")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.popTertiaryLabel)
            }
        }
        .frame(width: 26, height: 26)
        .help(localization.string("matrix.row.readOnly"))
    }

    private func toggleKey(_ app: TargetApp) -> String {
        MatrixCapability.toggleKey(capabilityID: capability.id, app: app)
    }

    @MainActor
    private func toggle(app: TargetApp, enabled: Bool) async {
        guard let skillID = capability.underlyingSkillID else { return }
        let key = toggleKey(app)
        guard !store.pendingToggles.contains(key) else { return }
        store.pendingToggles.insert(key)
        defer { store.pendingToggles.remove(key) }

        do {
            try await store.client.toggle(skillID: skillID, app: app, enabled: enabled)
            if let idx = store.skills.firstIndex(where: { $0.id == skillID }) {
                store.skills[idx].apps.setEnabled(enabled, for: app)
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var sourceCell: some View {
        HStack(spacing: 6) {
            Image(systemName: sourceSymbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.popSecondaryLabel)
            Text(capability.sourceLabel)
                .font(.system(size: 11))
                .foregroundStyle(Color.popSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var usageSnapshot: SkillUsageSnapshot? {
        usageIndex.skillSnapshot(for: capability.underlyingSkillID)
    }

    private var versionCell: some View {
        let skill = capability.underlyingSkillID.flatMap { skillID in
            store.skills.first { $0.id == skillID }
        }
        return MatrixVersionValueCell(value: MatrixVersionFormatter.value(
            manifestVersion: skill?.manifest?.semanticVersion,
            contentHash: skill?.contentHash,
            updatedAt: capability.updatedAt
        ))
    }

    private var tokensCell: some View {
        MatrixUsageValueCell(value: usageText { snapshot in
            UsageDisplayFormatter.compactTokens(snapshot.totalTokens)
        })
    }

    private var callsCell: some View {
        MatrixUsageValueCell(value: usageText { snapshot in
            UsageDisplayFormatter.compactCount(snapshot.usageEvents)
        })
    }

    private func usageText(_ format: (SkillUsageSnapshot) -> String) -> String? {
        guard let snapshot = usageSnapshot else {
            return nil
        }
        return snapshot.hasUsage ? format(snapshot) : "0"
    }

    private var sourceSymbol: String {
        switch (capability.sourceType ?? "").lowercased() {
        case "github": return "chevron.left.forwardslash.chevron.right"
        case "npm": return "shippingbox"
        case "brew": return "mug"
        case "pip": return "cube.box"
        case "builtin": return "house"
        case "folder": return "folder"
        case "zip": return "doc.zipper"
        case "url": return "link"
        case "md": return "doc.text"
        case "agent": return "person.crop.square"
        default: return "circle.grid.2x2"
        }
    }

    private var actionCell: some View {
        Menu {
            Button {
                store.selectCapability(capability.id)
            } label: {
                Label(localization.string("matrix.row.menu.inspect"), systemImage: "sidebar.right")
            }
            if let url = capability.sourceURL {
                Link(destination: url) {
                    Label(localization.string("matrix.row.menu.openSource"), systemImage: "arrow.up.right.square")
                }
            }
            if let skillID = capability.underlyingSkillID,
               let skill = store.skills.first(where: { $0.id == skillID }),
               FileManager.default.fileExists(atPath: skill.localStoreURL.path) {
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
                Color.popSelectedRowFill
            } else if isHovering {
                Color.popSurfaceHover
            } else {
                Color.clear
            }
        }
    }
}

struct MatrixVersionValueCell: View {
    let value: String?
    var isSubtle = false

    var body: some View {
        Text(value ?? "—")
            .font(.system(size: isSubtle ? 10.3 : 10.8, weight: .medium, design: .monospaced))
            .foregroundStyle(value == nil ? Color.popTertiaryLabel : (isSubtle ? Color.popSecondaryLabel : Color.popLabel))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
    }
}

struct MatrixUsageValueCell: View {
    let value: String?
    var isSubtle = false

    var body: some View {
        Text(value ?? "—")
            .font(.system(size: isSubtle ? 10.5 : 11, weight: isSubtle ? .regular : .medium).monospacedDigit())
            .foregroundStyle(value == nil ? Color.popTertiaryLabel : (isSubtle ? Color.popSecondaryLabel : Color.popLabel))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 8)
    }
}

/// Sticky header above each repo bucket. Clicking the chevron collapses /
/// expands the bucket. The right side shows aggregate "%d enabled on Claude
/// / Codex" so users can see coverage without scanning every row. v0.4
/// renders the same header for any capability kind — the kind-level banner
/// in MatrixView provides the kind context.
@MainActor
struct MatrixGroupHeader: View {
    let group: MatrixGroup
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    private var isCollapsed: Bool {
        store.collapsedGroups.contains(group.id)
    }

    private var claudeOn: Int { group.capabilities.filter { $0.apps.claude }.count }
    private var codexOn: Int { group.capabilities.filter { $0.apps.codex }.count }

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

            Text("\(group.capabilities.count)")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.popSecondaryLabel)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.popControlFill, in: Capsule())

            Spacer(minLength: 8)

            coverageChip(symbol: "sparkles", label: "Claude", enabled: claudeOn, total: group.capabilities.count)
            coverageChip(symbol: "chevron.left.forwardslash.chevron.right", label: "Codex", enabled: codexOn, total: group.capabilities.count)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.popSurface.opacity(0.36))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.popSeparator)
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
            (enabled > 0 ? Color.popAccentSoft : Color.popControlFill),
            in: Capsule()
        )
        .help(localization.string("matrix.group.coverageHelp", label, enabled, total))
    }
}
