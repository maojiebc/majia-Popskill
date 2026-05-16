import SwiftUI

/// Insights — at-a-glance view counting what the user has + what needs
/// attention. v0.3 ships 4 hero metric cards drawn from `PopskillStore`; v0.4
/// will bolt the transcript-usage scanner back on with weekly/monthly bars.
struct InsightsView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PopskillPageHeader(
                    titleKey: "sidebar.insights",
                    subtitle: localization.string("insights.subtitle")
                )

                heroGrid

                breakdownCard
                    .padding(.horizontal, 28)

                Color.clear.frame(height: 32)
            }
        }
        .popPageBackground()
    }

    // MARK: Hero grid

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

    // MARK: Breakdown

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "insights.breakdown.title")

            breakdownRow(label: localization.string("insights.breakdown.claude"), enabled: claudeOn, total: store.skills.count, tint: .orange)
            breakdownRow(label: localization.string("insights.breakdown.codex"), enabled: codexOn, total: store.skills.count, tint: .green)

            Divider().padding(.vertical, 2)

            // Top sources by skill count — v0.3 doesn't have usage but knowing
            // "where my skills live" is still informative.
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

    private var claudeOn: Int {
        store.skills.filter { $0.apps.claude }.count
    }

    private var codexOn: Int {
        store.skills.filter { $0.apps.codex }.count
    }

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
}
