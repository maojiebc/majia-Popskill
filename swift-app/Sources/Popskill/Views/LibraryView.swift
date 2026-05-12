import SwiftUI

struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    let onLibraryMutation: () async -> Void
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

            if !viewModel.unmanagedSkills.isEmpty {
                UnmanagedSkillsBanner(viewModel: viewModel, onImported: onLibraryMutation)
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

                SkillDetailPane(
                    skill: selectedSkill,
                    isUninstalling: selectedSkill.map { viewModel.isUninstalling(skillID: $0.id) } ?? false,
                    isToggling: { skill, app in
                        viewModel.isToggling(skillID: skill.id, app: app)
                    },
                    onToggle: { skill, app, enabled in
                        Task {
                            await viewModel.setEnabled(enabled, for: skill, app: app)
                        }
                    }
                ) { skill in
                    Task {
                        if await viewModel.uninstall(skill) {
                            selectedSkillID = viewModel.filteredSkills.first?.id
                            await onLibraryMutation()
                        }
                    }
                }
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

struct UnmanagedSkillsBanner: View {
    @Bindable var viewModel: LibraryViewModel
    let onImported: () async -> Void
    @State private var selectedImportApp: TargetApp = .codex

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(viewModel.unmanagedCount) unmanaged skill\(viewModel.unmanagedCount == 1 ? "" : "s") found", systemImage: "tray.and.arrow.down")
                    .font(.headline)
                Spacer()
                Picker("Import In", selection: $selectedImportApp) {
                    ForEach(TargetApp.allCases, id: \.id) { app in
                        Text(app.title).tag(app)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
            }

            ForEach(viewModel.unmanagedSkills.prefix(3)) { skill in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(skill.name)
                            .font(.subheadline.weight(.semibold))
                        Text(skill.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        Task {
                            if await viewModel.importUnmanaged(skill, apps: [selectedImportApp]) {
                                await onImported()
                            }
                        }
                    } label: {
                        if viewModel.isImporting(directory: skill.directory) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isImporting(directory: skill.directory))
                    .help("Import into \(selectedImportApp.title)")
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(Color.popStatusWarning.opacity(0.08))
    }
}

struct SkillDetailPane: View {
    let skill: Skill?
    let isUninstalling: Bool
    let isToggling: (Skill, TargetApp) -> Bool
    let onToggle: (Skill, TargetApp, Bool) -> Void
    let onUninstall: (Skill) -> Void
    @State private var isConfirmingUninstall = false

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
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                                ForEach(TargetApp.allCases, id: \.id) { app in
                                    AppToggle(
                                        title: app.title,
                                        isOn: skill.apps.isEnabled(app),
                                        isPending: isToggling(skill, app)
                                    ) { enabled in
                                        onToggle(skill, app, enabled)
                                    }
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

                        Button(role: .destructive) {
                            isConfirmingUninstall = true
                        } label: {
                            if isUninstalling {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Uninstall", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isUninstalling)
                        .confirmationDialog(
                            "Uninstall \(skill.name)?",
                            isPresented: $isConfirmingUninstall,
                            titleVisibility: .visible
                        ) {
                            Button("Uninstall", role: .destructive) {
                                onUninstall(skill)
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Popskill will ask CC Switch to remove this skill from all app skill folders and keep CC Switch's uninstall backup.")
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
