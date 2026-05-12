import SwiftUI

struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await viewModel.load() }
                }
                Divider()
            }

            List(viewModel.filteredSkills) { skill in
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
                } else if viewModel.filteredSkills.isEmpty {
                    ContentUnavailableView("No Skills", systemImage: "shippingbox")
                }
            }
        }
        .background(Color.popMainBackground)
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search Library")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Installed")
                        .font(.system(.largeTitle, weight: .bold))
                    Text("\(viewModel.skills.count) skills · \(viewModel.enabledCount) enabled")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 14) {
                    SummaryMetric(title: "Active", value: viewModel.enabledCount)
                    SummaryMetric(title: "Inactive", value: viewModel.inactiveCount)
                    SummaryMetric(
                        title: "Unmanaged",
                        value: viewModel.unmanagedCount,
                        color: viewModel.unmanagedCount > 0 ? .popStatusWarning : .popLabel
                    )
                }

                Button {
                    Task { await viewModel.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh")
                .disabled(viewModel.isLoading)
            }

            Picker("Filter", selection: $viewModel.selectedFilter) {
                ForEach(LibraryFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Color.popMainBackground)
    }
}

struct SkillRow: View {
    let skill: Skill
    let isToggling: (TargetApp) -> Bool
    let onToggle: (TargetApp, Bool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            InitialAvatarView(name: skill.name, identifier: skill.id)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(skill.name)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)

                    if skill.enabledAppCount == 0 {
                        StatusPill(title: "Inactive", color: .popStatusNeutral)
                    }
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

            HStack(spacing: 8) {
                ForEach([TargetApp.claude, .codex, .gemini], id: \.id) { app in
                    AppToggle(
                        title: app.title,
                        isOn: skill.apps.isEnabled(app),
                        isPending: isToggling(app)
                    ) { enabled in
                        onToggle(app, enabled)
                    }
                }
            }
            .frame(width: 250, alignment: .trailing)
        }
        .frame(minHeight: 68)
    }
}

struct AppToggle: View {
    let title: String
    let isOn: Bool
    let isPending: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 5) {
                if isPending {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? Color.accentColor : Color.popStatusNeutral)
                }
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 74, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .background(isOn ? Color.popHighlightFill : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isOn ? Color.accentColor.opacity(0.25) : Color.popBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .help(title)
    }
}

struct SummaryMetric: View {
    let title: String
    let value: Int
    var color: Color = .popLabel

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 86, alignment: .trailing)
    }
}

struct InitialAvatarView: View {
    let name: String
    let identifier: String

    private var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "S"
    }

    private var color: Color {
        let palette: [Color] = [.orange, .purple, .blue, .green, .pink, .teal]
        let index = Int(identifier.hashValue.magnitude % UInt(palette.count))
        return palette[index]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.gradient)
            Text(initial)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }
}

struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.10), in: Capsule())
    }
}

struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.popStatusWarning)
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: onRetry)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.popStatusWarning.opacity(0.08))
    }
}
