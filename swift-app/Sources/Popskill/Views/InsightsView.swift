import SwiftUI

/// Insights — installed-capability snapshot + transcript token usage. v0.4
/// wires the `TranscriptUsageScanner` back in, surfacing token totals (input
/// / output / cache read / cache create) and the top 10 capabilities by
/// token consumption inferred from `~/.claude/projects/**/*.jsonl`. The scan
/// runs off the main thread; the section degrades gracefully when there's no
/// `~/.claude/projects/` directory yet.
struct InsightsView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var lastScanAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PopskillPageHeader(
                    titleKey: "sidebar.insights",
                    subtitle: localization.string("insights.subtitle")
                ) {
                    Button {
                        Task { await runScan() }
                    } label: {
                        Label(
                            localization.string("insights.refresh"),
                            systemImage: store.usageScanInFlight ? "arrow.clockwise" : "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.usageScanInFlight)
                }

                heroGrid

                if let summary = store.usageSummary {
                    tokenSection(summary: summary).padding(.horizontal, 28)
                    topSkillsSection(summary: summary).padding(.horizontal, 28)
                } else if store.usageScanInFlight {
                    scanningCard.padding(.horizontal, 28)
                } else if let error = store.usageScanError {
                    errorCard(error).padding(.horizontal, 28)
                } else {
                    emptyUsageCard.padding(.horizontal, 28)
                }

                breakdownCard.padding(.horizontal, 28)

                Color.clear.frame(height: 32)
            }
        }
        .popPageBackground()
        .task {
            if store.usageSummary == nil && !store.usageScanInFlight && store.usageScanError == nil {
                await runScan()
            }
        }
    }

    @MainActor
    private func runScan() async {
        await store.refreshUsageScan()
        if store.usageSummary != nil { lastScanAt = Date() }
    }

    // MARK: Hero grid (unchanged from v0.3)

    private var heroGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            metricCard(
                titleKey: "insights.metric.totalSkills",
                value: store.skills.count,
                symbol: "square.grid.3x3.fill",
                tint: .accentColor
            )
            metricCard(
                titleKey: "insights.metric.enabledToggles",
                value: store.enabledSkillCount,
                symbol: "bolt.fill",
                tint: .orange
            )
            metricCard(
                titleKey: "insights.metric.pendingUpdates",
                value: store.pendingUpdateCount,
                symbol: "arrow.down.circle.fill",
                tint: store.pendingUpdateCount > 0 ? .blue : Color.popTertiaryLabel
            )
            metricCard(
                titleKey: "insights.metric.brokenLinks",
                value: store.brokenLinkCount,
                symbol: "exclamationmark.triangle.fill",
                tint: store.brokenLinkCount > 0 ? .red : .green
            )
        }
        .padding(.horizontal, 28)
    }

    private func metricCard(titleKey: String, value: Int, symbol: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.popLabel)
                LocalizedText(titleKey)
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    // MARK: Tokens

    private func tokenSection(summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: "insights.tokens.title", accent: .accentColor)
                Spacer()
                Text(localization.string("insights.tokens.scanFooter", summary.sessions, summary.filesScanned))
                    .font(.caption2)
                    .foregroundStyle(Color.popTertiaryLabel)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 10
            ) {
                tokenCard(
                    titleKey: "insights.tokens.input",
                    value: summary.inputTokens,
                    tint: .blue
                )
                tokenCard(
                    titleKey: "insights.tokens.output",
                    value: summary.outputTokens,
                    tint: .green
                )
                tokenCard(
                    titleKey: "insights.tokens.cacheCreation",
                    value: summary.cacheCreationTokens,
                    tint: .orange
                )
                tokenCard(
                    titleKey: "insights.tokens.cacheRead",
                    value: summary.cacheReadTokens,
                    tint: .purple
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "sum")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                Text(localization.string("insights.tokens.total"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                Spacer()
                Text(Self.formatTokens(summary.totalTokens))
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.popLabel)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    private func tokenCard(titleKey: String, value: Int64, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                LocalizedText(titleKey)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            Text(Self.formatTokens(value))
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.popLabel)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Top skills

    private func topSkillsSection(summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "insights.topSkills.title", accent: .accentColor)
            if summary.skillStats.isEmpty {
                Text(localization.string("insights.topSkills.empty"))
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
            } else {
                let max = summary.skillStats.first?.totalTokens ?? 1
                ForEach(summary.skillStats.prefix(10)) { stat in
                    topSkillRow(stat: stat, normalizedMax: max)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    private func topSkillRow(stat: SkillUsageStat, normalizedMax: Int64) -> some View {
        let label = displayLabel(for: stat)
        let fraction = normalizedMax > 0 ? Double(stat.totalTokens) / Double(normalizedMax) : 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.popLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(Self.formatTokens(stat.totalTokens))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.10))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: max(2, proxy.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
    }

    /// Map raw `skillID` from the scanner back to a readable name. The scanner
    /// observed-attribution strings can be either a skill id, a skill name,
    /// or a plugin-prefixed identifier — `matchesAttributionSkill` already
    /// handles the normalization so we leverage it here for display lookup.
    private func displayLabel(for stat: SkillUsageStat) -> String {
        if let match = store.skills.first(where: { $0.matchesAttributionSkill(stat.skillID) }) {
            return match.name
        }
        return stat.skillID
    }

    // MARK: Existing breakdown card (claude/codex coverage + top sources)

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "insights.breakdown.title")

            breakdownRow(label: localization.string("insights.breakdown.claude"), enabled: claudeOn, total: store.skills.count, tint: .orange)
            breakdownRow(label: localization.string("insights.breakdown.codex"), enabled: codexOn, total: store.skills.count, tint: .green)

            Divider().padding(.vertical, 2)

            Text(localization.string("insights.breakdown.topSources"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.popSecondaryLabel)
            ForEach(topSources, id: \.label) { source in
                HStack(spacing: 6) {
                    Text(source.label)
                        .font(.caption)
                        .foregroundStyle(Color.popLabel)
                    Spacer()
                    Text("\(source.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.popSecondaryLabel)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    private func breakdownRow(label: String, enabled: Int, total: Int, tint: Color) -> some View {
        let fraction = total > 0 ? Double(enabled) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.popLabel)
                Spacer()
                Text("\(enabled) / \(total)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint.opacity(0.10))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint)
                        .frame(width: max(2, proxy.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
    }

    private var claudeOn: Int { store.skills.filter { $0.apps.claude }.count }
    private var codexOn: Int { store.skills.filter { $0.apps.codex }.count }

    private struct SourceSummary {
        let label: String
        let count: Int
    }

    private var topSources: [SourceSummary] {
        let buckets = Dictionary(grouping: store.skills) { skill -> String in
            skill.sourceLabel
        }
        return buckets
            .map { SourceSummary(label: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    // MARK: States

    private var scanningCard: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                LocalizedText("insights.scan.scanning")
                    .font(.callout.weight(.semibold))
                LocalizedText("insights.scan.scanningHint")
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    private func errorCard(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.popStatusWarning)
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText("insights.scan.errorTitle")
                    .font(.callout.weight(.semibold))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    private var emptyUsageCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.popTertiaryLabel)
            LocalizedText("insights.scan.emptyTitle")
                .font(.callout.weight(.semibold))
            LocalizedText("insights.scan.emptyBody")
                .font(.caption)
                .foregroundStyle(Color.popSecondaryLabel)
                .multilineTextAlignment(.center)
            Button {
                Task { await runScan() }
            } label: {
                Label(localization.string("insights.refresh"), systemImage: "play.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    // MARK: Format

    private static func formatTokens(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        if value < 1_000 {
            return formatter.string(from: NSNumber(value: value)) ?? "0"
        }
        if value < 1_000_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        if value < 1_000_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        return String(format: "%.2fB", Double(value) / 1_000_000_000.0)
    }
}
