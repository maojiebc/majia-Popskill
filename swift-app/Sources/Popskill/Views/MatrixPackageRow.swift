import AppKit
import SwiftUI

/// Composite package (套装) row in the capability matrix. The header row carries
/// the disclosure triangle, type tag, author, and a fraction+mini-bar coverage
/// cell; expanding it reveals the component tree with `├─ / └─` connectors.
/// Layout matches `matrixColumnHeader`: capability · 类型 · 作者 · Claude · Codex
/// · 版本 · Tokens · 调用.
@MainActor
struct MatrixPackageRow: View {
    let capability: MatrixCapability
    @Bindable var store: PopskillStore
    let usageIndex: MatrixUsageIndex
    @Environment(\.popskillLocalization) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var package: CapabilityPackage? { capability.package }

    private var isSelected: Bool {
        store.selectedSkillID == capability.id
    }

    private var isCollapsed: Bool {
        guard let package else { return true }
        return store.collapsedPackageIDs.contains(package.id)
    }

    private var bulkSelectionState: MatrixBulkSelectionState {
        store.matrixBulkSelectionState(for: capability)
    }

    var body: some View {
        VStack(spacing: 0) {
            packageHeader
            if let package, !isCollapsed {
                let components = package.components.all
                ForEach(Array(components.enumerated()), id: \.element.displayKey) { index, component in
                    MatrixPackageComponentRow(
                        component: component,
                        packageID: package.id,
                        treePrefix: PackageComponentTreePrefix.value(index: index, count: components.count),
                        store: store,
                        usageIndex: usageIndex
                    )
                    Divider().opacity(0.28)
                }
            }
        }
    }

