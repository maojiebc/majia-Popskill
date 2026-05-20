import AppKit
import SwiftUI

/// Composite package row in the capability matrix. The row is read-only at the
/// package level for v1.1, but it exposes the component tree inline so Bundle
/// coverage is visible without opening a detail page.
struct MatrixPackageRow: View {
    let capability: MatrixCapability
    @Bindable var store: PopskillStore
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

    var body: some View {
        VStack(spacing: 0) {
            packageHeader
            if let package, !isCollapsed {
                ForEach(package.components.all, id: \.displayKey) { component in
                    MatrixPackageComponentRow(component: component, store: store)
                    Divider().opacity(0.28)
                }
            }
        }
    }

    private var packageHeader: some View {
        HStack(spacing: 0) {
            capabilityCell
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.vertical, 9)

            coverageCell(for: .claude)
                .frame(width: 100)
            coverageCell(for: .codex)
                .frame(width: 100)

            sourceCell
                .frame(width: 220, alignment: .leading)

            actionCell
                .frame(width: 56)
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
        .accessibilityHint(Text(capability.summary ?? localization.string("matrix.row.noSummary")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var capabilityCell: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                if let package {
                    store.togglePackageExpansion(package.id)
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .frame(width: 14, height: 22)
            }
            .buttonStyle(.plain)
            .help(localization.string(isCollapsed ? "matrix.package.expand" : "matrix.package.collapse"))

            PackageAvatar(name: capability.name, identifier: capability.id, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(capability.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)
                    kindBadge
                    if let package {
                        healthBadge(package.health)
                    }
                    if store.hasPendingUpdate(for: capability) {
                        Text(localization.string("matrix.row.updateBadge"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.16), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(packageSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
            }
        }
    }

    private var kindBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: capability.kind.symbol)
                .font(.system(size: 8, weight: .semibold))
            Text(localization.string(capability.kind.titleKey).uppercased())
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(Color.popSectionPurple)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Color.popSectionPurple.opacity(0.12), in: Capsule())
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
        return localization.string(
            "package.componentSummary",
            package.componentCount,
            package.installedComponentCount,
            package.requiredComponentCount
        )
    }

    private func coverageCell(for app: TargetApp) -> some View {
        let coverage = capability.appCoverage[app] ?? CapabilityAppCoverage(enabled: 0, total: 0)
        return HStack {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: app.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                Text(coverage.label)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(coverage.enabled > 0 ? app.bundleAccentColor : Color.popTertiaryLabel)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                coverage.enabled > 0 ? app.bundleAccentColor.opacity(0.10) : Color.popControlFill,
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    coverage.enabled > 0 ? app.bundleAccentColor.opacity(0.26) : Color.popControlStroke,
                    lineWidth: 0.7
                )
            )
            .help(localization.string("matrix.package.coverageHelp", app.title, coverage.enabled, coverage.total))
            Spacer(minLength: 0)
        }
    }

    private var sourceCell: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.popSecondaryLabel)
            Text(capability.sourceLabel)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.popSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
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
            if let package {
                Button {
                    store.togglePackageExpansion(package.id)
                } label: {
                    Label(
                        localization.string(isCollapsed ? "matrix.package.expand" : "matrix.package.collapse"),
                        systemImage: isCollapsed ? "chevron.down" : "chevron.up"
                    )
                }
                if let url = revealableSkillURL(for: package) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label(localization.string("matrix.row.menu.revealInFinder"), systemImage: "folder")
                    }
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

    private func revealableSkillURL(for package: CapabilityPackage) -> URL? {
        package.matchingInstalledSkills(in: store.skills)
            .first { FileManager.default.fileExists(atPath: $0.localStoreURL.path) }?
            .localStoreURL
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color.popSelectedRowFill
            } else if isHovering {
                Color.popSurfaceHover
            } else {
                Color.popSectionPurple.opacity(0.035)
            }
        }
    }
}

private struct MatrixPackageComponentRow: View {
    let component: PackageComponent
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    private var matchingSkill: Skill? {
        store.skill(for: component)
    }

    var body: some View {
        HStack(spacing: 0) {
            componentCell
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 56)
                .padding(.vertical, 6)

            appStateCell(for: .claude)
                .frame(width: 100)
            appStateCell(for: .codex)
                .frame(width: 100)

            sourceCell
                .frame(width: 220, alignment: .leading)

            Spacer().frame(width: 56)
        }
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let skill = matchingSkill {
                store.selectSkill(skill.id)
            }
        }
        .background(Color.popCardBackground.opacity(0.20))
    }

    private var componentCell: some View {
        HStack(spacing: 9) {
            Text(componentTreePrefix)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.popTertiaryLabel)
                .frame(width: 18, alignment: .leading)

            Image(systemName: component.kindSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(component.installed ? Color.popSecondaryLabel : Color.popTertiaryLabel)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(component.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)
                    Text(component.kind.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.popSecondaryLabel)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.popControlFill, in: Capsule())
                    if let requirement = requirementBadge {
                        Text(localization.string(requirement.key))
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(requirement.color)
                    }
                }
                Text(component.status)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
            }
        }
    }

    private var componentTreePrefix: String {
        "├─"
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
        let indicator = component.indicator(for: app, matching: matchingSkill)
        return HStack {
            Spacer(minLength: 0)
            Text(indicator.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(indicator.color)
                .frame(width: 26, height: 22)
                .help(localization.string(indicator.helpKey, app.title))
            Spacer(minLength: 0)
        }
    }

    private var sourceCell: some View {
        Text(component.location ?? component.id)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.popSecondaryLabel)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

private enum ComponentAppIndicator {
    case enabled
    case partial
    case off

    var symbol: String {
        switch self {
        case .enabled: "●"
        case .partial: "◐"
        case .off: "—"
        }
    }

    var color: Color {
        switch self {
        case .enabled: Color.popStatusOK
        case .partial: Color.popStatusWarning
        case .off: Color.popTertiaryLabel
        }
    }

    var helpKey: String {
        switch self {
        case .enabled: "matrix.package.component.enabledHelp"
        case .partial: "matrix.package.component.partialHelp"
        case .off: "matrix.package.component.offHelp"
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

    func indicator(for app: TargetApp, matching skill: Skill?) -> ComponentAppIndicator {
        switch kind.lowercased() {
        case "skill":
            if let skill {
                return skill.apps.isEnabled(app) ? .enabled : .off
            }
            return installed ? .enabled : (status.lowercased() == "stub" ? .partial : .off)
        case "agent":
            if installed && app == .claude { return .enabled }
            return status.lowercased() == "stub" && app == .claude ? .partial : .off
        case "cli", "mcp":
            return installed && (app == .claude || app == .codex) ? .enabled : .off
        default:
            return .off
        }
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

private extension TargetApp {
    var bundleAccentColor: Color {
        switch self {
        case .claude: .orange
        case .codex: .green
        case .gemini: .blue
        case .opencode: .indigo
        case .hermes: .purple
        }
    }
}
