import AppKit
import SwiftUI

/// Full-page capability detail (replaces the old trailing inspector panel to
/// match the prototype). Crumb bar · hero · actions · tabs, then — for bundles —
/// coverage cards + a component list, or — for standalone — a README block +
/// 30-day usage, with a right rail of source / SSOT / version / this-machine.
@MainActor
struct InspectorView: View {
    @Bindable var store: PopskillStore
    let capability: MatrixCapability
    @Environment(\.popskillLocalization) private var localization

    private var isBundle: Bool { capability.kind == .bundle }
    private var package: CapabilityPackage? { capability.package }
    private var skill: Skill? { capability.underlyingSkillID.flatMap { id in store.skills.first { $0.id == id } } }

    private var usageIndex: MatrixUsageIndex {
        MatrixUsageIndex(summary: store.usageSummary, skills: store.skills, packages: store.compositePackages)
    }

    var body: some View {
        VStack(spacing: 0) {
            crumbBar
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        actions
                        tabs
                        if isBundle { coverageGrid; componentList } else { readmeBlock; usageBlock }
                        Color.clear.frame(height: 28)
                    }
                    .padding(.horizontal, 32).padding(.top, 24)
                }
                .frame(maxWidth: .infinity)
                rail
            }
        }
        .popPageBackground()
    }

    // MARK: Crumb

    private var crumbBar: some View {
        HStack(spacing: 8) {
            Button { store.inspectorOpen = false } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left").font(.system(size: 11, weight: .semibold))
                    LocalizedText("inspector.back")
                }
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.popAccent)
            }.buttonStyle(.plain)
            Text(verbatim: "/").foregroundStyle(Color.popLinkOff)
            LocalizedText(isBundle ? "matrix.type.bundle" : capability.kind.titleKey).font(.system(size: 12.5)).foregroundStyle(Color.popSecondaryLabel)
            Text(verbatim: "/").foregroundStyle(Color.popLinkOff)
            Text(capability.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.popLabel)
            Spacer()
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
        .background(Color.popMainBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.popSeparator).frame(height: 1) }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(String(capability.name.prefix(1)).uppercased())
                .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(isBundle ? Color.popLabel : Color.popAccent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(capability.name).font(.system(size: 26, weight: .bold)).tracking(-0.4).foregroundStyle(Color.popLabel)
                    if let v = versionString { Text(v).font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.popSecondaryLabel) }
                    LedgerTypeTag(kind: capability.kind)
                }
                if let summary = capability.summary, !summary.isEmpty {
                    Text(summary).font(.system(size: 14)).foregroundStyle(Color(hex: 0x444444)).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    metaItem("↗ \(capability.sourceLabel)")
                    if let owner = capability.repoOwner, !owner.isEmpty { metaItem("● \(owner)") }
                    if let snap = usageSnapshot, snap.hasUsage {
                        metaItem(localization.string("inspector.callsPerMonth", UsageDisplayFormatter.compactCount(snap.usageEvents)))
                        metaItem("\(UsageDisplayFormatter.compactTokens(snap.totalTokens)) tokens")
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func metaItem(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Color.popSecondaryLabel).lineLimit(1)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            if isBundle {
                primaryAction("inspector.activateClaude")
                secondaryAction("inspector.activateCodex")
                secondaryAction("inspector.checkUpdate")
                Spacer()
                dangerAction("inspector.disableBundle")
            } else {
                LedgerStatusGlyph(state: capability.apps.claude ? .on : .off,
                                  help: localization.string("matrix.row.toggleHelp", "Claude"),
                                  onToggle: capability.isToggleable ? { Task { await toggle(.claude) } } : nil)
                LedgerStatusGlyph(state: capability.apps.codex ? .on : .off,
                                  help: localization.string("matrix.row.toggleHelp", "Codex"),
                                  onToggle: capability.isToggleable ? { Task { await toggle(.codex) } } : nil)
                secondaryAction("inspector.editPrompt")
                secondaryAction("inspector.checkUpdate")
                Spacer()
                dangerAction("inspector.makeStub")
            }
        }
        .padding(.top, 16).padding(.bottom, 18)
    }

    private func primaryAction(_ key: String) -> some View {
        actionLabel(key).foregroundStyle(.white).background(Color.popAccent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    private func secondaryAction(_ key: String) -> some View {
        actionLabel(key).foregroundStyle(Color(hex: 0x222222))
            .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.popControlStroke, lineWidth: 1))
    }
    private func dangerAction(_ key: String) -> some View {
        actionLabel(key).foregroundStyle(Color.popLinkBroken)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0xEBC4C4), lineWidth: 1))
    }
    private func actionLabel(_ key: String) -> some View {
        LocalizedText(key).font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 7)
    }

    // MARK: Tabs

    private var tabs: some View {
        let labels: [String] = isBundle
            ? ["inspector.tab.components", "inspector.tab.readme", "inspector.tab.usage", "inspector.tab.versions", "inspector.tab.sync"]
            : ["inspector.tab.readme", "inspector.tab.usage", "inspector.tab.versions", "inspector.tab.paths"]
        return HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, key in
                LocalizedText(key)
                    .font(.system(size: 12.5, weight: i == 0 ? .semibold : .medium))
                    .foregroundStyle(i == 0 ? Color.popLabel : Color.popSecondaryLabel)
                    .padding(.horizontal, 14).padding(.vertical, 8).padding(.bottom, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(i == 0 ? Color.popAccent : Color.clear).frame(height: 2) }
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.popSeparator).frame(height: 1) }
        .padding(.bottom, 18)
    }

    // MARK: Bundle — coverage + components

    private var coverageGrid: some View {
        HStack(spacing: 12) {
            coverageCard("Claude Code", capability.appCoverage[.claude])
            coverageCard("Codex", capability.appCoverage[.codex])
        }
        .padding(.bottom, 22)
    }

    private func coverageCard(_ label: String, _ coverage: CapabilityAppCoverage?) -> some View {
        let cov = coverage ?? CapabilityAppCoverage(enabled: 0, total: 0)
        let pct = cov.total > 0 ? Int((Double(cov.enabled) / Double(cov.total)) * 100) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localization.string("inspector.coverage", label)).font(.system(size: 11, weight: .semibold)).tracking(0.4).textCase(.uppercase).foregroundStyle(Color.popSecondaryLabel)
                Spacer()
                Text("\(cov.enabled)/\(cov.total)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.popSecondaryLabel)
            }
            Text("\(pct)%").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.popLabel)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(Color.popCoverageOn).frame(width: cov.total > 0 ? geo.size.width * CGFloat(cov.enabled) / CGFloat(cov.total) : 0)
                    Rectangle().fill(Color.popCoverageOff)
                }
            }
            .frame(height: 6).clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.popSeparator, lineWidth: 1))
    }

    private var componentList: some View {
        let components = package?.components.all ?? []
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel("inspector.componentList")
            VStack(spacing: 0) {
                ForEach(Array(components.enumerated()), id: \.offset) { i, c in
                    componentRow(c, last: i == components.count - 1)
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.popSeparator, lineWidth: 1))
        }
    }

    private func componentRow(_ c: PackageComponent, last: Bool) -> some View {
        let matching = store.skill(for: c)
        return HStack(spacing: 12) {
            Text(String(c.kind.prefix(1)).uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(componentColor(c.kind), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.popLabel)
                Text(c.status).font(.system(size: 11)).foregroundStyle(Color.popSecondaryLabel).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(c.kind.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.4).foregroundStyle(Color.popSecondaryLabel).frame(width: 56, alignment: .leading)
            LedgerStatusGlyph(state: linkState(c, app: .claude, matching: matching)).frame(width: 56)
            LedgerStatusGlyph(state: linkState(c, app: .codex, matching: matching)).frame(width: 56)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.popRowDivider).frame(height: 1) } }
    }

    // MARK: Standalone — README + usage

    private var readmeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(capability.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.popLabel)
            if let summary = capability.summary, !summary.isEmpty {
                Text(summary).font(.system(size: 13)).foregroundStyle(Color(hex: 0x3A3A3A)).fixedSize(horizontal: false, vertical: true)
            }
            if let triggers = capability.triggerScenarios, !triggers.isEmpty {
                Text("\(localization.string("inspector.triggers"))：\(triggers.prefix(2).joined(separator: " · "))")
                    .font(.system(size: 12)).foregroundStyle(Color.popSecondaryLabel)
            }
            if let v = versionString {
                Text(verbatim: "name: \(capability.name)\nversion: \(v)\nauthor: \(capability.repoOwner ?? "—")")
                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color(hex: 0xE8D8B0))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x1C1610), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.popSeparator, lineWidth: 1))
        .padding(.bottom, 18)
    }

    private var usageBlock: some View {
        let snap = usageSnapshot
        let bars: [Int] = snap?.dailyStats.map { $0.usageEvents } ?? []
        let peak = max(bars.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                LocalizedText("inspector.usage30d").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.popLabel)
                Spacer()
                if let snap, snap.hasUsage {
                    Text(localization.string("inspector.usagePeak", peak, UsageDisplayFormatter.compactCount(snap.usageEvents)))
                        .font(.system(size: 11.5)).foregroundStyle(Color.popSecondaryLabel)
                }
            }
            if bars.isEmpty {
                LocalizedText("inspector.noUsage").font(.system(size: 12)).foregroundStyle(Color.popTertiaryLabel).frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, v in
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.popAccent.opacity(0.85))
                            .frame(height: max(2, CGFloat(v) / CGFloat(peak) * 56))
                    }
                }
                .frame(height: 56)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.popSeparator, lineWidth: 1))
    }

    // MARK: Rail

    private var rail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                railHeader("inspector.rail.source")
                railRow("inspector.rail.repo", capability.sourceLabel, mono: true)
                railRow("inspector.rail.ssot", ssotPath, mono: true)

                railHeader("inspector.rail.links")
                if capability.apps.claude { linkPathRow("~/.claude/skills/\(capability.name)") }
                if capability.apps.codex { linkPathRow("~/.codex/skills/\(capability.name)") }
                if !capability.apps.claude && !capability.apps.codex {
                    Text(localization.string("inspector.rail.notLinked")).font(.system(size: 11)).foregroundStyle(Color.popTertiaryLabel).padding(.vertical, 6)
                }

                railHeader("inspector.rail.version")
                railRow("inspector.rail.current", versionString ?? "—", mono: true)

                railHeader("inspector.rail.thisMachine")
                if let snap = usageSnapshot, snap.hasUsage {
                    railRow("inspector.rail.tokens", UsageDisplayFormatter.compactTokens(snap.totalTokens), mono: true)
                    railRow("inspector.rail.calls", UsageDisplayFormatter.compactCount(snap.usageEvents), mono: true)
                } else {
                    railRow("inspector.rail.tokens", "—", mono: true)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 26)
        }
        .frame(width: 320)
        .background(Color.popSurface)
        .overlay(alignment: .leading) { Rectangle().fill(Color.popSeparator).frame(width: 1) }
    }

    private func railHeader(_ key: String) -> some View {
        LocalizedText(key).font(.system(size: 10.5, weight: .bold)).tracking(0.8).textCase(.uppercase).foregroundStyle(Color.popTertiaryLabel)
            .padding(.top, 14).padding(.bottom, 8)
    }
    private func railRow(_ key: String, _ value: String, mono: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            LocalizedText(key).font(.system(size: 12.5)).foregroundStyle(Color.popSecondaryLabel)
            Spacer(minLength: 10)
            Text(value).font(.system(size: mono ? 11.5 : 12.5, design: mono ? .monospaced : .default)).foregroundStyle(Color(hex: 0x222222))
                .multilineTextAlignment(.trailing).lineLimit(2).truncationMode(.middle).frame(maxWidth: 180, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xECE9E0)).frame(height: 1) }
    }
    private func linkPathRow(_ path: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.popAccent).frame(width: 7, height: 7)
            Text(path).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color(hex: 0x222222)).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.popSeparator, lineWidth: 1))
        .padding(.bottom, 6)
    }

    private func sectionLabel(_ key: String) -> some View {
        LocalizedText(key).font(.system(size: 10.5, weight: .bold)).tracking(0.8).textCase(.uppercase).foregroundStyle(Color.popTertiaryLabel).padding(.bottom, 10)
    }

    // MARK: Data

    private var usageSnapshot: SkillUsageSnapshot? {
        usageIndex.skillSnapshot(for: capability.underlyingSkillID)
    }
    private var versionString: String? {
        if isBundle { return package?.lifecycle?.updatedAt != nil ? nil : nil }
        return MatrixVersionFormatter.value(manifestVersion: skill?.manifest?.semanticVersion, contentHash: skill?.contentHash, updatedAt: capability.updatedAt)
    }
    private var ssotPath: String {
        if let url = skill?.localStoreURL { return (url.path as NSString).abbreviatingWithTildeInPath }
        return "~/.cc-switch/skills/\(capability.name)/"
    }
    private func componentColor(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "skill": return Color(hex: 0xC78A1D)
        case "agent": return Color(hex: 0x3A6DBA)
        case "mcp": return Color(hex: 0x7A4EC0)
        case "cli": return Color(hex: 0x2A8A5A)
        default: return Color(hex: 0x888888)
        }
    }
    private func linkState(_ c: PackageComponent, app: TargetApp, matching: Skill?) -> LedgerLinkState {
        if let s = matching { return s.apps.isEnabled(app) ? (s.hasBrokenLink ? .broken : .on) : .off }
        return c.installed ? .on : (c.status.lowercased() == "stub" ? .stub : .off)
    }

    @MainActor private func toggle(_ app: TargetApp) async {
        guard let skillID = capability.underlyingSkillID else { return }
        let enabled = !capability.apps.isEnabled(app)
        do {
            try await store.client.toggle(skillID: skillID, app: app, enabled: enabled)
            if let idx = store.skills.firstIndex(where: { $0.id == skillID }) { store.skills[idx].apps.setEnabled(enabled, for: app) }
        } catch { store.errorMessage = error.localizedDescription }
    }
}
