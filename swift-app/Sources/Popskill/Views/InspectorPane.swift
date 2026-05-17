import SwiftUI

/// Right-pane inspector for the matrix. Renders a single
/// `MatrixCapability` — skill / agent / cli / mcp / config. Skill rows show
/// the full set of sections (summary / triggers / apps / deployment /
/// metadata); other kinds gracefully omit the irrelevant pieces (an agent
/// has no SSOT symlink to chart, a CLI has no per-app toggle).
struct InspectorPane: View {
    @Bindable var store: PopskillStore
    let capability: MatrixCapability
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !primaryDescription.isEmpty {
                    summarySection
                }
                if let scenarios = capability.triggerScenarios, !scenarios.isEmpty {
                    triggerSection(scenarios: scenarios)
                }
                appsSection
                if capability.kind == .skill {
                    deploymentSection
                }
                metadataSection
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .background(Color.popCardBackground.opacity(0.72))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            InitialAvatarView(name: capability.name, identifier: capability.id)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(capability.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(2)
                    if capability.kind != .skill {
                        kindChip
                    }
                }
                Text(capability.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.closeInspector()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .frame(width: 22, height: 22)
                    .background(Color.popSubtleFill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(localization.string("matrix.inspector.close"))
        }
    }

    private var kindChip: some View {
        HStack(spacing: 3) {
            Image(systemName: capability.kind.symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(localization.string(capability.kind.titleKey).uppercased())
                .font(.system(size: 9.5, weight: .bold))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    // MARK: Sections

    private var primaryDescription: String {
        capability.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading(title: "matrix.inspector.section.summary")
            Text(primaryDescription)
                .font(.callout)
                .foregroundStyle(Color.popLabel)
                .textSelection(.enabled)
        }
    }

    private func triggerSection(scenarios: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading(title: "matrix.inspector.section.triggers", accent: .accentColor)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(scenarios, id: \.self) { scenario in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.callout)
                            .foregroundStyle(Color.popTertiaryLabel)
                        Text(scenario)
                            .font(.callout)
                            .foregroundStyle(Color.popLabel)
                    }
                }
            }
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.apps")
            HStack(spacing: 12) {
                appToggleButton(.claude)
                appToggleButton(.codex)
                Spacer()
            }
            if !capability.isToggleable {
                Text(localization.string("matrix.inspector.readOnly"))
                    .font(.caption2)
                    .foregroundStyle(Color.popTertiaryLabel)
            }
        }
    }

    private func appToggleButton(_ app: TargetApp) -> some View {
        let isOn = capability.apps.isEnabled(app)
        let pending = store.pendingToggles.contains(toggleKey(app))
        return Button {
            guard capability.isToggleable else { return }
            Task { await toggle(app: app, enabled: !isOn) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: app.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                Text(app.title)
                    .font(.callout.weight(.medium))
                if pending {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.popSecondaryLabel)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isOn ? Color.accentColor.opacity(0.14) : Color.popSubtleFill,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(pending || !capability.isToggleable)
    }

    private var deploymentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "matrix.inspector.section.deployment")
            if let deployment = capability.deployment {
                VStack(alignment: .leading, spacing: 6) {
                    deploymentRow(
                        title: localization.string("matrix.inspector.deployment.ssot"),
                        path: deployment.ssotPath,
                        status: nil
                    )
                    ForEach(sortedAppLinks(deployment.appLinks), id: \.key) { key, link in
                        deploymentRow(
                            title: appLabel(for: key),
                            path: link.path,
                            status: link.status
                        )
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                    Text(localization.string("matrix.inspector.deployment.strategy", deployment.strategy))
                        .font(.caption2)
                }
                .foregroundStyle(Color.popTertiaryLabel)
            } else {
                Text(localization.string("matrix.inspector.deployment.empty"))
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
            }
        }
    }

    private func sortedAppLinks(_ links: [String: AppLinkStatus]) -> [(key: String, value: AppLinkStatus)] {
        let priority: [String: Int] = ["claude": 0, "codex": 1]
        return links.sorted { lhs, rhs in
            let l = priority[lhs.key] ?? 99
            let r = priority[rhs.key] ?? 99
            if l != r { return l < r }
            return lhs.key < rhs.key
        }.map { (key: $0.key, value: $0.value) }
    }

    private func appLabel(for key: String) -> String {
        switch key.lowercased() {
        case "claude": return "Claude Code"
        case "codex":  return "Codex"
        case "gemini": return "Gemini"
        case "opencode": return "OpenCode"
        case "hermes": return "Hermes"
        default: return key.capitalized
        }
    }

    private func deploymentRow(title: String, path: String, status: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.popLabel)
                Text(path.isEmpty ? "—" : (path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if let status {
                linkStatusBadge(status)
            }
        }
        .padding(8)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 6))
    }

    private func linkStatusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status.lowercased() {
            case "ok":       return (localization.string("matrix.inspector.linkStatus.ok"), .green)
            case "broken":   return (localization.string("matrix.inspector.linkStatus.broken"), .red)
            case "inactive": return (localization.string("matrix.inspector.linkStatus.inactive"), Color.popTertiaryLabel)
            case "na":       return (localization.string("matrix.inspector.linkStatus.na"), Color.popTertiaryLabel)
            default:         return (status, Color.popSecondaryLabel)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.meta")
            VStack(alignment: .leading, spacing: 6) {
                metaRow(label: localization.string("matrix.inspector.meta.directory"), value: capability.directory)
                if let source = capability.sourceType, !source.isEmpty {
                    metaRow(label: localization.string("matrix.inspector.meta.sourceType"), value: source)
                }
                if let installedAt = capability.installedAt, installedAt > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.installedAt"), value: Self.formatTimestamp(installedAt))
                }
                if let updatedAt = capability.updatedAt, updatedAt > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.updatedAt"), value: Self.formatTimestamp(updatedAt))
                }
                if let size = capability.sizeBytes, size > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.size"), value: Self.formatBytes(size))
                }
            }
            if let url = capability.sourceURL {
                Link(destination: url) {
                    Label(localization.string("matrix.inspector.meta.openSource"), systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.popSecondaryLabel)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(Color.popLabel)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private static func formatTimestamp(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: Toggle helpers

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
}
