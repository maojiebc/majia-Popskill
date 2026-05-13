import SwiftUI

struct RecentActivityView: View {
    @Bindable var viewModel: InsightsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recently Used")
                        .font(.system(.largeTitle, weight: .bold))
                    Text("\(viewModel.summary.recentSessions.count) sessions")
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

            TranscriptBoundaryNote()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            List(viewModel.summary.recentSessions.prefix(80)) { session in
                RecentSessionRow(session: session, maxTokens: maxSessionTokens)
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isScanning && viewModel.summary.recentSessions.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                } else if viewModel.summary.recentSessions.isEmpty {
                    ContentUnavailableView("No Recent Sessions", systemImage: "clock")
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

    private var maxSessionTokens: Int64 {
        viewModel.summary.recentSessions.map(\.totalTokens).max() ?? 0
    }
}

struct RecentSessionRow: View {
    let session: SessionUsageStat
    let maxTokens: Int64

    var body: some View {
        HStack(spacing: 14) {
            PackageAvatar(name: session.projectName, identifier: session.sessionID)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(sessionProjectLabel)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    StatusPill(title: lastActivityText, color: .popStatusNeutral)
                }

                HStack(spacing: 10) {
                    Label("\(session.usageEvents) events", systemImage: "message")
                    Label(session.totalTokens.formatted(.number.notation(.compactName)), systemImage: "sum")
                    if let startedAt = session.startedAt {
                        Label(startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

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
            }

            Spacer(minLength: 20)

            Text(String(session.sessionID.prefix(8)))
                .font(.caption.monospaced())
                .foregroundStyle(Color.popTertiaryLabel)
        }
        .frame(minHeight: 72)
    }

    private var sessionProjectLabel: String {
        session.projectName.isEmpty ? "Unknown Project" : session.projectName
    }

    private var lastActivityText: String {
        guard let lastActivityAt = session.lastActivityAt else {
            return "No timestamp"
        }
        return lastActivityAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var widthRatio: Double {
        guard maxTokens > 0 else {
            return 0
        }
        return max(0.02, min(1, Double(session.totalTokens) / Double(maxTokens)))
    }
}
