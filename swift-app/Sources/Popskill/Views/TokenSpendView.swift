import SwiftUI

struct TokenSpendView: View {
    @Bindable var viewModel: InsightsViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

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
                        UsageMetricCard(title: "Total", value: viewModel.summary.totalTokens, accent: PopskillSectionAccent.color(for: 0))
                        UsageMetricCard(title: "Input", value: viewModel.summary.inputTokens, accent: PopskillSectionAccent.color(for: 1))
                        UsageMetricCard(title: "Output", value: viewModel.summary.outputTokens, accent: PopskillSectionAccent.color(for: 2))
                        UsageMetricCard(title: "Cache Read", value: viewModel.summary.cacheReadTokens, accent: PopskillSectionAccent.color(for: 3))
                        UsageMetricCard(title: "Cache Create", value: viewModel.summary.cacheCreationTokens, accent: PopskillSectionAccent.color(for: 4))
                    }

                    DetailSection(title: "By Model", accent: PopskillSectionAccent.color(for: 2)) {
                        VStack(spacing: 8) {
                            ForEach(viewModel.summary.modelStats) { stat in
                                ModelUsageRow(stat: stat, maxTokens: maxModelTokens)
                            }
                        }
                    }
                }
                .padding(28)
            }
            .overlay {
                if viewModel.isScanning && viewModel.summary.modelStats.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                } else if viewModel.summary.modelStats.isEmpty {
                    ContentUnavailableView("No Token Data", systemImage: "creditcard")
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

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Token Spend")
                    .font(.system(.largeTitle, weight: .bold))
                Text("\(viewModel.summary.modelStats.count) models · \(viewModel.summary.totalTokens.formatted(.number.notation(.compactName))) tokens")
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
    }

    private var maxModelTokens: Int64 {
        viewModel.summary.modelStats.map(\.totalTokens).max() ?? 0
    }
}
