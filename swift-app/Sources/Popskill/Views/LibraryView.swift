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
                            lastCheckedUpdatesAt: viewModel.lastCheckedUpdatesAt,
                            selectedRehydrateApp: $viewModel.selectedRehydrateApp,
                            recoverableStubForComponent: { component in
                                viewModel.recoverableStub(for: component)
                            },
                            isRehydratingSkillID: { skillID in
                                viewModel.isRehydrating(skillID: skillID)
                            }
                        ) { component in
                            Task {
                                if await viewModel.rehydrateComponent(component) {
                                    await onLibraryMutation()
                                }
                            }
                        }
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
                            let standaloneSkill = skill(forStandalonePackage: package)
                            let searchState = viewModel.activeSearchQuery.flatMap { query -> PackageRowSearchState? in
                                guard let hit = viewModel.searchHit(for: package) else {
                                    return nil
                                }
                                return PackageRowSearchState(
                                    query: query,
                                    hit: hit,
                                    capabilitySummary: standaloneSkill?.capabilitySummary
                                )
                            }
                            PopskillSelectableCard(isSelected: selectedItemID == selectionID) {
                                selectedItemID = selectionID
                            } content: {
                                PackageRow(
                                    package: package,
                                    signals: viewModel.packageCardSignals(for: package),
                                    quickToggle: standaloneSkill.map { skill in
                                        PackageQuickToggle(
                                            apps: TargetApp.quickToggleSupported,
                                            isOn: { app in
                                                skill.apps.isEnabled(app)
                                            },
                                            isPending: { app in
                                                viewModel.isToggling(skillID: skill.id, app: app)
                                            },
                                            onToggle: { app, enabled in
                                                Task {
                                                    await viewModel.setEnabled(enabled, for: skill, app: app)
                                                }
                                            }
                                        )
                                    },
                                    searchState: searchState
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
                emptyStateView
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if let description = emptyStateDescription {
            ContentUnavailableView {
                Label(emptyStateTitle, systemImage: "shippingbox")
            } description: {
                Text(description)
            }
        } else {
            ContentUnavailableView(emptyStateTitle, systemImage: "shippingbox")
        }
    }

    private var emptyStateDescription: String? {
        guard !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return localization.string("library.search.emptyHint")
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
            updateInfo: viewModel.updateInfo(skillID: skill.id),
            lastCheckedUpdatesAt: viewModel.lastCheckedUpdatesAt,
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
                    .help(localization.string("Update All"))
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
                .help(localization.string("Check Updates"))
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
                .help(localization.string("Refresh"))
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

            AppCountBar(apps: TargetApp.supported) { app in
                viewModel.enabledSkillCount(for: app)
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
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(localization.string("library.unmanagedFound", viewModel.unmanagedCount), systemImage: "tray.and.arrow.down")
                    .font(.headline)
                Spacer()
                Picker(localization.string("Import In"), selection: $selectedImportApp) {
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
                    .help(localization.string("library.importInto", selectedImportApp.title))
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
    @Binding var selectedRehydrateApp: TargetApp
    let recoverableStubForComponent: (PackageComponent) -> StubbedSkill?
    let isRehydratingSkillID: (String) -> Bool
    let onRehydrateComponent: (PackageComponent) -> Void
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
                            DetailField(title: "Coverage", value: packageCoverageLabel(package))
                            DetailField(title: "Missing Components", value: "\(package.missingComponentCount)")
                            DetailField(title: "Required Missing", value: "\(package.missingRequiredComponentCount)")
                            DetailField(title: "Recoverable Missing", value: "\(package.recoverableMissingComponentCount)")
                            if let hash = lifecycle.contentHash, !hash.isEmpty {
                                DetailField(title: "Hash", value: String(hash.prefix(12)))
                            }
                            DetailField(title: "Local Hash State", value: packageLocalHashStateLabel(package, pendingUpdates: pendingUpdates))
                            DetailField(title: "Remote Hash State", value: packageRemoteHashStateLabel(pendingUpdates))

                            if !pendingUpdates.isEmpty {
                                ForEach(pendingUpdates.prefix(3)) { update in
                                    let matchingComponent = package.matchingSkillComponent(for: update)
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.popStatusWarning)
                                            .frame(width: 16)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(update.name)
                                                .font(.caption.weight(.semibold))
                                            Text(packageUpdateSourceLabel(update, component: matchingComponent))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text(packageUpdateHashSummary(update))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                if pendingUpdates.count > 3 {
                                    Text("+\(pendingUpdates.count - 3) more pending updates in Updates")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        DetailSection(title: "Components", accent: PopskillSectionAccent.color(for: 1)) {
                            ForEach(package.componentGroupSummaries) { group in
                                DetailField(title: group.title, value: packageGroupSummaryLabel(group))
                            }

                            let rehydratableComponents = package.components.all.filter { component in
                                recoverableStubForComponent(component) != nil
                            }

                            if !rehydratableComponents.isEmpty {
                                HStack(spacing: 10) {
                                    Image(systemName: "icloud.and.arrow.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.popStatusWarning)
                                    Text("Recoverable skills can be rehydrated directly into the selected app target.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Picker("Restore In", selection: $selectedRehydrateApp) {
                                    ForEach(TargetApp.supported, id: \.id) { app in
                                        Text(app.title).tag(app)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 160)
                            }

                            PackageComponentTree(
                                components: package.components,
                                restoreApp: selectedRehydrateApp,
                                recoverableStubForComponent: recoverableStubForComponent,
                                isRehydratingSkillID: isRehydratingSkillID,
                                onRehydrateComponent: onRehydrateComponent
                            )
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
                                title: "Repository Branch",
                                value: package.source.repoBranch ?? localization.string("Not Tracked")
                            )
                            DetailField(
                                title: "Repository",
                                value: packageRepositoryLabel(package, fallback: localization.string("Not Tracked"))
                            )
                            DetailField(
                                title: "README",
                                value: package.source.readmeUrl ?? localization.string("Not Tracked")
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
    let signals: PackageCardSignals
    var showsStatusSignals: Bool = true
    var quickToggle: PackageQuickToggle? = nil
    var searchState: PackageRowSearchState? = nil
    @Environment(\.popskillLocalization) private var localization

    private var summaryToShow: String {
        searchState?.capabilitySummary ?? package.summary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PackageAvatar(name: package.name, identifier: package.id)

            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(highlightedSearchString(package.name, query: searchState?.query))
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(Color.popLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        StatusPill(title: package.typeLabel, color: packageColor(package.type))
                        StatusPill(title: package.health.title, color: packageHealthColor(package.health))
                        if signals.pendingUpdates > 0 {
                            StatusPill(title: "Updates \(signals.pendingUpdates)", color: .popStatusWarning)
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

                    Text(highlightedSearchString(summaryToShow, query: searchState?.query))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let searchState, !searchState.hit.matchedTriggers.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            ForEach(searchState.hit.matchedTriggers.prefix(4), id: \.self) { trigger in
                                Text(trigger)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.10), in: Capsule())
                            }
                            if searchState.hit.matchedTriggers.count > 4 {
                                Text("+\(searchState.hit.matchedTriggers.count - 4)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text(localization.string(
                        "package.componentSummary",
                        package.componentCount,
                        package.installedComponentCount,
                        package.requiredComponentCount
                    ))
                        .font(.caption)
                        .foregroundStyle(Color.popTertiaryLabel)
                        .lineLimit(1)

                    if package.type == .composite, signals.installedSkillComponentCount > 0 {
                        PackageAppCoverageBar(
                            counts: signals.appEnabledCounts,
                            totalSkills: signals.installedSkillComponentCount
                        )
                    }

                    HStack(spacing: 10) {
                        Label(packageUpdateChannelLabel(package), systemImage: "point.3.connected.trianglepath.dotted")
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Label(packageLifecycleSummaryLabel(package), systemImage: "clock.arrow.circlepath")
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let hash = package.trackedContentHash {
                            Label(shortHash(hash), systemImage: "number")
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.popTertiaryLabel)

                    if let quickToggle {
                        AppToggleRow(
                            apps: quickToggle.apps,
                            isOn: quickToggle.isOn,
                            isPending: quickToggle.isPending,
                            onToggle: quickToggle.onToggle,
                            showsEnabledSummary: true,
                            toggleSize: 22
                        )
                    }

                    if packageSignalChipData.isEmpty == false {
                        HStack(spacing: 6) {
                            ForEach(packageSignalChipData, id: \.id) { chip in
                                HStack(spacing: 4) {
                                    Image(systemName: chip.systemImage)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(chip.title)
                                        .font(.caption2.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(chip.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(chip.color.opacity(0.10), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 96)
    }

    private var packageSignalChipData: [PackageSignalChipData] {
        guard showsStatusSignals else {
            return []
        }

        var chips: [PackageSignalChipData] = []

        if signals.pendingUpdates > 0 {
            chips.append(
                PackageSignalChipData(
                    id: "updates",
                    title: "\(signals.pendingUpdates) pending",
                    systemImage: "arrow.down.circle",
                    color: .popStatusWarning
                )
            )
        }

        if signals.recoverableMissingComponents > 0 {
            chips.append(
                PackageSignalChipData(
                    id: "rehydrate",
                    title: "Rehydrate \(signals.recoverableMissingComponents)",
                    systemImage: "icloud.and.arrow.down",
                    color: .popSectionBlue
                )
            )
        }

        if signals.missingRequiredComponents > 0 {
            chips.append(
                PackageSignalChipData(
                    id: "missing-required",
                    title: "Required missing \(signals.missingRequiredComponents)",
                    systemImage: "exclamationmark.triangle",
                    color: .popStatusError
                )
            )
        }

        if let checkedAt = signals.lastCheckedUpdatesAt {
            chips.append(
                PackageSignalChipData(
                    id: "checked",
                    title: "Checked \(checkedAt.formatted(date: .omitted, time: .shortened))",
                    systemImage: "clock.arrow.circlepath",
                    color: .popTertiaryLabel
                )
            )
        } else {
            chips.append(
                PackageSignalChipData(
                    id: "check-pending",
                    title: "Check pending",
                    systemImage: "clock.badge.questionmark",
                    color: .popStatusNeutral
                )
            )
        }

        return chips
    }
}

private struct PackageSignalChipData {
    let id: String
    let title: String
    let systemImage: String
    let color: Color
}

struct PackageQuickToggle {
    let apps: [TargetApp]
    let isOn: (TargetApp) -> Bool
    let isPending: (TargetApp) -> Bool
    let onToggle: (TargetApp, Bool) -> Void
}

struct PackageComponentTree: View {
    let components: PackageComponents
    let restoreApp: TargetApp
    let recoverableStubForComponent: (PackageComponent) -> StubbedSkill?
    let isRehydratingSkillID: (String) -> Bool
    let onRehydrateComponent: (PackageComponent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(components.all, id: \.displayKey) { component in
                let stub = recoverableStubForComponent(component)
                PackageComponentLine(
                    component: component,
                    recoverableStub: stub,
                    restoreApp: restoreApp,
                    isRehydrating: stub.map { isRehydratingSkillID($0.id) } ?? false,
                    onRehydrate: {
                        onRehydrateComponent(component)
                    }
                )
            }
        }
    }
}

struct PackageComponentLine: View {
    let component: PackageComponent
    let recoverableStub: StubbedSkill?
    let restoreApp: TargetApp
    let isRehydrating: Bool
    let onRehydrate: () -> Void

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
                if recoverableStub != nil {
                    Button(action: onRehydrate) {
                        if isRehydrating {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.popStatusWarning)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRehydrating)
                    .help("Rehydrate into \(restoreApp.title)")
                } else {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.popStatusNeutral)
                        .help(componentRecoveryHint(component))
                }
            }

            StatusPill(title: component.status.capitalized, color: componentStatusColor(component))
        }
    }
}

struct SkillDetailPane: View {
    let skill: Skill?
    let updateInfo: SkillUpdateInfo?
    let lastCheckedUpdatesAt: Date?
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
                            DetailField(title: "Source Kind", value: skillSourceKindLabel(skill))
                            DetailField(
                                title: "Repository",
                                value: skillRepositoryLabel(skill, fallback: localization.string("Not Tracked"))
                            )
                            DetailField(title: "Update Strategy", value: skillUpdateStrategyLabel(skill))
                        }

                        DetailSection(title: "Lifecycle", accent: PopskillSectionAccent.color(for: 1)) {
                            DetailField(title: "Lifecycle State", value: skillLifecycleStateLabel(skill, updateInfo: updateInfo))
                            DetailField(title: "Pending Updates", value: updateInfo == nil ? "0" : "1")
                            DetailField(
                                title: "Last Checked",
                                value: lastCheckedUpdatesAt?.formatted(date: .abbreviated, time: .shortened)
                                    ?? localization.string("Not Tracked")
                            )
                            DetailField(title: "Update Channel", value: skillUpdateChannelLabel(skill))
                            DetailField(
                                title: "Installed Date",
                                value: formattedOptionalTimestamp(skill.installedAt, fallback: localization.string("Not Tracked"))
                            )
                            DetailField(
                                title: "Last Updated",
                                value: formattedOptionalTimestamp(skill.updatedAt, fallback: localization.string("Not Tracked"))
                            )
                            DetailField(title: "Size", value: skill.sizeBytes.map(byteCountText) ?? localization.string("Not Tracked"))
                            if let contentHash = skill.contentHash, !contentHash.isEmpty {
                                DetailField(title: "Hash", value: String(contentHash.prefix(12)))
                            }
                            if let updateInfo {
                                DetailField(title: "Hash Delta", value: hashDeltaSummary(updateInfo))
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
                                },
                                toggleSize: 24
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
                    apps: TargetApp.quickToggleSupported,
                    isOn: { app in
                        skill.apps.isEnabled(app)
                    },
                    isPending: { app in
                        isToggling(app)
                    },
                    onToggle: onToggle,
                    toggleSize: 24
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
    return "\(shortHash(update.currentHash)) -> \(shortHash(update.remoteHash))"
}

private func packageUpdateHashSummary(_ update: SkillUpdateInfo) -> String {
    "Local \(shortHash(update.currentHash)) · Remote \(shortHash(update.remoteHash))"
}

private func packageUpdateSourceLabel(_ update: SkillUpdateInfo, component: PackageComponent?) -> String {
    if let component {
        if let location = component.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty,
           location.caseInsensitiveCompare(component.id) != .orderedSame {
            return "Component \(component.id) · \(location)"
        }
        return "Component \(component.id)"
    }
    return "Update key \(update.id)"
}

private func shortHash(_ hash: String?, fallback: String = "unknown") -> String {
    guard let hash,
          !hash.isEmpty
    else {
        return fallback
    }
    return String(hash.prefix(8))
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

private func componentRecoveryHint(_ component: PackageComponent) -> String {
    guard !component.installed else {
        return "Installed"
    }

    if component.kind.caseInsensitiveCompare("skill") != .orderedSame {
        return "Rehydrate is available only for skill components."
    }

    if component.isRecoverable {
        return "Recoverable component without a local stub backup."
    }

    return "Missing component that requires reinstall."
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

private func packageCoverageLabel(_ package: CapabilityPackage) -> String {
    guard package.componentCount > 0 else {
        return "0%"
    }
    let ratio = Double(package.installedComponentCount) / Double(package.componentCount)
    return "\(Int((ratio * 100).rounded()))%"
}

private func packageGroupSummaryLabel(_ group: PackageComponentGroupSummary) -> String {
    var segments = ["\(group.installed)/\(group.total) installed"]
    if group.missing > 0 {
        segments.append("\(group.missing) missing")
    }
    if group.recoverableMissing > 0 {
        segments.append("\(group.recoverableMissing) recoverable")
    }
    if group.missingRequired > 0 {
        segments.append("\(group.missingRequired) required missing")
    }
    return segments.joined(separator: " · ")
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

private func packageLifecycleSummaryLabel(_ package: CapabilityPackage) -> String {
    guard let timestamp = package.lastLifecycleTimestamp else {
        return "Lifecycle untracked"
    }
    return "Updated \(formattedTimestamp(timestamp))"
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

private func packageLocalHashStateLabel(_ package: CapabilityPackage, pendingUpdates: [SkillUpdateInfo]) -> String {
    var hashes = Set<String>()
    if let trackedHash = package.trackedContentHash {
        hashes.insert(trackedHash)
    }
    for update in pendingUpdates {
        if let hash = update.currentHash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
            hashes.insert(hash)
        }
    }

    return packageHashStateLabel(
        hashes,
        emptyFallback: "Not Tracked",
        manyTemplate: "%d local hashes"
    )
}

private func packageRemoteHashStateLabel(_ pendingUpdates: [SkillUpdateInfo]) -> String {
    let hashes = Set(
        pendingUpdates
            .map(\.remoteHash)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    )
    return packageHashStateLabel(
        hashes,
        emptyFallback: "No Remote Drift",
        manyTemplate: "%d remote hashes"
    )
}

private func packageHashStateLabel(
    _ hashes: Set<String>,
    emptyFallback: String,
    manyTemplate: String
) -> String {
    let sorted = hashes.sorted()
    guard !sorted.isEmpty else {
        return emptyFallback
    }
    if sorted.count == 1, let hash = sorted.first {
        return shortHash(hash)
    }
    return String(format: manyTemplate, sorted.count)
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

private func skillRepositoryLabel(_ skill: Skill, fallback: String) -> String {
    guard let owner = skill.repoOwner,
          let name = skill.repoName,
          !owner.isEmpty,
          !name.isEmpty
    else {
        return fallback
    }

    return "\(owner)/\(name)"
}

private func skillSourceKindLabel(_ skill: Skill) -> String {
    if skill.repoOwner?.isEmpty == false, skill.repoName?.isEmpty == false {
        return "GitHub"
    }

    if skill.sourceURL != nil {
        return "Remote"
    }

    return "Local"
}

private func skillUpdateStrategyLabel(_ skill: Skill) -> String {
    skill.repoOwner?.isEmpty == false && skill.repoName?.isEmpty == false ? "Git" : "Manual"
}

private func skillUpdateChannelLabel(_ skill: Skill) -> String {
    if let owner = skill.repoOwner,
       let name = skill.repoName,
       !owner.isEmpty,
       !name.isEmpty {
        return "\(owner)/\(name)"
    }

    return "manual"
}

private func skillLifecycleStateLabel(_ skill: Skill, updateInfo: SkillUpdateInfo?) -> String {
    if updateInfo != nil {
        return "Update available"
    }

    if skill.enabledAppCount == 0 {
        return "Inactive"
    }

    if skill.lastLifecycleTimestamp == nil {
        return "Installed (untracked dates)"
    }

    return "Up to date"
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
