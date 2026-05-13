import SwiftUI

struct IdleCandidatesView: View {
    @Bindable var viewModel: LibraryViewModel

    private var idleSkills: [Skill] {
        viewModel.skills.filter { $0.enabledAppCount == 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Idle Candidates")
                        .font(.system(.largeTitle, weight: .bold))
                    Text("\(idleSkills.count) inactive of \(viewModel.skills.count) installed")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await viewModel.load() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .help("Refresh")
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await viewModel.load() }
                }
                Divider()
            }

            List(idleSkills) { skill in
                SkillRow(
                    skill: skill,
                    isToggling: { app in
                        viewModel.isToggling(skillID: skill.id, app: app)
                    }
                ) { app, enabled in
                    Task {
                        await viewModel.setEnabled(enabled, for: skill, app: app)
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
                } else if idleSkills.isEmpty {
                    ContentUnavailableView("No Idle Skills", systemImage: "checkmark.seal")
                }
            }
        }
        .background(Color.popMainBackground)
        .task {
            if !viewModel.hasLoadedOnce {
                await viewModel.load()
            }
        }
    }
}
