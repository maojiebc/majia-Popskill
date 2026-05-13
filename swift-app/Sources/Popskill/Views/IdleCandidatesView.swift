import SwiftUI

struct IdleCandidatesView: View {
    @Bindable var viewModel: LibraryViewModel
    @Bindable var insightsViewModel: InsightsViewModel
    @State private var isConfirmingBulkStub = false
    private let idleThresholdDays = 60

    private var idleSkills: [Skill] {
        let referenceDate = Date()
        return viewModel.skills.filter {
            $0.isIdleCandidate(referenceDate: referenceDate, thresholdDays: idleThresholdDays)
                && !hasRecentAttributedUse($0, referenceDate: referenceDate)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Idle Candidates")
                        .font(.system(.largeTitle, weight: .bold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isConfirmingBulkStub = true
                } label: {
                    if viewModel.isBulkStubbing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Stub All", systemImage: "tray.and.arrow.down")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(idleSkills.isEmpty || viewModel.isBulkStubbing)
                .help("Make All Idle Skills Stub")

                Button {
                    Task {
                        await viewModel.load()
                        await insightsViewModel.scan()
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .help("Refresh")
                .disabled(isRefreshing)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task {
                        await viewModel.load()
                        await insightsViewModel.scan()
                    }
                }
                Divider()
            }

            List(idleSkills) { skill in
                IdleCandidateRow(
                    skill: skill,
                    isStubbing: viewModel.isStubbing(skillID: skill.id) || viewModel.isBulkStubbing
                ) {
                    Task {
                        _ = await viewModel.stub(skill)
                    }
                }
                .listRowSeparator(.visible)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isLoading && viewModel.skills.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                } else if insightsViewModel.isScanning && !insightsViewModel.hasScannedOnce {
                    ProgressView()
                        .controlSize(.large)
                } else if idleSkills.isEmpty {
                    ContentUnavailableView("No Idle Skills", systemImage: "checkmark.seal")
                }
            }
        }
        .popPageBackground()
        .task {
            if !viewModel.hasLoadedOnce {
                await viewModel.load()
            }
            if !insightsViewModel.hasScannedOnce {
                await insightsViewModel.scan()
            }
        }
        .confirmationDialog(
            "Make \(idleSkills.count) Idle Skills Stub?",
            isPresented: $isConfirmingBulkStub
        ) {
            Button("Make Stubs", role: .destructive) {
                let candidates = idleSkills
                Task {
                    _ = await viewModel.stubAll(candidates)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Popskill will keep recoverable metadata and CC Switch backups for each selected skill.")
        }
    }

    private var isRefreshing: Bool {
        viewModel.isLoading || insightsViewModel.isScanning
    }

    private var subtitle: String {
        if insightsViewModel.isScanning && !insightsViewModel.hasScannedOnce {
            return "Checking local transcript attribution..."
        }

        return "\(idleSkills.count) inactive and unused for \(idleThresholdDays)+ days of \(viewModel.skills.count) installed"
    }

    private func hasRecentAttributedUse(_ skill: Skill, referenceDate: Date) -> Bool {
        guard let stat = usageStat(for: skill), let lastUsedAt = stat.lastUsedAt else {
            return false
        }

        let threshold = TimeInterval(idleThresholdDays) * 24 * 60 * 60
        let cutoff = referenceDate.addingTimeInterval(-threshold)
        return lastUsedAt > cutoff
    }

    private func usageStat(for skill: Skill) -> SkillUsageStat? {
        insightsViewModel.summary.skillStats
            .filter { skill.matchesAttributionSkill($0.skillID) }
            .max {
                switch ($0.lastUsedAt, $1.lastUsedAt) {
                case let (left?, right?):
                    return left < right
                case (.none, .some):
                    return true
                case (.some, .none):
                    return false
                case (.none, .none):
                    return $0.usageEvents < $1.usageEvents
                }
            }
    }
}

struct IdleCandidateRow: View {
    let skill: Skill
    let isStubbing: Bool
    let onStub: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PackageAvatar(name: skill.name, identifier: skill.id)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(skill.name)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)

                    StatusPill(title: idleBadgeTitle, color: .popStatusNeutral)
                }

                Text(skill.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(skill.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)

            Button {
                onStub()
            } label: {
                if isStubbing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Make Stub", systemImage: "icloud.and.arrow.down")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isStubbing)
            .help("Make Stub")
        }
        .frame(minHeight: 68)
    }

    private var idleBadgeTitle: String {
        guard let timestamp = skill.lastLifecycleTimestamp else {
            return "Inactive"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
