import SwiftUI

/// Link Health — runs `skill-cli link-health` on first view and renders the
/// summary + a flat table of every row. A row is just "skillName · status
/// across N apps". Clicking a row jumps to the matrix and opens the inspector
/// so the user can read the SSOT paths in context.
@MainActor
struct LinkHealthView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var loading: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            PopskillPageHeader(
                titleKey: "sidebar.health",
                subtitle: subtitle
            ) {
                Button {
                    Task { await reload() }
                } label: {
                    Label(localization.string("health.refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(loading)
            }

            if loading && store.linkHealth == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report = store.linkHealth {
                content(report: report)
            } else {
                emptyState
            }
        }
        .popPageBackground()
        .task {
            if store.linkHealth == nil {
                await reload()
            }
        }
    }

    private var subtitle: String {
        if let summary = store.linkHealth?.summary {
            return localization.string("health.subtitle", summary.ok, summary.broken, summary.inactive)
        }
        return localization.string("health.subtitleNoScan")
    }

    private func content(report: LinkHealthReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryStrip(report.summary)
                    .padding(.horizontal, 28)
                LazyVStack(spacing: 6) {
                    ForEach(report.rows, id: \.skillId) { row in
                        rowView(row)
                    }
                }
                .padding(.horizontal, 28)
                Color.clear.frame(height: 24)
            }
        }
    }

    private func summaryStrip(_ summary: LinkHealthSummary) -> some View {
        HStack(spacing: 10) {
            summaryChip(symbol: "checkmark.circle.fill", color: .green, label: localization.string("health.summary.ok"), value: summary.ok)
            summaryChip(symbol: "exclamationmark.triangle.fill", color: .red, label: localization.string("health.summary.broken"), value: summary.broken)
            summaryChip(symbol: "circle.dashed", color: Color.popTertiaryLabel, label: localization.string("health.summary.inactive"), value: summary.inactive)
            Spacer()
        }
    }

    private func summaryChip(symbol: String, color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.popLabel)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.popSecondaryLabel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func rowView(_ row: LinkHealthRow) -> some View {
        Button {
            store.currentSelection = .matrix
            store.selectSkill(row.skillId)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: rowSymbol(for: row))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(rowTint(for: row))
                    .frame(width: 28, height: 28)
                    .background(rowTint(for: row).opacity(0.14), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.skillName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.popLabel)
                    if let path = row.deployment?.ssotPath, !path.isEmpty {
                        Text((path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.popSecondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(localization.string("health.row.noPath"))
                            .font(.caption)
                            .foregroundStyle(Color.popTertiaryLabel)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(orderedLinks(row.deployment?.appLinks ?? [:]), id: \.key) { key, link in
                        appBadge(key: key, status: link.status)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.popTertiaryLabel)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .popCard(cornerRadius: PopskillRadius.smallCard, shadowOpacity: 0.02)
        }
        .buttonStyle(.plain)
    }

    private func rowSymbol(for row: LinkHealthRow) -> String {
        let statuses = (row.deployment?.appLinks ?? [:]).values.map { $0.status.lowercased() }
        if statuses.contains("broken") { return "exclamationmark.triangle.fill" }
        if statuses.contains("ok") { return "link" }
        return "circle.dashed"
    }

    private func rowTint(for row: LinkHealthRow) -> Color {
        let statuses = (row.deployment?.appLinks ?? [:]).values.map { $0.status.lowercased() }
        if statuses.contains("broken") { return Color.popStatusError }
        if statuses.contains("ok") { return Color.popStatusOK }
        return Color.popTertiaryLabel
    }

    private func orderedLinks(_ links: [String: AppLinkStatus]) -> [(key: String, value: AppLinkStatus)] {
        let priority: [String: Int] = ["claude": 0, "codex": 1]
        return links.sorted { lhs, rhs in
            (priority[lhs.key] ?? 99) < (priority[rhs.key] ?? 99)
        }
    }

    private func appBadge(key: String, status: String) -> some View {
        let (tint, label): (Color, String) = {
            switch status.lowercased() {
            case "ok":       return (.green, "✓")
            case "broken":   return (.red, "!")
            case "inactive": return (Color.popTertiaryLabel, "·")
            default:         return (Color.popSecondaryLabel, "?")
            }
        }()
        return HStack(spacing: 2) {
            Text(key.prefix(1).uppercased())
                .font(.system(size: 9.5, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(tint.opacity(0.14), in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            LocalizedText("health.empty.title")
                .font(.title3.weight(.semibold))
            Button {
                Task { await reload() }
            } label: {
                Label(localization.string("health.empty.runScan"), systemImage: "play.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    @MainActor
    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            store.linkHealth = try await store.client.linkHealth()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
