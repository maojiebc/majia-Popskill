import Foundation
import SwiftUI

struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    let onLibraryMutation: () async -> Void
    @State private var selectedItemID: String?

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
                if viewModel.selectedFilter == .stub {
                    stubList
                } else {
                    packageAndSkillList
                }

                Divider()

                if viewModel.selectedFilter == .stub {
                    StubDetailPane(
                        stub: selectedStub,
                        restoreApp: viewModel.selectedRehydrateApp,
                        isRehydrating: selectedStub.map { viewModel.isRehydrating(skillID: $0.id) } ?? false
                    ) { stub in
                        Task {
                            if await viewModel.rehydrate(stub) {
                                selectedItemID = defaultSelectionID()
                                viewModel.selectedFilter = .all
                                await onLibraryMutation()
                            }
                        }
                    }
                    .frame(width: 320)
                } else if let selectedPackage {
                    PackageDetailPane(package: selectedPackage)
                        .frame(width: 360)
                } else {
                    SkillDetailPane(
                        skill: selectedSkill,
                        isUninstalling: selectedSkill.map { viewModel.isUninstalling(skillID: $0.id) } ?? false,
                        isStubbing: selectedSkill.map { viewModel.isStubbing(skillID: $0.id) } ?? false,
                        isScanningSecurity: selectedSkill.map { viewModel.isScanningSecurity(skillID: $0.id) } ?? false,
                        securityScanResult: selectedSkill.flatMap { viewModel.securityScanResult(skillID: $0.id) },
                        isToggling: { skill, app in
                            viewModel.isToggling(skillID: skill.id, app: app)
                        },
                        onToggle: { skill, app, enabled in
                            Task {
                                await viewModel.setEnabled(enabled, for: skill, app: app)
                            }
                        },
                        onSecurityScan: { skill in
                            Task {
                                await viewModel.scanSecurity(skill)
                            }
                        },
                        onStub: { skill in
                            Task {
                                if await viewModel.stub(skill) {
                                    selectedItemID = defaultSelectionID()
                                    if viewModel.filteredSkills.isEmpty {
                                        viewModel.selectedFilter = .stub
                                    }
                                    await onLibraryMutation()
                                }
                            }
                        }
                    ) { skill in
                        Task {
                            if await viewModel.uninstall(skill) {
                                selectedItemID = defaultSelectionID()
                                await onLibraryMutation()
                            }
                        }
                    }
                    .frame(width: 320)
                }
            }
            .onChange(of: viewModel.skills) { _, skills in
                ensureSelectionIsValid()
            }
            .onChange(of: viewModel.packages) { _, _ in
                ensureSelectionIsValid()
            }
            .onChange(of: viewModel.filteredSkills) { _, skills in
                ensureSelectionIsValid()
            }
            .onChange(of: viewModel.filteredStubs) { _, stubs in
                ensureSelectionIsValid()
            }
            .onChange(of: viewModel.filteredPackages) { _, _ in
                ensureSelectionIsValid()
            }
            .onChange(of: viewModel.selectedFilter) { _, filter in
                selectedItemID = defaultSelectionID()
            }
            .onChange(of: viewModel.selectedPackageFilter) { _, _ in
                selectedItemID = defaultSelectionID()
            }
        }
        .popPageBackground()
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search Library")
    }

    private var packageAndSkillList: some View {
        List(selection: $selectedItemID) {
            if !viewModel.filteredPackages.isEmpty {
                Section {
                    ForEach(viewModel.filteredPackages) { package in
                        PackageRow(package: package)
                            .tag(selectionID(forPackage: package.id))
                            .listRowSeparator(.visible)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                } header: {
                    Text("Capability Packages")
                }
            }

            if viewModel.selectedPackageFilter == .all {
                Section {
                    ForEach(viewModel.filteredSkills) { skill in
                        SkillRow(
                            skill: skill,
                            securityScanResult: viewModel.securityScanResult(skillID: skill.id),
                            isToggling: { app in
                                viewModel.isToggling(skillID: skill.id, app: app)
                            }
                        ) { app, enabled in
                            Task {
                                await viewModel.setEnabled(enabled, for: skill, app: app)
                            }
                        }
                        .tag(selectionID(forSkill: skill.id))
                        .listRowSeparator(.visible)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                } header: {
                    Text("Installed Skills")
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading && viewModel.packages.isEmpty && viewModel.skills.isEmpty {
                ProgressView()
                    .controlSize(.large)
            } else if viewModel.filteredPackages.isEmpty && visibleSkillRowsAreEmpty {
                ContentUnavailableView(emptyStateTitle, systemImage: "shippingbox")
            }
        }
    }

    private var stubList: some View {
        List(viewModel.filteredStubs, selection: $selectedItemID) { stub in
            StubRow(
                stub: stub,
                isRehydrating: viewModel.isRehydrating(skillID: stub.id)
            ) {
                Task {
                    if await viewModel.rehydrate(stub) {
                        selectedItemID = defaultSelectionID()
                        await onLibraryMutation()
                    }
                }
            }
            .tag(selectionID(forStub: stub.id))
            .listRowSeparator(.visible)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading && viewModel.stubs.isEmpty {
                ProgressView()
                    .controlSize(.large)
            } else if viewModel.filteredStubs.isEmpty {
                ContentUnavailableView(emptyStateTitle, systemImage: "icloud")
            }
        }
    }

    private var selectedSkill: Skill? {
        guard let skillID = skillID(from: selectedItemID) else {
            return selectedItemID == nil && viewModel.filteredPackages.isEmpty
                ? viewModel.filteredSkills.first
                : nil
        }
        return viewModel.filteredSkills.first { $0.id == skillID } ?? viewModel.filteredSkills.first
    }

    private var selectedStub: StubbedSkill? {
        guard let stubID = stubID(from: selectedItemID) else {
            return viewModel.filteredStubs.first
        }
        return viewModel.filteredStubs.first { $0.id == stubID } ?? viewModel.filteredStubs.first
    }

    private var selectedPackage: CapabilityPackage? {
        guard viewModel.selectedFilter != .stub else {
            return nil
        }

        guard selectedItemID != nil else {
            return viewModel.filteredPackages.first
        }

        guard let packageID = packageID(from: selectedItemID) else {
            return nil
        }
        return viewModel.filteredPackages.first { $0.id == packageID } ?? viewModel.filteredPackages.first
    }

    private var visibleSkillRowsAreEmpty: Bool {
        viewModel.selectedPackageFilter != .all || viewModel.filteredSkills.isEmpty
    }

    private var emptyStateTitle: String {
        if viewModel.selectedFilter == .stub {
            return viewModel.stubs.isEmpty ? "No Stubs" : "No Matching Stubs"
        }

        if viewModel.selectedPackageFilter != .all {
            return viewModel.packages.isEmpty ? "No Packages" : "No Matching Packages"
        }

        if viewModel.skills.isEmpty {
            return "No Skills"
        }

        if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Matching Skills"
        }

        switch viewModel.selectedFilter {
        case .all:
            return "No Skills"
        case .active:
            return "No Active Skills"
        case .inactive:
            return "No Inactive Skills"
        case .stub:
            return "No Stubs"
        }
    }

    private func selectionID(forPackage packageID: String) -> String {
        "package|\(packageID)"
    }

    private func selectionID(forSkill skillID: String) -> String {
        "skill|\(skillID)"
    }

    private func selectionID(forStub stubID: String) -> String {
        "stub|\(stubID)"
    }

    private func packageID(from selectionID: String?) -> String? {
        id(from: selectionID, prefix: "package|")
    }

    private func skillID(from selectionID: String?) -> String? {
        id(from: selectionID, prefix: "skill|")
    }

    private func stubID(from selectionID: String?) -> String? {
        id(from: selectionID, prefix: "stub|")
    }

    private func id(from selectionID: String?, prefix: String) -> String? {
        guard let selectionID, selectionID.hasPrefix(prefix) else {
            return nil
        }
        return String(selectionID.dropFirst(prefix.count))
    }

    private func defaultSelectionID() -> String? {
        if viewModel.selectedFilter == .stub {
            return viewModel.filteredStubs.first.map { selectionID(forStub: $0.id) }
        }

        if let package = viewModel.filteredPackages.first {
            return selectionID(forPackage: package.id)
        }

        if viewModel.selectedPackageFilter == .all {
            return viewModel.filteredSkills.first.map { selectionID(forSkill: $0.id) }
        }

        return nil
    }

    private func ensureSelectionIsValid() {
        guard let selectedItemID else {
            self.selectedItemID = defaultSelectionID()
            return
        }

        if viewModel.selectedFilter == .stub {
            if let stubID = stubID(from: selectedItemID),
               viewModel.filteredStubs.contains(where: { $0.id == stubID }) {
                return
            }
            self.selectedItemID = defaultSelectionID()
            return
        }

        if let packageID = packageID(from: selectedItemID),
           viewModel.filteredPackages.contains(where: { $0.id == packageID }) {
            return
        }

        if viewModel.selectedPackageFilter == .all,
           let skillID = skillID(from: selectedItemID),
           viewModel.filteredSkills.contains(where: { $0.id == skillID }) {
            return
        }

        self.selectedItemID = defaultSelectionID()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Installed")
                        .font(.system(.largeTitle, weight: .bold))
                    Text("\(viewModel.packages.count) packages · \(viewModel.skills.count) skills · \(viewModel.enabledCount) enabled")
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
                    SummaryMetric(
                        title: "Stubs",
                        value: viewModel.stubCount,
                        color: viewModel.stubCount > 0 ? .popSectionBlue : .popLabel
                    )
                }

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
                .buttonStyle(.bordered)
                .help("Refresh")
                .disabled(viewModel.isLoading)
            }

            HStack(spacing: 12) {
                Picker("Package Type", selection: $viewModel.selectedPackageFilter) {
                    ForEach(PackageFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)

                Picker("Filter", selection: $viewModel.selectedFilter) {
                    ForEach(LibraryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
            }

            if viewModel.selectedFilter == .stub {
                Picker("Restore In", selection: $viewModel.selectedRehydrateApp) {
                    ForEach(TargetApp.allCases, id: \.id) { app in
                        Text(app.title).tag(app)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .popPageBackground()
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

struct PackageDetailPane: View {
    let package: CapabilityPackage?

    var body: some View {
        Group {
            if let package {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            PackageIcon(type: package.type)
                                .frame(width: 52, height: 52)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(package.name)
                                    .font(.title2.weight(.bold))
                                    .lineLimit(2)
                                Text(package.sourceLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Text(package.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            StatusPill(title: package.typeLabel, color: packageColor(package.type))
                            StatusPill(
                                title: package.installed ? "Installed" : "Available",
                                color: package.installed ? .popStatusOK : .popStatusWarning
                            )
                        }

                        DetailSection(title: "Components", accent: PopskillSectionAccent.color(for: 0)) {
                            PackageComponentTree(components: package.components)
                        }

                        DetailSection(title: "Config", accent: PopskillSectionAccent.color(for: 1)) {
                            if package.configSchema.isEmpty {
                                Text("No config required")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(package.configSchema) { field in
                                    HStack(spacing: 8) {
                                        Image(systemName: field.secret ? "key.fill" : "slider.horizontal.3")
                                            .foregroundStyle(field.secret ? Color.popStatusWarning : Color.secondary)
                                            .frame(width: 16)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(field.label)
                                                .font(.caption.weight(.semibold))
                                            Text("\(field.storage) · \(field.required ? "Required" : "Optional")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        DetailSection(title: "Source", accent: PopskillSectionAccent.color(for: 2)) {
                            DetailField(title: "Type", value: package.typeLabel)
                            DetailField(title: "Location", value: package.source.location)
                            DetailField(title: "Update Strategy", value: package.source.updateStrategy)
                        }
                    }
                    .padding(22)
                }
            } else {
                ContentUnavailableView("No Package Selected", systemImage: "square.stack.3d.up")
            }
        }
        .background(Color.popHeaderBackground.opacity(0.45))
    }
}

struct PackageRow: View {
    let package: CapabilityPackage
    @State private var isExpanded: Bool

    init(package: CapabilityPackage) {
        self.package = package
        _isExpanded = State(initialValue: package.type == .composite)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PackageIcon(type: package.type)

            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(package.name)
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(Color.popLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        StatusPill(title: package.typeLabel, color: packageColor(package.type))
                        StatusPill(
                            title: package.installed ? "Installed" : "Available",
                            color: package.installed ? .popStatusOK : .popStatusWarning
                        )
                    }

                    Text(package.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("\(package.componentCount) components · \(package.installedComponentCount) installed · \(package.requiredComponentCount) required")
                        .font(.caption)
                        .foregroundStyle(Color.popTertiaryLabel)
                        .lineLimit(1)
                }

                if package.type == .composite {
                    DisclosureGroup(isExpanded: $isExpanded) {
                        PackageComponentTree(components: package.components)
                            .padding(.top, 4)
                    } label: {
                        Text("Component Tree")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .disclosureGroupStyle(.automatic)
                } else if let component = package.components.all.first {
                    PackageComponentLine(component: component)
                }
            }
        }
        .frame(minHeight: package.type == .composite ? 130 : 86)
    }
}

struct PackageIcon: View {
    let type: CapabilityPackageType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PopskillRadius.smallCard)
                .fill(packageColor(type).opacity(0.16))
            Image(systemName: type == .composite ? "square.stack.3d.up.fill" : "doc.badge.gearshape.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(packageColor(type))
        }
        .frame(width: 44, height: 44)
    }
}

struct PackageComponentTree: View {
    let components: PackageComponents

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(components.all, id: \.displayKey) { component in
                PackageComponentLine(component: component)
            }
        }
    }
}

struct PackageComponentLine: View {
    let component: PackageComponent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: componentIcon(component.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(componentStatusColor(component))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(component.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let location = component.location, !location.isEmpty {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            StatusPill(title: component.status.capitalized, color: componentStatusColor(component))
        }
    }
}

struct SkillDetailPane: View {
    let skill: Skill?
    let isUninstalling: Bool
    let isStubbing: Bool
    let isScanningSecurity: Bool
    let securityScanResult: SecurityScanResult?
    let isToggling: (Skill, TargetApp) -> Bool
    let onToggle: (Skill, TargetApp, Bool) -> Void
    let onSecurityScan: (Skill) -> Void
    let onStub: (Skill) -> Void
    let onUninstall: (Skill) -> Void
    @State private var isConfirmingStub = false
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

                        DetailSection(title: "Enabled In", accent: PopskillSectionAccent.color(for: 0)) {
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

                        DetailSection(title: "Metadata", accent: PopskillSectionAccent.color(for: 1)) {
                            DetailField(title: "Directory", value: skill.directory)
                            DetailField(title: "Identifier", value: skill.id)
                            if let contentHash = skill.contentHash, !contentHash.isEmpty {
                                DetailField(title: "Hash", value: String(contentHash.prefix(12)))
                            }
                        }

                        DetailSection(title: "Security", accent: PopskillSectionAccent.color(for: 2)) {
                            HStack(spacing: 8) {
                                StatusPill(
                                    title: securityScanTitle(securityScanResult),
                                    color: securityScanColor(securityScanResult)
                                )

                                if let securityScanResult {
                                    Text(securityScanResult.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            Button {
                                onSecurityScan(skill)
                            } label: {
                                if isScanningSecurity {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Scan with AgentShield", systemImage: "shield.lefthalf.filled")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isScanningSecurity || !FileManager.default.fileExists(atPath: skill.localStoreURL.path))
                        }

                        HStack(spacing: 10) {
                            if FileManager.default.fileExists(atPath: skill.localStoreURL.path) {
                                Link(destination: skill.localStoreURL) {
                                    Label("Open Folder", systemImage: "folder")
                                }
                                .buttonStyle(.bordered)
                            }

                            if let url = skill.sourceURL {
                                Link(destination: url) {
                                    Label("Open Source", systemImage: "arrow.up.right.square")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                isConfirmingStub = true
                            } label: {
                                if isStubbing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Make Stub", systemImage: "icloud.and.arrow.down")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isStubbing || isUninstalling)
                            .confirmationDialog(
                                "Make \(skill.name) a stub?",
                                isPresented: $isConfirmingStub,
                                titleVisibility: .visible
                            ) {
                                Button("Make Stub") {
                                    onStub(skill)
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Popskill will remove the local skill content through CC Switch, keep a backup, and leave a recoverable card in Stubs.")
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
                            .disabled(isUninstalling || isStubbing)
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

struct StubDetailPane: View {
    let stub: StubbedSkill?
    let restoreApp: TargetApp
    let isRehydrating: Bool
    let onRehydrate: (StubbedSkill) -> Void

    var body: some View {
        Group {
            if let stub {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            InitialAvatarView(name: stub.skill.name, identifier: stub.skill.id)
                                .frame(width: 52, height: 52)
                                .saturation(0.2)
                                .opacity(0.78)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(stub.skill.name)
                                    .font(.title2.weight(.bold))
                                    .lineLimit(2)
                                Text(stub.skill.sourceLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        StatusPill(title: "Stub", color: .popSectionBlue)

                        Text(stub.skill.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        DetailSection(title: "Restore", accent: PopskillSectionAccent.color(for: 0)) {
                            DetailField(title: "Target App", value: restoreApp.title)
                            DetailField(title: "Stubbed", value: formattedTimestamp(stub.stubbedAt))

                            Button {
                                onRehydrate(stub)
                            } label: {
                                if isRehydrating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Rehydrate", systemImage: "icloud.and.arrow.down")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRehydrating)
                        }

                        DetailSection(title: "Backup", accent: PopskillSectionAccent.color(for: 1)) {
                            DetailField(title: "Backup ID", value: stub.backupId)
                            DetailField(title: "Backup Path", value: stub.backupPath)
                        }
                    }
                    .padding(22)
                }
            } else {
                ContentUnavailableView("No Stub Selected", systemImage: "icloud")
            }
        }
        .background(Color.popHeaderBackground.opacity(0.45))
    }
}

struct SkillRow: View {
    let skill: Skill
    let securityScanResult: SecurityScanResult?
    let isToggling: (TargetApp) -> Bool
    let onToggle: (TargetApp, Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            InitialAvatarView(name: skill.name, identifier: skill.id)

            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(skill.name)
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(Color.popLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if skill.enabledAppCount == 0 {
                            StatusPill(title: "Inactive", color: .popStatusNeutral)
                        }

                        if let securityScanResult {
                            StatusPill(
                                title: securityScanTitle(securityScanResult),
                                color: securityScanColor(securityScanResult)
                            )
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
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(minHeight: 94)
    }
}

struct StubRow: View {
    let stub: StubbedSkill
    let isRehydrating: Bool
    let onRehydrate: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            InitialAvatarView(name: stub.skill.name, identifier: stub.skill.id)
                .saturation(0.2)
                .opacity(0.78)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(stub.skill.name)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)

                    StatusPill(title: "Stub", color: .popSectionBlue)
                }

                Text(stub.skill.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("\(stub.skill.sourceLabel) · stubbed \(formattedTimestamp(stub.stubbedAt))")
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)

            Button {
                onRehydrate()
            } label: {
                if isRehydrating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "icloud.and.arrow.down")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRehydrating)
            .help("Rehydrate")
        }
        .frame(minHeight: 68)
    }
}

private func formattedTimestamp(_ timestamp: Int) -> String {
    Date(timeIntervalSince1970: TimeInterval(timestamp))
        .formatted(date: .abbreviated, time: .shortened)
}

private func securityScanTitle(_ result: SecurityScanResult?) -> String {
    guard let result else {
        return "Not Scanned"
    }

    switch result.status {
    case .verified:
        return "Verified"
    case .warning:
        return "Warning"
    case .blocked:
        return "Blocked"
    case .unavailable:
        return "Unavailable"
    }
}

private func securityScanColor(_ result: SecurityScanResult?) -> Color {
    guard let result else {
        return .popStatusNeutral
    }

    switch result.status {
    case .verified:
        return .popStatusOK
    case .warning:
        return .popStatusWarning
    case .blocked:
        return .popStatusError
    case .unavailable:
        return .popStatusNeutral
    }
}

private func packageColor(_ type: CapabilityPackageType) -> Color {
    switch type {
    case .composite:
        return .popSectionPurple
    case .standalone:
        return .popSectionBlue
    }
}

private func componentIcon(_ kind: String) -> String {
    switch kind.lowercased() {
    case "cli":
        return "terminal"
    case "skill":
        return "shippingbox"
    case "mcp":
        return "point.3.connected.trianglepath.dotted"
    case "agent":
        return "person.crop.circle"
    default:
        return "puzzlepiece.extension"
    }
}

private func componentStatusColor(_ component: PackageComponent) -> Color {
    if component.installed {
        return .popStatusOK
    }

    switch component.status.lowercased() {
    case "available", "declared", "stub", "registry-reference":
        return component.required ? .popStatusWarning : .popStatusNeutral
    default:
        return .popStatusNeutral
    }
}
