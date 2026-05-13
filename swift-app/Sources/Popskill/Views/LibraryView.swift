import Foundation
import SwiftUI

struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    let onLibraryMutation: () async -> Void
    @State private var selectedItemID: String?
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        VStack(spacing: 0) {
            header

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await viewModel.load() }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }

            if !viewModel.unmanagedSkills.isEmpty {
                UnmanagedSkillsBanner(viewModel: viewModel, onImported: onLibraryMutation)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }

            HStack(alignment: .top, spacing: 20) {
                if viewModel.selectedFilter == .stub {
                    stubList
                } else {
                    packageAndSkillList
                }

                if viewModel.selectedFilter == .stub, let selectedStub {
                    StubDetailPane(
                        stub: selectedStub,
                        backup: viewModel.backupSnapshot(for: selectedStub),
                        restoreApp: viewModel.selectedRehydrateApp,
                        isRehydrating: viewModel.isRehydrating(skillID: selectedStub.id)
                    ) { stub in
                        Task {
                            if await viewModel.rehydrate(stub) {
                                selectedItemID = nil
                                viewModel.selectedFilter = .all
                                await onLibraryMutation()
                            }
                        }
                    }
                    .frame(width: 340)
                    .popMaterialCard()
                } else if let selectedPackage {
                    if let packageSkill = skill(forStandalonePackage: selectedPackage) {
                        skillDetailPane(packageSkill)
                    } else {
                        PackageDetailPane(
                            package: selectedPackage,
                            pendingUpdates: viewModel.updates(for: selectedPackage),
                            lastCheckedUpdatesAt: viewModel.lastCheckedUpdatesAt
                        )
                            .frame(width: 360)
                            .popMaterialCard()
                    }
                } else if let selectedSkill {
                    skillDetailPane(selectedSkill)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(maxHeight: .infinity, alignment: .top)
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
            .onChange(of: viewModel.selectedFilter) { _, _ in
                selectedItemID = nil
            }
            .onChange(of: viewModel.selectedPackageFilter) { _, _ in
                selectedItemID = nil
            }
        }
        .popPageBackground()
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: Text(localization.string("Search Library")))
    }

    private var packageAndSkillList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !viewModel.filteredPackages.isEmpty {
                    PopskillSectionTitle(
                        title: "Capability Packages",
                        subtitle: localization.string(
                            "package.componentSummary",
                            viewModel.filteredPackages.reduce(0) { $0 + $1.componentCount },
                            viewModel.filteredPackages.reduce(0) { $0 + $1.installedComponentCount },
                            viewModel.filteredPackages.reduce(0) { $0 + $1.requiredComponentCount }
                        )
                    )

                    LazyVGrid(columns: packageGridColumns, alignment: .leading, spacing: 16) {
                        ForEach(viewModel.filteredPackages) { package in
                            let selectionID = selectionID(forPackage: package.id)
                            PopskillSelectableCard(isSelected: selectedItemID == selectionID) {
                                selectedItemID = selectionID
                            } content: {
                                PackageRow(
                                    package: package,
                                    pendingUpdates: viewModel.updates(for: package).count
                                )
                            }
                        }
                    }
                }
            }
            .padding(2)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .overlay {
            if viewModel.isLoading && viewModel.packages.isEmpty && viewModel.skills.isEmpty {
                ProgressView()
                    .controlSize(.large)
            } else if viewModel.filteredPackages.isEmpty {
                ContentUnavailableView(emptyStateTitle, systemImage: "shippingbox")
            }
        }
    }

    private var stubList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                PopskillSectionTitle(
                    title: "Stubs",
                    subtitle: "\(viewModel.filteredStubs.count) recoverable cards"
                )

                ForEach(viewModel.filteredStubs) { stub in
                    let selectionID = selectionID(forStub: stub.id)
                    PopskillSelectableCard(isSelected: selectedItemID == selectionID) {
                        selectedItemID = selectionID
                    } content: {
                        StubRow(
                            stub: stub,
                            isRehydrating: viewModel.isRehydrating(skillID: stub.id)
                        ) {
                            Task {
                                if await viewModel.rehydrate(stub) {
                                    selectedItemID = nil
                                    await onLibraryMutation()
                                }
                            }
                        }
                    }
                }
            }
            .padding(2)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
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
            return nil
        }
        return viewModel.filteredSkills.first { $0.id == skillID }
    }

    private var selectedStub: StubbedSkill? {
        guard let stubID = stubID(from: selectedItemID) else {
            return nil
        }
        return viewModel.filteredStubs.first { $0.id == stubID }
    }

    private var selectedPackage: CapabilityPackage? {
        guard viewModel.selectedFilter != .stub else {
            return nil
        }

        guard selectedItemID != nil else {
            return nil
        }

        guard let packageID = packageID(from: selectedItemID) else {
            return nil
        }
        return viewModel.filteredPackages.first { $0.id == packageID }
    }

    @ViewBuilder
    private func skillDetailPane(_ skill: Skill) -> some View {
        SkillDetailPane(
            skill: skill,
            isUninstalling: viewModel.isUninstalling(skillID: skill.id),
            isStubbing: viewModel.isStubbing(skillID: skill.id),
            isScanningSecurity: viewModel.isScanningSecurity(skillID: skill.id),
            securityScanResult: viewModel.securityScanResult(skillID: skill.id),
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
                        selectedItemID = nil
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
                    selectedItemID = nil
                    await onLibraryMutation()
                }
            }
        }
        .frame(width: 340)
        .popMaterialCard()
    }

    private func skill(forStandalonePackage package: CapabilityPackage) -> Skill? {
        guard package.type == .standalone,
              let component = package.components.skills.first ?? package.components.all.first(where: { $0.kind == "skill" }) else {
            return nil
        }

        return viewModel.skills.first { skill in
            skill.id == component.id
                || skill.directory == component.location
                || skill.name == component.name
        }
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

    private var packageGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]
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

    private func ensureSelectionIsValid() {
        guard let selectedItemID else {
            return
        }

        if viewModel.selectedFilter == .stub {
            if let stubID = stubID(from: selectedItemID),
               viewModel.filteredStubs.contains(where: { $0.id == stubID }) {
                return
            }
            self.selectedItemID = nil
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

        self.selectedItemID = nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("Installed")
                        .font(.popLargeTitle)
                    Text(localization.string(
                        "library.summary",
                        viewModel.packages.count,
                        viewModel.skills.count,
                        viewModel.enabledCount
                    ))
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

                if viewModel.updatableCount > 0 || viewModel.isUpdatingAll {
                    Button {
                        Task {
                            if await viewModel.updateAll() > 0 {
                                await onLibraryMutation()
                            }
                        }
                    } label: {
                        if viewModel.isUpdatingAll {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(localization.string("Update All"), systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Update All")
                    .disabled(viewModel.isCheckingUpdates || viewModel.isUpdatingAny)
                }

                Button {
                    Task { await viewModel.checkUpdates() }
                } label: {
                    if viewModel.isCheckingUpdates {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .buttonStyle(.bordered)
                .help("Check Updates")
                .disabled(viewModel.isCheckingUpdates || viewModel.isUpdatingAny)

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
                Picker("Sort", selection: $viewModel.sortOption) {
                    ForEach(LibrarySortOption.allCases) { option in
                        Text(localization.string(option.title)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)

                Picker("Package Type", selection: $viewModel.selectedPackageFilter) {
                    ForEach(PackageFilter.allCases) { filter in
                        Text(localization.string(filter.title)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)

                Picker("Filter", selection: $viewModel.selectedFilter) {
                    ForEach(LibraryFilter.allCases) { filter in
                        Text(localization.string(filter.title)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
            }

            HStack(spacing: 8) {
                Image(systemName: viewModel.lastUpdateCheckError == nil ? "clock.arrow.circlepath" : "exclamationmark.triangle")
                    .foregroundStyle(viewModel.lastUpdateCheckError == nil ? Color.popTertiaryLabel : Color.popStatusWarning)

                Text(updateCheckSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .help(viewModel.lastUpdateCheckError ?? localization.string("update.autoHelp"))

            if viewModel.selectedFilter == .stub {
                Picker("Restore In", selection: $viewModel.selectedRehydrateApp) {
                    ForEach(TargetApp.supported, id: \.id) { app in
                        Text(app.title).tag(app)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var updateCheckSummary: String {
        let availability = localization.string("update.availableCount", viewModel.updatableCount)
        let cadence = viewModel.lastUpdateCheckError == nil
            ? localization.string("update.autoEvery30m")
            : localization.string("update.lastCheckFailed")

        guard let lastCheckedUpdatesAt = viewModel.lastCheckedUpdatesAt else {
            return "\(availability) · \(localization.string("update.checkPending")) · \(cadence)"
        }

        return "\(availability) · \(localization.string("update.checkedAt", lastCheckedUpdatesAt.formatted(date: .omitted, time: .shortened))) · \(cadence)"
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
                    ForEach(TargetApp.supported, id: \.id) { app in
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
        .padding(16)
        .popMaterialCard(cornerRadius: PopskillRadius.card)
    }
}

struct PackageDetailPane: View {
    let package: CapabilityPackage?
    let pendingUpdates: [SkillUpdateInfo]
    let lastCheckedUpdatesAt: Date?
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        Group {
            if let package {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            PackageAvatar(name: package.name, identifier: package.id, size: 52)

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

                        Text(briefSummary(package.summary))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                        HStack(spacing: 8) {
                            StatusPill(title: package.typeLabel, color: packageColor(package.type))
                            StatusPill(title: package.health.title, color: packageHealthColor(package.health))
                            if !pendingUpdates.isEmpty {
                                StatusPill(title: "Update Available", color: .popStatusWarning)
                            }
                        }

                        DetailSection(title: "Update Status", accent: PopskillSectionAccent.color(for: 0)) {
                            let lifecycle = package.lifecycle ?? .untracked
                            DetailField(
                                title: "Lifecycle State",
                                value: packageLifecycleStateLabel(package, pendingUpdates: pendingUpdates.count)
                            )
                            DetailField(title: "Pending Updates", value: "\(pendingUpdates.count)")
                            DetailField(
                                title: "Last Checked",
                                value: lastCheckedUpdatesAt?.formatted(date: .abbreviated, time: .shortened)
                                    ?? localization.string("Not Tracked")
                            )
                            DetailField(
                                title: "Update Channel",
                                value: packageUpdateChannelLabel(package)
                            )
                            DetailField(
                                title: "Installed Date",
                                value: formattedOptionalTimestamp(lifecycle.installedAt, fallback: localization.string("Not Tracked"))
                            )
                            DetailField(
                                title: "Last Updated",
                                value: formattedOptionalTimestamp(lifecycle.updatedAt, fallback: localization.string("Not Tracked"))
                            )
                            DetailField(title: "Installed Components", value: "\(package.installedComponentCount) / \(package.componentCount)")
                            DetailField(title: "Missing Components", value: "\(package.missingComponentCount)")
                            DetailField(title: "Required Missing", value: "\(package.missingRequiredComponentCount)")
                            DetailField(title: "Recoverable Missing", value: "\(package.recoverableMissingComponentCount)")
                            if let hash = lifecycle.contentHash, !hash.isEmpty {
                                DetailField(title: "Hash", value: String(hash.prefix(12)))
                            }

                            if !pendingUpdates.isEmpty {
                                ForEach(pendingUpdates.prefix(3)) { update in
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.popStatusWarning)
                                            .frame(width: 16)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(update.name)
                                                .font(.caption.weight(.semibold))
                                            Text(hashDeltaSummary(update))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        DetailSection(title: "Components", accent: PopskillSectionAccent.color(for: 1)) {
                            PackageComponentTree(components: package.components)
                        }

                        DetailSection(title: "Config", accent: PopskillSectionAccent.color(for: 2)) {
                            if package.configSchema.isEmpty {
                                LocalizedText("No config required")
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
                                            Text("\(field.storage) · \(localization.string(field.required ? "Required" : "Optional"))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        DetailSection(title: "Source & Docs", accent: PopskillSectionAccent.color(for: 3)) {
                            DetailField(title: "Type", value: package.typeLabel)
                            DetailField(title: "Package Kinds", value: package.primaryComponentKindsLabel)
                            DetailField(title: "Source Kind", value: packageSourceKindLabel(package.source.kind))
                            DetailField(title: "Location", value: package.source.location)
                            DetailField(title: "Update Strategy", value: packageUpdateStrategyLabel(package.source.updateStrategy))
                            DetailField(
                                title: "Repository",
                                value: packageRepositoryLabel(package, fallback: localization.string("Not Tracked"))
                            )

                            HStack(spacing: 8) {
                                if let url = package.sourceURL {
                                    Link(destination: url) {
                                        LocalizedLabel(title: "Open Source", systemImage: "arrow.up.right.square")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if let readmeURL = packageReadmeURL(package) {
                                    Link(destination: readmeURL) {
                                        LocalizedLabel(title: "Open Markdown", systemImage: "doc.text")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if let folderURL = packagePrimaryFolderURL(package) {
                                    Link(destination: folderURL) {
                                        LocalizedLabel(title: "Open Folder", systemImage: "folder")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .padding(22)
                }
            } else {
                ContentUnavailableView("No Package Selected", systemImage: "square.stack.3d.up")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PopskillRadius.largeCard, style: .continuous))
    }
}

struct PackageRow: View {
    let package: CapabilityPackage
    let pendingUpdates: Int
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PackageAvatar(name: package.name, identifier: package.id)

            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(package.name)
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(Color.popLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        StatusPill(title: package.typeLabel, color: packageColor(package.type))
                        StatusPill(title: package.health.title, color: packageHealthColor(package.health))
                        if pendingUpdates > 0 {
                            StatusPill(title: "Updates \(pendingUpdates)", color: .popStatusWarning)
                        }

                        if package.missingComponentCount > 0 {
                            Label("\(package.missingComponentCount)", systemImage: "icloud.and.arrow.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.popStatusWarning)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.popStatusWarning.opacity(0.10), in: Capsule())
                        }
                    }

                    Text(package.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(localization.string(
                        "package.componentSummary",
                        package.componentCount,
                        package.installedComponentCount,
                        package.requiredComponentCount
                    ))
                        .font(.caption)
                        .foregroundStyle(Color.popTertiaryLabel)
                        .lineLimit(1)
                }
            }
        }
        .frame(minHeight: 96)
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

            if !component.installed {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.popStatusWarning)
                    .help("Rehydrate")
            }

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
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        Group {
            if let skill {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            PackageAvatar(name: skill.name, identifier: skill.id, size: 52)

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

                        Text(briefSummary(skill.description))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                        DetailSection(title: "Source & Docs", accent: PopskillSectionAccent.color(for: 0)) {
                            HStack(spacing: 8) {
                                if let markdownURL = skill.markdownURL {
                                    Link(destination: markdownURL) {
                                        LocalizedLabel(title: "Open Markdown", systemImage: "doc.text")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if FileManager.default.fileExists(atPath: skill.localStoreURL.path) {
                                    Link(destination: skill.localStoreURL) {
                                        LocalizedLabel(title: "Open Folder", systemImage: "folder")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if let url = skill.sourceURL {
                                    Link(destination: url) {
                                        LocalizedLabel(title: "Open Source", systemImage: "arrow.up.right.square")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            DetailField(title: "Directory", value: skill.directory)
                            DetailField(title: "Identifier", value: skill.id)
                        }

                        DetailSection(title: "Lifecycle", accent: PopskillSectionAccent.color(for: 1)) {
                            DetailField(title: "Version", value: localization.string("Not Tracked"))
                            DetailField(
                                title: "Installed Date",
                                value: formattedOptionalTimestamp(skill.installedAt, fallback: localization.string("Not Tracked"))
                            )
                            DetailField(
                                title: "Last Updated",
                                value: formattedOptionalTimestamp(skill.updatedAt, fallback: localization.string("Not Tracked"))
                            )
                            DetailField(title: "Size", value: skill.sizeBytes.map(byteCountText) ?? localization.string("Not Tracked"))
                            DetailField(title: "Downloads", value: localization.string("Not Tracked"))
                            if let contentHash = skill.contentHash, !contentHash.isEmpty {
                                DetailField(title: "Hash", value: String(contentHash.prefix(12)))
                            }
                        }

                        DetailSection(title: "Enabled In", accent: PopskillSectionAccent.color(for: 2)) {
                            AppToggleRow(
                                apps: TargetApp.supported,
                                isOn: { app in
                                    skill.apps.isEnabled(app)
                                },
                                isPending: { app in
                                    isToggling(skill, app)
                                },
                                onToggle: { app, enabled in
                                    onToggle(skill, app, enabled)
                                }
                            )
                        }

                        DetailSection(title: "Security", accent: PopskillSectionAccent.color(for: 3)) {
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
                                    LocalizedLabel(title: "Scan with AgentShield", systemImage: "shield.lefthalf.filled")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isScanningSecurity || !FileManager.default.fileExists(atPath: skill.localStoreURL.path))
                        }

                        HStack(spacing: 10) {
                            Button {
                                isConfirmingStub = true
                            } label: {
                                if isStubbing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    LocalizedLabel(title: "Make Stub", systemImage: "icloud.and.arrow.down")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isStubbing || isUninstalling)
                            .confirmationDialog(
                                "Make \(skill.name) a stub?",
                                isPresented: $isConfirmingStub,
                                titleVisibility: .visible
                            ) {
                                Button {
                                    onStub(skill)
                                } label: {
                                    LocalizedText("Make Stub")
                                }
                                Button(role: .cancel) {} label: {
                                    LocalizedText("Cancel")
                                }
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
                                    LocalizedLabel(title: "Uninstall", systemImage: "trash")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isUninstalling || isStubbing)
                            .confirmationDialog(
                                "Uninstall \(skill.name)?",
                                isPresented: $isConfirmingUninstall,
                                titleVisibility: .visible
                            ) {
                                Button(role: .destructive) {
                                    onUninstall(skill)
                                } label: {
                                    LocalizedText("Uninstall")
                                }
                                Button(role: .cancel) {} label: {
                                    LocalizedText("Cancel")
                                }
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
        .clipShape(RoundedRectangle(cornerRadius: PopskillRadius.largeCard, style: .continuous))
    }
}

struct StubDetailPane: View {
    let stub: StubbedSkill?
    let backup: SkillBackup?
    let restoreApp: TargetApp
    let isRehydrating: Bool
    let onRehydrate: (StubbedSkill) -> Void
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        Group {
            if let stub {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            PackageAvatar(name: stub.skill.name, identifier: stub.skill.id, size: 52)
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
                            DetailField(title: "Restore Target", value: rehydrateTargetPath(for: stub.skill, app: restoreApp))
                            DetailField(title: "Stubbed", value: formattedTimestamp(stub.stubbedAt))
                            DetailField(
                                title: "Backup Created",
                                value: backup.map { formattedTimestamp($0.createdAt) } ?? localization.string("Not Tracked")
                            )

                            Button {
                                onRehydrate(stub)
                            } label: {
                                if isRehydrating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    LocalizedLabel(title: "Rehydrate", systemImage: "icloud.and.arrow.down")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRehydrating)
                        }

                        DetailSection(title: "Source", accent: PopskillSectionAccent.color(for: 2)) {
                            DetailField(title: "Original Source", value: stub.skill.sourceLabel)
                            DetailField(title: "Original Directory", value: stub.skill.directory)
                            DetailField(
                                title: "Current State",
                                value: "Removed locally, recoverable from backup."
                            )
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
        .clipShape(RoundedRectangle(cornerRadius: PopskillRadius.largeCard, style: .continuous))
    }
}

struct SkillRow: View {
    let skill: Skill
    let updateInfo: SkillUpdateInfo?
    let isUpdating: Bool
    let securityScanResult: SecurityScanResult?
    let isToggling: (TargetApp) -> Bool
    let onToggle: (TargetApp, Bool) -> Void
    let onUpdate: (SkillUpdateInfo) -> Void
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PackageAvatar(name: skill.name, identifier: skill.id)

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

                        if updateInfo != nil {
                            StatusPill(title: "Updates", color: .popStatusWarning)
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

                AppToggleRow(
                    apps: TargetApp.supported,
                    isOn: { app in
                        skill.apps.isEnabled(app)
                    },
                    isPending: { app in
                        isToggling(app)
                    },
                    onToggle: onToggle
                )
            }

            Spacer(minLength: 8)

            if let updateInfo {
                Button {
                    onUpdate(updateInfo)
                } label: {
                    if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(localization.string("Update"), systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isUpdating)
                .help("Update")
            }
        }
        .frame(minHeight: 136)
    }

}

struct StubRow: View {
    let stub: StubbedSkill
    let isRehydrating: Bool
    let onRehydrate: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PackageAvatar(name: stub.skill.name, identifier: stub.skill.id)
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

private func formattedOptionalTimestamp(_ timestamp: Int?, fallback: String) -> String {
    guard let timestamp, timestamp > 0 else {
        return fallback
    }
    return formattedTimestamp(timestamp)
}

private func byteCountText(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

private func hashDeltaSummary(_ update: SkillUpdateInfo) -> String {
    let current = update.currentHash.map { String($0.prefix(8)) } ?? "unknown"
    return "\(current) -> \(String(update.remoteHash.prefix(8)))"
}

private func briefSummary(_ text: String, maxLength: Int = 180) -> String {
    let normalized = text
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if let firstSentenceEnd = normalized.rangeOfCharacter(from: CharacterSet(charactersIn: ".。!?！？")) {
        return String(normalized[...firstSentenceEnd.lowerBound])
    }

    guard normalized.count > maxLength else {
        return normalized
    }

    return String(normalized.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
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

private func packageHealthColor(_ health: CapabilityPackageHealth) -> Color {
    switch health {
    case .active:
        return .popStatusOK
    case .partial:
        return .popStatusWarning
    case .inactive:
        return .popStatusNeutral
    case .blocked:
        return .popStatusError
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

    if component.isRecoverable {
        return component.required ? .popStatusWarning : .popStatusNeutral
    }

    return .popStatusNeutral
}

private func packageRepositoryLabel(_ package: CapabilityPackage, fallback: String) -> String {
    guard let owner = package.source.repoOwner,
          let name = package.source.repoName,
          !owner.isEmpty,
          !name.isEmpty
    else {
        return fallback
    }

    if let branch = package.source.repoBranch, !branch.isEmpty, branch != "main" {
        return "\(owner)/\(name)@\(branch)"
    }
    return "\(owner)/\(name)"
}

private func packageReadmeURL(_ package: CapabilityPackage) -> URL? {
    guard let readmeUrl = package.source.readmeUrl,
          let url = URL(string: readmeUrl),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme)
    else {
        return nil
    }
    return url
}

private func packageLifecycleStateLabel(_ package: CapabilityPackage, pendingUpdates: Int) -> String {
    if package.missingRequiredComponentCount > 0 {
        return "Blocked (missing required components)"
    }
    if package.missingComponentCount > 0 {
        if package.recoverableMissingComponentCount > 0 {
            return "Partial (rehydrate available)"
        }
        return "Partial (missing components)"
    }
    if pendingUpdates > 0 {
        return "Update available"
    }
    if package.installedComponentCount > 0 {
        return "Up to date"
    }
    return "Not installed"
}

private func packageUpdateChannelLabel(_ package: CapabilityPackage) -> String {
    guard let owner = package.source.repoOwner,
          let name = package.source.repoName,
          !owner.isEmpty,
          !name.isEmpty
    else {
        return package.source.repoBranch.map { "branch \($0)" } ?? "manual"
    }

    if let branch = package.source.repoBranch, !branch.isEmpty {
        return "\(owner)/\(name)@\(branch)"
    }

    return "\(owner)/\(name)"
}

private func packageSourceKindLabel(_ kind: String) -> String {
    switch kind.lowercased() {
    case "builtin":
        return "Built-in"
    case "github":
        return "GitHub"
    case "local":
        return "Local"
    default:
        return kind.capitalized
    }
}

private func packageUpdateStrategyLabel(_ strategy: String) -> String {
    switch strategy.lowercased() {
    case "manual":
        return "Manual"
    case "git":
        return "Git"
    case "registry":
        return "Registry"
    default:
        return strategy.capitalized
    }
}

private func packagePrimaryFolderURL(_ package: CapabilityPackage) -> URL? {
    let paths = package.components.all
        .filter(\.installed)
        .compactMap(\.location)

    for path in paths {
        if let fileURL = resolvedLocalPathURL(path),
           FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
    }
    return nil
}

private func rehydrateTargetPath(for skill: Skill, app: TargetApp) -> String {
    let relativeRoot = app.definition.skillDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    let baseURL: URL
    if relativeRoot.hasPrefix("/") {
        baseURL = URL(fileURLWithPath: relativeRoot)
    } else {
        baseURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relativeRoot)
    }
    return baseURL.appendingPathComponent(skill.directory).path
}

private func resolvedLocalPathURL(_ path: String) -> URL? {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let expanded = (trimmed as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded)
    }

    return URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".cc-switch")
        .appendingPathComponent("skills")
        .appendingPathComponent(expanded)
}
