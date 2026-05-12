import SwiftUI

struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var selectedSkillID: Skill.ID?

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

            HStack(spacing: 0) {
                List(viewModel.filteredSkills, selection: $selectedSkillID) { skill in
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
                    .tag(skill.id)
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

                Divider()

                SkillDetailPane(skill: selectedSkill)
                    .frame(width: 320)
            }
            .onChange(of: viewModel.skills) { _, skills in
                if selectedSkillID == nil {
                    selectedSkillID = skills.first?.id
                }
            }
        }
        .background(Color.popMainBackground)
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search Library")
    }

    private var selectedSkill: Skill? {
        guard let selectedSkillID else {
            return viewModel.filteredSkills.first
        }
        return viewModel.skills.first { $0.id == selectedSkillID }
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

struct SkillDetailPane: View {
    let skill: Skill?

    var body: some View {
        Group {
            if let skill {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            InitialAvatarView(name: skill.name, identifier: skill.id)
                                .frame(width: 52, height: 52)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(skill.name)
                                    .font(.title2.weight(.bold))
                                    .lineLimit(2)
                                Text(skill.sourceLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Text(skill.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        DetailSection(title: "Enabled In") {
                            ForEach([TargetApp.claude, .codex, .gemini, .opencode, .hermes], id: \.id) { app in
                                HStack {
                                    Image(systemName: skill.apps.isEnabled(app) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(skill.apps.isEnabled(app) ? Color.accentColor : Color.popStatusNeutral)
                                    Text(app.title)
                                    Spacer()
                                }
                            }
                        }

                        DetailSection(title: "Metadata") {
                            DetailField(title: "Directory", value: skill.directory)
                            DetailField(title: "Identifier", value: skill.id)
                            if let contentHash = skill.contentHash, !contentHash.isEmpty {
                                DetailField(title: "Hash", value: String(contentHash.prefix(12)))
                            }
                        }

                        if let readmeUrl = skill.readmeUrl, let url = URL(string: readmeUrl) {
                            Link(destination: url) {
                                Label("Open Source", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(22)
                }
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right")
            }
        }
        .background(Color.popHeaderBackground.opacity(0.45))
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.popSecondaryLabel)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

struct DetailField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(3)
        }
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