    private var packageHeader: some View {
        HStack(spacing: 0) {
            bulkSelectionButton
                .frame(width: MatrixTableLayout.selectionColumnWidth)

            capabilityCell
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 0)
                .padding(.vertical, 7)

            typeCell
                .frame(width: MatrixTableLayout.typeColumnWidth, alignment: .leading)
            authorCell
                .frame(width: MatrixTableLayout.authorColumnWidth, alignment: .leading)

            coverageCell(for: .claude)
                .frame(width: MatrixTableLayout.appColumnWidth)
            coverageCell(for: .codex)
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
            if isSelected || bulkSelectionState.isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.popAccent)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .onTapGesture {
            if store.matrixBulkSelectedIDs.isEmpty {
                store.selectCapability(capability.id)
            } else {
                store.toggleMatrixBulkSelection(for: capability)
            }
        }
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isHovering)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(capability.name))
        .accessibilityHint(Text(capability.summary ?? localization.string("matrix.row.noSummary")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var bulkSelectionButton: some View {
        Button {
            store.toggleMatrixBulkSelection(for: capability)
        } label: {
            MatrixBulkCheckbox(state: bulkSelectionState)
        }
        .buttonStyle(.plain)
        .help(localization.string("matrix.bulk.selectRow"))
        .accessibilityLabel(Text(localization.string("matrix.bulk.selectRow")))
    }

    private var capabilityCell: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                if let package {
                    store.togglePackageExpansion(package.id)
                }
            } label: {
                Text(isCollapsed ? "▶" : "▼")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x444444))
                    .frame(width: 16, height: 18)
            }
            .buttonStyle(.plain)
            .help(localization.string(isCollapsed ? "matrix.package.expand" : "matrix.package.collapse"))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(capability.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)
                    if let package {
                        healthBadge(package.health)
                    }
                    if capability.hasBrokenLinks(in: store.skills) {
                        MatrixBrokenLinkBadge()
                    }
                    if store.hasPendingUpdate(for: capability) {
                        Text(localization.string("matrix.row.updateBadge"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.popAccentSoft, in: Capsule())
                            .foregroundStyle(Color.popAccent)
                    }
                }
                Text(packageSubtitle)
                    .font(.system(size: 11.2))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
                if !capability.sourceLabel.isEmpty {
                    Text("↗ \(capability.sourceLabel)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.popSecondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
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
        if let vendor = package?.vendor, !vendor.isEmpty { return vendor }
        if let owner = capability.repoOwner, !owner.isEmpty { return owner }
        return "—"
    }

    private func healthBadge(_ health: CapabilityPackageHealth) -> some View {
        let color = health.badgeColor
        return Text(localization.string(health.titleKey))
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var packageSubtitle: String {
        guard let package else { return capability.summary ?? localization.string("matrix.row.noSummary") }
        return PackageComponentCompositionFormatter.summary(for: package, localization: localization)
    }

    private func coverageCell(for app: TargetApp) -> some View {
        let coverage = capability.appCoverage[app] ?? CapabilityAppCoverage(enabled: 0, total: 0)
        return LedgerCoverageBar(
            enabled: coverage.enabled,
            total: coverage.total,
            help: localization.string("matrix.package.coverageHelp", app.title, coverage.enabled, coverage.total)
        )
    }

    private var usageSnapshot: PackageUsageSnapshot? {
        usageIndex.packageSnapshot(for: package?.id)
    }

    private var versionCell: some View {
        MatrixVersionValueCell(value: MatrixVersionFormatter.value(
            contentHash: package?.trackedContentHash,
            updatedAt: package?.lifecycle?.updatedAt
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

    private func usageText(_ format: (PackageUsageSnapshot) -> String) -> String? {
        guard let snapshot = usageSnapshot else {
            return nil
        }
        return snapshot.hasUsage ? format(snapshot) : "0"
    }

    private var rowBackground: some View {
        Group {
            if bulkSelectionState.isSelected {
                Color.popAccentSoft.opacity(0.84)
            } else if isSelected {
                Color.popSelectedRowFill
            } else if isHovering {
                Color.popSurfaceHover
            } else {
                Color.popSubtleFill
            }
        }
    }
}

@MainActor
private struct MatrixPackageComponentRow: View {
    let component: PackageComponent
    let packageID: String
    let treePrefix: String
    @Bindable var store: PopskillStore
    let usageIndex: MatrixUsageIndex
    @Environment(\.popskillLocalization) private var localization

    private var matchingSkill: Skill? {
        store.skill(for: component)
    }

    private var bulkSelectionState: MatrixBulkSelectionState {
        store.matrixBulkSelectionState(packageID: packageID, component: component)
    }

    var body: some View {
        HStack(spacing: 0) {
            bulkSelectionButton
                .frame(width: MatrixTableLayout.selectionColumnWidth)

            componentCell
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
                .padding(.vertical, 5)

            componentTypeCell
                .frame(width: MatrixTableLayout.typeColumnWidth, alignment: .leading)
            Color.clear
                .frame(width: MatrixTableLayout.authorColumnWidth)

            appStateCell(for: .claude)
                .frame(width: MatrixTableLayout.appColumnWidth)
            appStateCell(for: .codex)
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
        .onTapGesture {
            if store.matrixBulkSelectedIDs.isEmpty, let skill = matchingSkill {
                store.selectSkill(skill.id)
            } else {
                store.toggleMatrixBulkComponentSelection(packageID: packageID, component: component)
            }
        }
        .background(bulkSelectionState.isSelected ? Color.popAccentSoft.opacity(0.68) : Color.popChildRowFill)
    }

    private var bulkSelectionButton: some View {
        Button {
            store.toggleMatrixBulkComponentSelection(packageID: packageID, component: component)
        } label: {
            MatrixBulkCheckbox(state: bulkSelectionState)
        }
        .buttonStyle(.plain)
        .help(localization.string("matrix.bulk.selectRow"))
        .accessibilityLabel(Text(localization.string("matrix.bulk.selectRow")))
    }

    private var componentCell: some View {
        HStack(spacing: 9) {
            Text(treePrefix)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.popLinkOff)
                .frame(width: 18, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(component.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)
                    if let requirement = requirementBadge {
                        Text(localization.string(requirement.key))
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(requirement.color)
                    }
                    if matchingSkill?.hasBrokenLink == true {
                        MatrixBrokenLinkBadge()
                    }
                }
                Text(component.status)
                    .font(.system(size: 10.2))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
            }
        }
    }

    private var componentTypeCell: some View {
        HStack(spacing: 0) {
            Text(component.kind.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color.popSecondaryLabel)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.popControlFill, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.popControlStroke, lineWidth: 0.7)
                )
            Spacer(minLength: 0)
        }
    }

    private var requirementBadge: (key: String, color: Color)? {
        if component.required && !component.installed {
            return ("matrix.package.component.required", Color.popStatusWarning)
        }
        if !component.required {
            return ("matrix.package.component.optional", Color.popTertiaryLabel)
        }
        return nil
    }

    private func appStateCell(for app: TargetApp) -> some View {
        let state = component.linkState(for: app, matching: matchingSkill)
        return HStack {
            Spacer(minLength: 0)
            LedgerStatusGlyph(
                state: state,
                help: localization.string("matrix.package.component.stateHelp", app.title)
            )
            Spacer(minLength: 0)
        }
    }

    private var usageStat: PackageComponentUsageStat? {
        usageIndex.packageComponentStat(packageID: packageID, componentID: component.id)
    }

    private var versionCell: some View {
        MatrixVersionValueCell(
            value: MatrixVersionFormatter.value(
                manifestVersion: matchingSkill?.manifest?.semanticVersion,
                contentHash: matchingSkill?.contentHash,
                updatedAt: matchingSkill?.updatedAt
            ),
            isSubtle: true
        )
    }

    private var tokensCell: some View {
        MatrixUsageValueCell(value: usageText { stat in
            UsageDisplayFormatter.compactTokens(stat.totalTokens)
        }, isSubtle: true)
    }

    private var callsCell: some View {
        MatrixUsageValueCell(value: usageText { stat in
            UsageDisplayFormatter.compactCount(stat.usageEvents)
        }, isSubtle: true)
    }

    private func usageText(_ format: (PackageComponentUsageStat) -> String) -> String? {
        guard usageIndex.hasSummary else {
            return nil
        }
        guard let usageStat else {
            return "0"
        }
        return usageStat.usageEvents > 0 || usageStat.totalTokens > 0 ? format(usageStat) : "0"
    }
}

enum PackageComponentTreePrefix {
    static func value(index: Int, count: Int) -> String {
        guard count > 0, index == count - 1 else {
            return "├─"
        }
        return "└─"
    }
}

private extension CapabilityPackageHealth {
    var titleKey: String {
        switch self {
        case .active: "matrix.package.health.active"
        case .partial: "matrix.package.health.partial"
        case .inactive: "matrix.package.health.inactive"
        case .blocked: "matrix.package.health.blocked"
        }
    }

    var badgeColor: Color {
        switch self {
        case .active: Color.popStatusOK
        case .partial: Color.popStatusWarning
        case .inactive: Color.popTertiaryLabel
        case .blocked: Color.popStatusError
        }
    }
}

private extension PackageComponent {
    var kindSymbol: String {
        switch kind.lowercased() {
        case "skill": "square.grid.3x3.fill"
        case "agent": "person.crop.square"
        case "cli": "terminal"
        case "mcp": "rectangle.connected.to.line.below"
        default: "circle.grid.2x2"
        }
    }

    /// Map a component's per-tool installation state onto the ledger glyph set.
    func linkState(for app: TargetApp, matching skill: Skill?) -> LedgerLinkState {
        switch kind.lowercased() {
        case "skill":
            if let skill {
                guard skill.apps.isEnabled(app) else { return .off }
                return skill.hasBrokenLink ? .broken : .on
            }
            return installed ? .on : (status.lowercased() == "stub" ? .stub : .off)
        case "agent":
            if installed && app == .claude { return .on }
            return status.lowercased() == "stub" && app == .claude ? .stub : .off
        case "cli", "mcp":
            return installed && (app == .claude || app == .codex) ? .on : .off
        default:
            return .off
        }
    }
}
