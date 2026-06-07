import SwiftUI

/// One capability row inside the matrix. Layout mirrors `matrixColumnHeader`
/// in `MatrixView.swift`: capability (flexible) · 类型 · 作者 · Claude · Codex ·
/// 版本 · Tokens · 调用. Renders Skill / Agent / CLI / MCP / Config via the
/// unified `MatrixCapability` model. The Claude/Codex cells are the design's
/// ●/—/◐/✕ ledger glyph; for skills it stays tappable (toggles that tool's link).
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

            typeCell
                .frame(width: MatrixTableLayout.typeColumnWidth, alignment: .leading)
            authorCell
                .frame(width: MatrixTableLayout.authorColumnWidth, alignment: .leading)

            statusCell(for: .claude)
                .frame(width: MatrixTableLayout.appColumnWidth)
            statusCell(for: .codex)
                .frame(width: MatrixTableLayout.appColumnWidth)

            versionCell
                .frame(width: MatrixTableLayout.versionColumnWidth, alignment: .leading)
            tokensCell
                .frame(width: MatrixTableLayout.tokensColumnWidth, alignment: .trailing)
            callsCell
                .frame(width: MatrixTableLayout.callsColumnWidth, alignment: .trailing)
        }
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.popAccent)
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
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(capability.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.popLabel)
                    .lineLimit(1)
                if capability.hasBrokenLinks(in: store.skills) {
                    MatrixBrokenLinkBadge()
                }
                if hasUpdate {
                    Text(localization.string("matrix.row.updateBadge"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.popAccentSoft, in: Capsule())
                        .foregroundStyle(Color.popAccent)
                }
            }
            Text(summary)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.popSecondaryLabel)
                .lineLimit(1)
        }
    }

    private var typeCell: some View {
        HStack(spacing: 0) {
            LedgerTypeTag(kind: capability.kind)
            Spacer(minLength: 0)
        }
    }

    private var authorCell: some View {
        Text(authorText)
            .font(.system(size: 11.5))
            .foregroundStyle(Color.popSecondaryLabel)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorText: String {
        if let owner = capability.repoOwner, !owner.isEmpty { return owner }
        if let type = capability.sourceType, !type.isEmpty { return type }
        return "—"
    }

    private var summary: String {
        if let summary = capability.summary, !summary.isEmpty { return summary }
        return localization.string("matrix.row.noSummary")
    }

    /// Ledger glyph for one tool. Skills stay tappable (toggle that link); other
    /// kinds render read-only. Maps enabled→●, broken→✕, otherwise →— .
    @ViewBuilder
    private func statusCell(for app: TargetApp) -> some View {
        let enabled = capability.apps.isEnabled(app)
        let broken = enabled && capability.hasBrokenLinks(in: store.skills)
        let state: LedgerLinkState = enabled ? (broken ? .broken : .on) : .off
        HStack {
            Spacer(minLength: 0)
            if capability.isToggleable {
                LedgerStatusGlyph(
                    state: state,
                    isPending: store.pendingToggles.contains(toggleKey(app)),
                    help: localization.string("matrix.row.toggleHelp", app.title),
                    onToggle: { Task { await toggle(app: app, enabled: !enabled) } }
                )
            } else {
                LedgerStatusGlyph(
                    state: state,
                    help: localization.string("matrix.row.readOnly")
                )
            }
            Spacer(minLength: 0)
        }
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
/// / Codex" so users can see coverage without scanning every row.
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
                .overlay(Capsule().strokeBorder(Color.popControlStroke, lineWidth: 0.7))

            Spacer(minLength: 8)

            coverageChip(symbol: "sparkles", label: "Claude", enabled: claudeOn, total: group.capabilities.count)
            coverageChip(symbol: "chevron.left.forwardslash.chevron.right", label: "Codex", enabled: codexOn, total: group.capabilities.count)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.popSurface)
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
        .foregroundStyle(enabled > 0 ? Color.popAccent : Color.popTertiaryLabel)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            (enabled > 0 ? Color.popAccentSoft : Color.popControlFill),
            in: Capsule()
        )
        .help(localization.string("matrix.group.coverageHelp", label, enabled, total))
    }
}
