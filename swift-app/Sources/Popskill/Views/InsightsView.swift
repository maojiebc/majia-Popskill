import Observation
import SwiftUI

@MainActor
@Observable
final class InsightsViewModel {
    var summary = UsageSummary()
    var isScanning = false
    var hasScannedOnce = false
    var errorMessage: String?

    private let scanner = TranscriptUsageScanner()

    func scan() async {
        guard !isScanning else {
            return
        }

        isScanning = true
        errorMessage = nil
        defer {
            isScanning = false
            hasScannedOnce = true
        }

        do {
            let scanner = self.scanner
            summary = try await Task.detached {
                try scanner.scan()
            }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct InsightsView: View {
    @Bindable var viewModel: InsightsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Usage")
                        .font(.system(.largeTitle, weight: .bold))
                    Text("\(viewModel.summary.filesScanned) files · \(viewModel.summary.sessions) sessions")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await viewModel.scan() }
                } label: {
                    if viewModel.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .help("Refresh")
                .disabled(viewModel.isScanning)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await viewModel.scan() }
                }
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        UsageMetricCard(title: "Total Tokens", value: viewModel.summary.totalTokens, accent: PopskillSectionAccent.color(for: 0))
                        UsageMetricCard(title: "Input", value: viewModel.summary.inputTokens, accent: PopskillSectionAccent.color(for: 1))
                        UsageMetricCard(title: "Output", value: viewModel.summary.outputTokens, accent: PopskillSectionAccent.color(for: 2))
                        UsageMetricCard(title: "Cache Read", value: viewModel.summary.cacheReadTokens, accent: PopskillSectionAccent.color(for: 3))
                        UsageMetricCard(title: "Cache Create", value: viewModel.summary.cacheCreationTokens, accent: PopskillSectionAccent.color(for: 4))
                        UsageMetricCard(title: "Usage Events", value: Int64(viewModel.summary.usageEvents), accent: PopskillSectionAccent.color(for: 5))
                    }

                    DetailSection(title: "Source", accent: PopskillSectionAccent.color(for: 1)) {
                        DetailField(title: "Transcript Files", value: "\(viewModel.summary.filesScanned)")
                        DetailField(title: "Sessions", value: "\(viewModel.summary.sessions)")
                    }

                    DetailSection(title: "Models", accent: PopskillSectionAccent.color(for: 2)) {
                        VStack(spacing: 8) {
                            ForEach(viewModel.summary.modelStats.prefix(8)) { stat in
                                ModelUsageRow(stat: stat, maxTokens: maxModelTokens)
                            }
                        }
                    }
                }
                .padding(28)
            }
            .overlay {
                if viewModel.isScanning && viewModel.summary.filesScanned == 0 {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .popPageBackground()
        .task {
            if !viewModel.hasScannedOnce {
                await viewModel.scan()
            }
        }
    }

    private var maxModelTokens: Int64 {
        viewModel.summary.modelStats.map(\.totalTokens).max() ?? 0
    }
}

struct UsageMetricCard: View {
    let title: String
    let value: Int64
    var accent: Color = .popSectionBlue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(formattedValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.68)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(14)
        .popCard(cornerRadius: PopskillRadius.card)
    }

    private var formattedValue: String {
        value.formatted(.number.notation(.compactName))
    }
}

struct ModelUsageRow: View {
    let stat: ModelUsageStat
    let maxTokens: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stat.model)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(stat.totalTokens.formatted(.number.notation(.compactName)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.popHeaderBackground)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.65))
                        .frame(width: proxy.size.width * widthRatio)
                }
            }
            .frame(height: 7)

            Text("\(stat.usageEvents) events · input \(stat.inputTokens.formatted(.number.notation(.compactName))) · output \(stat.outputTokens.formatted(.number.notation(.compactName)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .popCard(cornerRadius: PopskillRadius.smallCard, shadowOpacity: 0.02)
    }

    private var widthRatio: Double {
        guard maxTokens > 0 else {
            return 0
        }
        return max(0.02, min(1, Double(stat.totalTokens) / Double(maxTokens)))
    }
}
