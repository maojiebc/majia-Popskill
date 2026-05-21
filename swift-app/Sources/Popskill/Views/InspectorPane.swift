import AppKit
import SwiftUI

/// Right-pane inspector for the matrix. Renders a single
/// `MatrixCapability` — skill / agent / cli / mcp / config. Skill rows show
/// the full set of sections (summary / triggers / apps / deployment /
/// metadata); other kinds gracefully omit the irrelevant pieces (an agent
/// has no SSOT symlink to chart, a CLI has no per-app toggle).
@MainActor
struct InspectorPane: View {
    @Bindable var store: PopskillStore
    let capability: MatrixCapability
    @Environment(\.popskillLocalization) private var localization
    @State private var selectedTab: InspectorTab = .overview
    @State private var linkHealthScanInFlight: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                tabPicker
                if let package = capability.package {
                    packageContent(package)
                } else {
                    capabilityContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .background(Color.popCardBackground.opacity(0.72))
        .onAppear {
            normalizeSelectedTab()
        }
        .onChange(of: capability.id) { _, _ in
            selectedTab = .overview
            normalizeSelectedTab()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            InitialAvatarView(name: capability.name, identifier: capability.id)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(capability.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(2)
                    kindChip
                }
                Text(capability.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
                headerChipStrip
            }
            Spacer()
            Button {
                store.closeInspector()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .frame(width: 22, height: 22)
                    .background(Color.popSubtleFill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(localization.string("matrix.inspector.close"))
        }
    }

    @ViewBuilder
    private var headerChipStrip: some View {
        let chips = inspectorHeaderChips()
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(chips) { chip in
                        Text(chip.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(chip.tint)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(chip.tint.opacity(0.10), in: Capsule())
                    }
                }
            }
            .padding(.top, 3)
        }
    }

    private func inspectorHeaderChips() -> [InspectorHeaderChip] {
        if let package = capability.package {
            return packageHeaderChips(package)
        }
        if let skill = selectedSkill {
            return skillHeaderChips(skill)
        }
        return []
    }

    private func packageHeaderChips(_ package: CapabilityPackage) -> [InspectorHeaderChip] {
        var chips: [InspectorHeaderChip] = []
        for app in [TargetApp.claude, .codex] {
            if let coverage = capability.appCoverage[app], coverage.total > 0 {
                chips.append(InspectorHeaderChip(
                    id: "\(app.rawValue)-coverage",
                    title: "\(app.title) \(coverage.label)",
                    tint: coverage.enabled > 0 ? app.inspectorAccentColor : Color.popTertiaryLabel
                ))
            }
        }
        if let snapshot = package.usageSnapshot(using: store.usageSummary, skills: store.skills), snapshot.hasUsage {
            chips.append(contentsOf: usageHeaderChips(calls: snapshot.usageEvents, tokens: snapshot.totalTokens))
        }
        return chips
    }

    private func skillHeaderChips(_ skill: Skill) -> [InspectorHeaderChip] {
        var chips = TargetApp.quickToggleSupported.map { app in
            let isOn = skill.apps.isEnabled(app)
            let stateKey = isOn ? "matrix.package.component.state.active" : "matrix.package.component.state.off"
            return InspectorHeaderChip(
                id: "\(app.rawValue)-state",
                title: "\(app.title) \(localization.string(stateKey))",
                tint: isOn ? app.inspectorAccentColor : Color.popTertiaryLabel
            )
        }
        if let snapshot = skill.usageSnapshot(using: store.usageSummary), snapshot.hasUsage {
            chips.append(contentsOf: usageHeaderChips(calls: snapshot.usageEvents, tokens: snapshot.totalTokens))
        }
        return chips
    }

    private func usageHeaderChips(calls: Int, tokens: Int64) -> [InspectorHeaderChip] {
        [
            InspectorHeaderChip(
                id: "calls",
                title: localization.string("matrix.inspector.header.calls", UsageDisplayFormatter.compactCount(calls)),
                tint: Color.popSectionGreen
            ),
            InspectorHeaderChip(
                id: "tokens",
                title: localization.string("matrix.inspector.header.tokens", UsageDisplayFormatter.compactTokens(tokens)),
                tint: Color.accentColor
            )
        ]
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(availableTabs) { tab in
                Text(localization.string(tab.titleKey)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .onChange(of: selectedTab) { _, _ in
            normalizeSelectedTab()
        }
    }

    @ViewBuilder
    private func packageContent(_ package: CapabilityPackage) -> some View {
        switch selectedTab {
        case .overview:
            packageSummarySection(package)
            packageActivationSection(package)
            packageActionsSection(package)
            packageCoverageSection
            packageMachineSection(package)
            packageComponentsSection(package)
        case .readme:
            if let skill = readmeSkill(for: package) {
                readmePreviewSection(
                    skill: skill,
                    context: localization.string("matrix.readme.showing", skill.name)
                )
            }
        case .usage:
            packageUsageSection(package)
        case .version:
            if !package.configSchema.isEmpty {
                packageConfigSection(package)
            }
            packageLocalPathsSection(package)
            packageVersionSection(package)
            packageMetadataSection(package)
        case .paths:
            packageLocalPathsSection(package)
        case .sync:
            packageActionsSection(package)
            packageSyncStatusSection(package)
            packageSyncSection(package)
        case .metadata:
            packageMetadataSection(package)
        }
    }

    @ViewBuilder
    private var capabilityContent: some View {
        switch selectedTab {
        case .overview:
            if !primaryDescription.isEmpty {
                summarySection
            }
            if let skill = selectedSkill {
                skillActionsSection(skill)
                skillMachineSection(skill)
                skillSourceSection(skill)
            }
            if let scenarios = capability.triggerScenarios, !scenarios.isEmpty {
                triggerSection(scenarios: scenarios)
            }
            if let skill = selectedSkill {
                skillBundleSection(skill)
            }
            appsSection
        case .readme:
            if let skill = selectedSkill {
                readmePreviewSection(skill: skill)
            }
        case .usage:
            if let skill = selectedSkill {
                skillUsageSection(skill)
            }
        case .version:
            if let skill = selectedSkill {
                skillVersionSection(skill)
            } else {
                metadataSection
            }
        case .paths:
            if let skill = selectedSkill {
                skillPathsSection(skill)
            } else {
                metadataSection
            }
        case .metadata:
            metadataSection
        case .sync:
            metadataSection
        }
    }

    private var availableTabs: [InspectorTab] {
        if let package = capability.package {
            var tabs: [InspectorTab] = [.overview]
            if readmeSkill(for: package) != nil {
                tabs.append(.readme)
            }
            tabs.append(contentsOf: [.usage, .version, .sync])
            return tabs
        }

        var tabs: [InspectorTab] = [.overview]
        if selectedSkill != nil {
            tabs.append(contentsOf: [.readme, .usage, .version, .paths])
        }
        if selectedSkill == nil {
            tabs.append(.metadata)
        }
        return tabs
    }

    private func normalizeSelectedTab() {
        guard !availableTabs.contains(selectedTab) else { return }
        selectedTab = .overview
    }

    private func packageActionsSection(_ package: CapabilityPackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.actions", accent: .accentColor)
            LazyVGrid(columns: Self.actionGridColumns, alignment: .leading, spacing: 8) {
                inspectorActionButton(
                    titleKey: "matrix.package.action.rescanUsage",
                    systemImage: "chart.bar.doc.horizontal",
                    inFlight: store.usageScanInFlight,
                    disabled: store.usageScanInFlight
                ) {
                    Task { await store.refreshUsageScan() }
                }

                inspectorActionButton(
                    titleKey: "matrix.package.action.checkUpdates",
                    systemImage: "arrow.clockwise",
                    inFlight: store.updatesRefreshInFlight,
                    disabled: store.updatesRefreshInFlight
                ) {
                    Task { await store.refreshUpdates(force: true) }
                }

                sourceAction(for: package)

                inspectorActionButton(
                    titleKey: "matrix.package.action.revealInFinder",
                    systemImage: "folder",
                    disabled: firstRevealableSkillURL(for: package) == nil
                ) {
                    if let url = firstRevealableSkillURL(for: package) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sourceAction(for package: CapabilityPackage) -> some View {
        if let url = package.sourceURL {
            Link(destination: url) {
                inspectorActionLabel(
                    titleKey: "matrix.package.action.openSource",
                    systemImage: "arrow.up.right.square"
                )
            }
            .buttonStyle(.plain)
        } else {
            inspectorActionButton(
                titleKey: "matrix.package.action.openSource",
                systemImage: "arrow.up.right.square",
                disabled: true
            ) {}
        }
    }

    private func skillActionsSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.actions", accent: .accentColor)
            LazyVGrid(columns: Self.actionGridColumns, alignment: .leading, spacing: 8) {
                inspectorActionButton(
                    titleKey: "matrix.skill.action.openReadme",
                    systemImage: "square.and.pencil",
                    disabled: skill.markdownURL == nil
                ) {
                    if let url = skill.markdownURL {
                        NSWorkspace.shared.open(url)
                    }
                }

                inspectorActionButton(
                    titleKey: "matrix.skill.action.checkUpdates",
                    systemImage: "arrow.clockwise",
                    inFlight: store.updatesRefreshInFlight,
                    disabled: store.updatesRefreshInFlight
                ) {
                    Task { await store.refreshUpdates(force: true) }
                }

                sourceAction(for: skill)

                inspectorActionButton(
                    titleKey: "matrix.skill.action.revealInFinder",
                    systemImage: "folder",
                    disabled: !FileManager.default.fileExists(atPath: skill.localStoreURL.path)
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([skill.localStoreURL])
                }
            }
        }
    }

    @ViewBuilder
    private func skillMachineSection(_ skill: Skill) -> some View {
        let metrics = skillMachineMetrics(skill)
        if !metrics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(title: "matrix.inspector.section.machine", accent: .popSectionGreen)
                LazyVGrid(columns: Self.machineMetricColumns, alignment: .leading, spacing: 8) {
                    ForEach(metrics) { metric in
                        machineMetricCard(metric)
                    }
                }
            }
        }
    }

    private func skillMachineMetrics(_ skill: Skill) -> [InspectorMachineMetric] {
        var metrics: [InspectorMachineMetric] = []
        let snapshot = skill.usageSnapshot(using: store.usageSummary)

        if let installedAt = skill.installedAt, installedAt > 0 {
            metrics.append(InspectorMachineMetric(
                id: "installed",
                title: localization.string("matrix.machine.firstActivated"),
                value: Self.formatTimestamp(installedAt),
                tint: Color.popSectionPurple
            ))
        }
        if let lastUsedAt = snapshot?.lastUsedAt {
            metrics.append(InspectorMachineMetric(
                id: "last-used",
                title: localization.string("matrix.machine.lastUsed"),
                value: Self.relativeFormatter.localizedString(for: lastUsedAt, relativeTo: Date()),
                tint: Color.popSectionGreen
            ))
        }
        if let snapshot, snapshot.hasUsage {
            metrics.append(InspectorMachineMetric(
                id: "tokens",
                title: localization.string("matrix.machine.tokens"),
                value: UsageDisplayFormatter.compactTokens(snapshot.totalTokens),
                tint: Color.accentColor
            ))
            metrics.append(InspectorMachineMetric(
                id: "calls",
                title: localization.string("matrix.machine.calls"),
                value: UsageDisplayFormatter.compactCount(snapshot.usageEvents),
                tint: Color.popLabel
            ))
        }
        if let size = skill.sizeBytes, size > 0 {
            metrics.append(InspectorMachineMetric(
                id: "size",
                title: localization.string("matrix.machine.size"),
                value: Self.formatBytes(size),
                tint: Color.popSecondaryLabel
            ))
        }

        return metrics
    }

    private func machineMetricCard(_ metric: InspectorMachineMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.popSecondaryLabel)
                .lineLimit(1)
            Text(metric.value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(metric.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(metric.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func skillSourceSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.source", accent: .popSectionPurple)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(skillSourceFacts(skill)) { fact in
                    sourceFactRow(fact)
                }
            }
        }
    }

    private func skillSourceFacts(_ skill: Skill) -> [InspectorSourceFact] {
        var facts: [InspectorSourceFact] = [
            InspectorSourceFact(
                id: "repository",
                title: localization.string("matrix.source.repository"),
                value: skill.sourceLabel,
                icon: "chevron.left.forwardslash.chevron.right"
            ),
            InspectorSourceFact(
                id: "directory",
                title: localization.string("matrix.source.directory"),
                value: skill.directory,
                icon: "folder"
            ),
            InspectorSourceFact(
                id: "local-store",
                title: localization.string("matrix.source.localStore"),
                value: skill.localStoreURL.path.abbreviatingWithTilde,
                icon: "externaldrive"
            )
        ]
        if let sourceType = skill.sourceType, !sourceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            facts.append(InspectorSourceFact(
                id: "source-type",
                title: localization.string("matrix.source.type"),
                value: sourceType,
                icon: "tag"
            ))
        }
        if let author = skill.manifest?.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            facts.append(InspectorSourceFact(
                id: "author",
                title: localization.string("matrix.source.author"),
                value: author,
                icon: "person"
            ))
        }
        if let license = skill.manifest?.license?.trimmingCharacters(in: .whitespacesAndNewlines), !license.isEmpty {
            facts.append(InspectorSourceFact(
                id: "license",
                title: localization.string("matrix.source.license"),
                value: license,
                icon: "doc.plaintext"
            ))
        }
        if let homepageURL = skill.manifest?.homepageURL {
            facts.append(InspectorSourceFact(
                id: "homepage",
                title: localization.string("matrix.source.homepage"),
                value: homepageURL.absoluteString,
                icon: "arrow.up.right.square",
                url: homepageURL
            ))
        }
        if let manifest = skill.manifest,
           let requiredTools = manifest.requiredToolsLabel(
               availableLabel: localization.string("matrix.skill.manifest.requires.available"),
               missingLabel: localization.string("matrix.skill.manifest.requires.missing")
           ) {
            facts.append(InspectorSourceFact(
                id: "requires",
                title: localization.string("matrix.source.requires"),
                value: requiredTools,
                icon: manifest.hasMissingRequiredTools ? "exclamationmark.triangle.fill" : "checkmark.seal"
            ))
        }
        if let markdownURL = skill.markdownURL {
            facts.append(InspectorSourceFact(
                id: "readme",
                title: localization.string("matrix.source.readme"),
                value: markdownURL.path.abbreviatingWithTilde,
                icon: "doc.text"
            ))
        }
        return facts
    }

    private func sourceFactRow(_ fact: InspectorSourceFact) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: fact.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.popSecondaryLabel)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(fact.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                if let url = fact.url {
                    Link(fact.value, destination: url)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text(fact.value)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(8)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func sourceAction(for skill: Skill) -> some View {
        if let url = skill.sourceURL {
            Link(destination: url) {
                inspectorActionLabel(
                    titleKey: "matrix.skill.action.openSource",
                    systemImage: "arrow.up.right.square"
                )
            }
            .buttonStyle(.plain)
        } else {
            inspectorActionButton(
                titleKey: "matrix.skill.action.openSource",
                systemImage: "arrow.up.right.square",
                disabled: true
            ) {}
        }
    }

    private func inspectorActionButton(
        titleKey: String,
        systemImage: String,
        inFlight: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            inspectorActionLabel(titleKey: titleKey, systemImage: systemImage, inFlight: inFlight)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.52 : 1)
    }

    private func inspectorActionLabel(titleKey: String, systemImage: String, inFlight: Bool = false) -> some View {
        HStack(spacing: 7) {
            if inFlight {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 14)
            }
            Text(localization.string(titleKey))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.popLabel)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var kindChip: some View {
        HStack(spacing: 3) {
            Image(systemName: capability.kind.symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(localization.string(capability.kind.titleKey).uppercased())
                .font(.system(size: 9.5, weight: .bold))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    // MARK: Sections

    private var primaryDescription: String {
        capability.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var selectedSkill: Skill? {
        guard let skillID = capability.underlyingSkillID else {
            return nil
        }
        return store.skills.first { $0.id == skillID }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading(title: "matrix.inspector.section.summary")
            Text(primaryDescription)
                .font(.callout)
                .foregroundStyle(Color.popLabel)
                .textSelection(.enabled)
        }
    }

    private func readmePreviewSection(skill: Skill, context: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionHeading(title: "matrix.inspector.section.readme", accent: .popSectionPurple)
                Spacer()
                Button {
                    Task { await store.loadReadmePreview(for: skill, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.popSecondaryLabel)
                .help(localization.string("matrix.readme.reload"))
            }

            if let context {
                Text(context)
                    .font(.caption2)
                    .foregroundStyle(Color.popTertiaryLabel)
            }

            readmePreviewBody(for: skill)
        }
        .task(id: skill.id) {
            await store.loadReadmePreview(for: skill)
        }
    }

    @ViewBuilder
    private func readmePreviewBody(for skill: Skill) -> some View {
        switch store.readmePreviewState(for: skill) {
        case .loaded(let preview):
            VStack(alignment: .leading, spacing: 8) {
                Text(preview.excerpt)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color.popLabel)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(preview.url)
                    } label: {
                        Label(localization.string("matrix.readme.openFile"), systemImage: "doc.text")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)

                    if preview.truncated {
                        Text(localization.string("matrix.readme.truncated"))
                            .font(.caption2)
                            .foregroundStyle(Color.popTertiaryLabel)
                    }
                }
            }
            .padding(10)
            .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .failed(let message):
            Text(localization.string("matrix.readme.error", message))
                .font(.caption)
                .foregroundStyle(Color.popTertiaryLabel)
        case .loading:
            readmeLoadingRow
        case .none:
            readmeLoadingRow
        }
    }

    private var readmeLoadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(localization.string("matrix.readme.loading"))
                .font(.caption)
                .foregroundStyle(Color.popSecondaryLabel)
        }
    }

    private func skillUsageSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.usage", accent: .accentColor)
            usageWindowCaption

            if store.usageScanInFlight {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    LocalizedText("matrix.package.usage.scanning")
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
            } else if let snapshot = skill.usageSnapshot(using: store.usageSummary) {
                if snapshot.hasUsage {
                    HStack(spacing: 10) {
                        packageUsageMetric(
                            titleKey: "matrix.package.usage.tokens",
                            value: Self.formatTokens(snapshot.totalTokens),
                            tint: .accentColor
                        )
                        packageUsageMetric(
                            titleKey: "matrix.package.usage.calls",
                            value: "\(snapshot.usageEvents)",
                            tint: .popSectionGreen
                        )
                    }
                    if let lastUsedAt = snapshot.lastUsedAt {
                        Text(localization.string("matrix.package.usage.lastUsed", Self.relativeFormatter.localizedString(for: lastUsedAt, relativeTo: Date())))
                            .font(.caption2)
                            .foregroundStyle(Color.popTertiaryLabel)
                    }
                    if !snapshot.dailyStats.isEmpty {
                        usageTrend(snapshot.dailyStats)
                    }
                } else {
                    Text(localization.string("matrix.skill.usage.empty"))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    Text(localization.string("matrix.skill.usage.notScanned"))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                    Spacer(minLength: 8)
                    Button {
                        Task { await store.refreshUsageScan() }
                    } label: {
                        Label(localization.string("insights.refresh"), systemImage: "chart.bar.doc.horizontal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }

    private func packageSummarySection(_ package: CapabilityPackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.summary", accent: .popSectionPurple)
            Text(package.summary)
                .font(.callout)
                .foregroundStyle(Color.popLabel)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                packagePill(
                    localization.string(package.health.inspectorTitleKey),
                    color: package.health.inspectorColor
                )
                packagePill(
                    PackageComponentCompositionFormatter.composition(for: package, localization: localization),
                    color: Color.popSecondaryLabel
                )
            }
        }
    }

    private var packageCoverageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.coverage", accent: .popSectionPurple)
            HStack(spacing: 10) {
                packageCoverageCard(for: .claude)
                packageCoverageCard(for: .codex)
            }
        }
    }

    private func packageCoverageCard(for app: TargetApp) -> some View {
        let coverage = capability.appCoverage[app] ?? CapabilityAppCoverage(enabled: 0, total: 0)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: app.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(app.title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Color.popSecondaryLabel)
            Text(coverage.label)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(coverage.enabled > 0 ? app.inspectorAccentColor : Color.popTertiaryLabel)
            ProgressView(value: Double(coverage.enabled), total: Double(max(coverage.total, 1)))
                .tint(app.inspectorAccentColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func packageMachineSection(_ package: CapabilityPackage) -> some View {
        let metrics = packageMachineMetrics(package)
        if !metrics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(title: "matrix.inspector.section.machine", accent: .popSectionGreen)
                LazyVGrid(columns: Self.machineMetricColumns, alignment: .leading, spacing: 8) {
                    ForEach(metrics) { metric in
                        machineMetricCard(metric)
                    }
                }
            }
        }
    }

    private func packageMachineMetrics(_ package: CapabilityPackage) -> [InspectorMachineMetric] {
        var metrics: [InspectorMachineMetric] = []
        let snapshot = package.usageSnapshot(using: store.usageSummary, skills: store.skills)

        if let snapshot, snapshot.hasUsage {
            metrics.append(InspectorMachineMetric(
                id: "tokens",
                title: localization.string("matrix.machine.tokens"),
                value: UsageDisplayFormatter.compactTokens(snapshot.totalTokens),
                tint: Color.accentColor
            ))
            metrics.append(InspectorMachineMetric(
                id: "calls",
                title: localization.string("matrix.machine.calls"),
                value: UsageDisplayFormatter.compactCount(snapshot.usageEvents),
                tint: Color.popLabel
            ))
            if let topComponent = snapshot.componentStats.first {
                metrics.append(InspectorMachineMetric(
                    id: "top-component",
                    title: localization.string("matrix.machine.topComponent"),
                    value: topComponent.componentName,
                    tint: Color.popSectionGreen
                ))
            }
        }

        if let size = package.installedSizeBytes(in: store.skills) {
            metrics.append(InspectorMachineMetric(
                id: "size",
                title: localization.string("matrix.machine.size"),
                value: Self.formatBytes(size),
                tint: Color.popSecondaryLabel
            ))
        }

        return metrics
    }

    private func packageActivationSection(_ package: CapabilityPackage) -> some View {
        let matchedSkills = package.matchingInstalledSkills(in: store.skills)
        let claudeTargets = package.installedSkillsRequiringEnablement(for: .claude, in: store.skills)
        let codexTargets = package.installedSkillsRequiringEnablement(for: .codex, in: store.skills)

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.activation", accent: .accentColor)
            LazyVGrid(columns: Self.actionGridColumns, alignment: .leading, spacing: 8) {
                packageActivationButton(app: .claude, package: package, targets: claudeTargets)
                packageActivationButton(app: .codex, package: package, targets: codexTargets)
            }
            if matchedSkills.isEmpty {
                Text(localization.string("matrix.package.activation.empty"))
                    .font(.caption2)
                    .foregroundStyle(Color.popTertiaryLabel)
            } else if claudeTargets.isEmpty && codexTargets.isEmpty {
                Text(localization.string("matrix.package.activation.complete"))
                    .font(.caption2)
                    .foregroundStyle(Color.popTertiaryLabel)
            } else {
                Text(localization.string("matrix.package.activation.remaining", claudeTargets.count, codexTargets.count))
                    .font(.caption2)
                    .foregroundStyle(Color.popTertiaryLabel)
            }
        }
    }

    private func packageActivationButton(app: TargetApp, package: CapabilityPackage, targets: [Skill]) -> some View {
        let inFlight = packageActivationInFlight(for: targets, app: app)
        return inspectorActionButton(
            titleKey: packageActivationTitleKey(for: app),
            systemImage: app.symbolName,
            inFlight: inFlight,
            disabled: targets.isEmpty || inFlight
        ) {
            Task { await activatePackage(package, app: app) }
        }
    }

    private func packageActivationTitleKey(for app: TargetApp) -> String {
        switch app {
        case .claude: return "matrix.package.action.activateClaude"
        case .codex: return "matrix.package.action.activateCodex"
        default: return "matrix.package.action.activateApp"
        }
    }

    private func packageComponentsSection(_ package: CapabilityPackage) -> some View {
        let usageStatsByComponentID = Dictionary(
            uniqueKeysWithValues: package
                .usageSnapshot(using: store.usageSummary, skills: store.skills)?
                .componentStats
                .map { ($0.componentID, $0) } ?? []
        )

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "matrix.inspector.section.components", accent: .popSectionPurple)
            ForEach(package.componentGroupSummaries) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.popLabel)
                        Text("\(group.installed)/\(group.total)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.popSecondaryLabel)
                        if group.missingRequired > 0 {
                            Text(localization.string("matrix.package.missingRequired", group.missingRequired))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.popStatusError)
                        }
                        Spacer()
                    }
                    ForEach(components(in: group.kind, package: package), id: \.displayKey) { component in
                        packageComponentDetailRow(
                            component,
                            package: package,
                            usageStat: usageStatsByComponentID[component.id]
                        )
                    }
                }
                .padding(8)
                .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func packageUsageSection(_ package: CapabilityPackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.usage", accent: .accentColor)
            usageWindowCaption

            if store.usageScanInFlight {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    LocalizedText("matrix.package.usage.scanning")
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
            } else if let snapshot = package.usageSnapshot(using: store.usageSummary, skills: store.skills) {
                if snapshot.hasUsage {
                    HStack(spacing: 10) {
                        packageUsageMetric(
                            titleKey: "matrix.package.usage.tokens",
                            value: Self.formatTokens(snapshot.totalTokens),
                            tint: .accentColor
                        )
                        packageUsageMetric(
                            titleKey: "matrix.package.usage.calls",
                            value: "\(snapshot.usageEvents)",
                            tint: .popSectionGreen
                        )
                    }
                    if let lastUsedAt = snapshot.lastUsedAt {
                        Text(localization.string("matrix.package.usage.lastUsed", Self.relativeFormatter.localizedString(for: lastUsedAt, relativeTo: Date())))
                            .font(.caption2)
                            .foregroundStyle(Color.popTertiaryLabel)
                    }
                    if !snapshot.dailyStats.isEmpty {
                        usageTrend(snapshot.dailyStats)
                    }
                    if !snapshot.componentStats.isEmpty {
                        packageUsageBreakdown(snapshot.componentStats)
                    }
                } else {
                    Text(localization.string("matrix.package.usage.empty", snapshot.matchedSkillCount))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    Text(localization.string("matrix.package.usage.notScanned"))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                    Spacer(minLength: 8)
                    Button {
                        Task { await store.refreshUsageScan() }
                    } label: {
                        Label(localization.string("insights.refresh"), systemImage: "chart.bar.doc.horizontal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }

    private func usageTrend(_ stats: [UsageBucketStat]) -> some View {
        let buckets = usageTrendBuckets(stats, window: store.usageSummary?.recent30Days)
        let peak = buckets.max { lhs, rhs in
            if lhs.usageEvents == rhs.usageEvents {
                return lhs.dayStart < rhs.dayStart
            }
            return lhs.usageEvents < rhs.usageEvents
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LocalizedText("matrix.package.usage.trend")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                Spacer(minLength: 8)
                if let peak, peak.usageEvents > 0 {
                    Text(localization.string(
                        "matrix.package.usage.peak",
                        UsageDisplayFormatter.compactCount(peak.usageEvents),
                        Self.usageDayFormatter.string(from: peak.dayStart)
                    ))
                    .font(.caption2)
                    .foregroundStyle(Color.popTertiaryLabel)
                }
            }

            UsageTrendBars(buckets: buckets, tint: .accentColor)

            if let first = buckets.first?.dayStart, let last = buckets.last?.dayStart {
                HStack {
                    Text(Self.usageDayFormatter.string(from: first))
                    Spacer()
                    Text(Self.usageDayFormatter.string(from: last))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.popTertiaryLabel)
            }
        }
        .padding(9)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func usageTrendBuckets(_ stats: [UsageBucketStat], window: UsageWindowSummary?) -> [UsageBucketStat] {
        let indexed = Dictionary(uniqueKeysWithValues: stats.map {
            (Self.usageCalendar.startOfDay(for: $0.dayStart), $0)
        })

        guard let window else {
            return stats.sorted { $0.dayStart < $1.dayStart }
        }

        let endDay = Self.usageCalendar.startOfDay(for: window.endedAt)
        let startDay = Self.usageCalendar.date(
            byAdding: .day,
            value: -(max(1, window.days) - 1),
            to: endDay
        ) ?? endDay

        return (0..<max(1, window.days)).compactMap { offset in
            guard let day = Self.usageCalendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }
            return indexed[day] ?? UsageBucketStat(
                dayStart: day,
                usageEvents: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            )
        }
    }

    private func packageUsageBreakdown(_ stats: [PackageComponentUsageStat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText("matrix.package.usage.topComponents")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.popSecondaryLabel)

            ForEach(stats.prefix(5)) { stat in
                packageUsageComponentRow(stat)
            }
        }
    }

    private func packageUsageComponentRow(_ stat: PackageComponentUsageStat) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: stat.componentKind.usageKindSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stat.installed ? Color.popStatusOK : Color.popTertiaryLabel)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(stat.componentName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.popLabel)
                    .lineLimit(1)
                Text(stat.componentKind.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.popTertiaryLabel)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(localization.string("matrix.package.usage.componentCalls", stat.usageEvents))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.popLabel)
                    .monospacedDigit()
                Text(Self.formatTokens(stat.totalTokens))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.popSecondaryLabel)
            }
        }
        .padding(8)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func packageUsageMetric(titleKey: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LocalizedText(titleKey)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.popSecondaryLabel)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var usageWindowCaption: some View {
        if let window = store.usageSummary?.recent30Days {
            Text(localization.string("matrix.package.usage.window", window.days))
                .font(.caption2)
                .foregroundStyle(Color.popTertiaryLabel)
        }
    }

    private func components(in kind: String, package: CapabilityPackage) -> [PackageComponent] {
        switch kind {
        case "skill": return package.components.skills
        case "cli": return package.components.cli
        case "mcp": return package.components.mcp
        case "agent": return package.components.agents
        default: return []
        }
    }

    private func packageComponentDetailRow(
        _ component: PackageComponent,
        package: CapabilityPackage,
        usageStat: PackageComponentUsageStat?
    ) -> some View {
        let matchedSkill = package.matchingInstalledSkill(for: component, in: store.skills)
        let versionLabel = package.componentVersionLabel(for: component, in: store.skills)

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: component.inspectorKindSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(component.installed ? Color.popStatusOK : Color.popTertiaryLabel)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(component.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.popLabel)
                    Text(component.kind.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.popSecondaryLabel)
                }
                Text(component.location ?? component.id)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 4) {
                    packageComponentAppStateBadge(
                        component.appState(for: .claude, matching: matchedSkill),
                        app: .claude
                    )
                    packageComponentAppStateBadge(
                        component.appState(for: .codex, matching: matchedSkill),
                        app: .codex
                    )
                }
                HStack(spacing: 5) {
                    Text(component.status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(component.installed ? Color.popStatusOK : Color.popStatusWarning)
                    Text(versionLabel ?? "—")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(versionLabel == nil ? Color.popTertiaryLabel : Color.accentColor)
                    Text(localization.string(
                        "matrix.package.component.calls",
                        usageStat.map { UsageDisplayFormatter.compactCount($0.usageEvents) } ?? "—"
                    ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.popSecondaryLabel)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func packageComponentAppStateBadge(_ state: PackageComponentAppState, app: TargetApp) -> some View {
        let color = packageComponentAppStateColor(state)
        return HStack(spacing: 3) {
            Text(packageComponentAppShortLabel(app))
                .font(.system(size: 8.5, weight: .bold))
            Text(localization.string(packageComponentAppStateTitleKey(state)))
                .font(.system(size: 9.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.10), in: Capsule())
        .help(localization.string(packageComponentAppStateHelpKey(state), app.title))
    }

    private func packageComponentAppShortLabel(_ app: TargetApp) -> String {
        switch app {
        case .claude: return "CC"
        case .codex: return "CDX"
        default: return app.title.uppercased()
        }
    }

    private func packageComponentAppStateTitleKey(_ state: PackageComponentAppState) -> String {
        switch state {
        case .active: return "matrix.package.component.state.active"
        case .stub: return "matrix.package.component.state.stub"
        case .off: return "matrix.package.component.state.off"
        case .unsupported: return "matrix.package.component.state.unsupported"
        }
    }

    private func packageComponentAppStateHelpKey(_ state: PackageComponentAppState) -> String {
        switch state {
        case .active: return "matrix.package.component.enabledHelp"
        case .stub: return "matrix.package.component.partialHelp"
        case .off: return "matrix.package.component.offHelp"
        case .unsupported: return "matrix.package.component.unsupportedHelp"
        }
    }

    private func packageComponentAppStateColor(_ state: PackageComponentAppState) -> Color {
        switch state {
        case .active: return Color.popStatusOK
        case .stub: return Color.popStatusWarning
        case .off: return Color.popTertiaryLabel
        case .unsupported: return Color.popSecondaryLabel
        }
    }

    private func packageConfigSection(_ package: CapabilityPackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.config", accent: .popSectionPurple)
            ForEach(package.configSchema) { field in
                HStack(spacing: 8) {
                    Text(field.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.popLabel)
                    if field.required {
                        Text(localization.string("matrix.package.component.required"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.popStatusWarning)
                    }
                    Spacer()
                    Text(field.secret ? localization.string("matrix.package.config.secret") : field.storage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.popSecondaryLabel)
                }
                .padding(8)
                .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func packageLocalPathsSection(_ package: CapabilityPackage) -> some View {
        let matchedSkills = package.matchingInstalledSkills(in: store.skills)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.paths")
            if matchedSkills.isEmpty {
                Text(localization.string("matrix.package.paths.empty"))
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
            } else {
                ForEach(matchedSkills.prefix(8), id: \.id) { skill in
                    packagePathRow(skill)
                }
                if matchedSkills.count > 8 {
                    Text(localization.string("matrix.package.paths.more", matchedSkills.count - 8))
                        .font(.caption2)
                        .foregroundStyle(Color.popTertiaryLabel)
                }
            }
        }
    }

    private func packagePathRow(_ skill: Skill) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(skill.markdownURL == nil ? Color.popTertiaryLabel : Color.popSecondaryLabel)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.popLabel)
                Text(skill.localStoreURL.path.abbreviatingWithTilde)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if skill.markdownURL != nil {
                Text("SKILL.md")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.popStatusOK)
            }
            if FileManager.default.fileExists(atPath: skill.localStoreURL.path) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([skill.localStoreURL])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.popSecondaryLabel)
                .help(localization.string("matrix.row.menu.revealInFinder"))
            }
        }
        .padding(8)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func packageVersionSection(_ package: CapabilityPackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.version")
            VStack(alignment: .leading, spacing: 6) {
                metaRow(label: localization.string("matrix.package.version.strategy"), value: package.source.updateStrategy)
                if let branch = package.source.repoBranch, !branch.isEmpty {
                    metaRow(label: localization.string("matrix.package.version.branch"), value: branch)
                }
                if let installedAt = package.lifecycle?.installedAt, installedAt > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.installedAt"), value: Self.formatTimestamp(installedAt))
                }
                if let updatedAt = package.lifecycle?.updatedAt, updatedAt > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.updatedAt"), value: Self.formatTimestamp(updatedAt))
                }
                metaRow(
                    label: localization.string("matrix.package.version.hash"),
                    value: package.trackedContentHash.map(Self.shortHash) ?? localization.string("matrix.package.version.untracked")
                )
            }
            packageComponentVersionsSection(package)
        }
    }

    @ViewBuilder
    private func packageComponentVersionsSection(_ package: CapabilityPackage) -> some View {
        let summaries = package.componentVersionSummaries(in: store.skills)
        if !summaries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                LocalizedText("matrix.package.version.components")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                ForEach(summaries.prefix(8)) { summary in
                    packageComponentVersionRow(summary)
                }
                if summaries.count > 8 {
                    Text(localization.string("matrix.package.paths.more", summaries.count - 8))
                        .font(.caption2)
                        .foregroundStyle(Color.popTertiaryLabel)
                }
            }
            .padding(.top, 4)
        }
    }

    private func packageComponentVersionRow(_ summary: PackageComponentVersionSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: summary.kind.usageKindSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(summary.versionLabel == nil ? Color.popTertiaryLabel : Color.popSecondaryLabel)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.popLabel)
                    .lineLimit(1)
                Text(summary.status)
                    .font(.caption2)
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer(minLength: 8)
            Text(summary.versionLabel ?? localization.string("matrix.package.version.untracked"))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(summary.versionLabel == nil ? Color.popTertiaryLabel : Color.accentColor)
        }
        .padding(8)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func skillVersionSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.version")
            VStack(alignment: .leading, spacing: 6) {
                if let version = skill.manifest?.semanticVersion {
                    metaRow(
                        label: localization.string("matrix.skill.manifest.version"),
                        value: MatrixVersionFormatter.semanticVersion(version) ?? version
                    )
                }
                if let author = skill.manifest?.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                    metaRow(label: localization.string("matrix.skill.manifest.author"), value: author)
                }
                if let license = skill.manifest?.license?.trimmingCharacters(in: .whitespacesAndNewlines), !license.isEmpty {
                    metaRow(label: localization.string("matrix.skill.manifest.license"), value: license)
                }
                if let manifest = skill.manifest,
                   let requiredTools = manifest.requiredToolsLabel(
                       availableLabel: localization.string("matrix.skill.manifest.requires.available"),
                       missingLabel: localization.string("matrix.skill.manifest.requires.missing")
                   ) {
                    metaRow(label: localization.string("matrix.skill.manifest.requires"), value: requiredTools)
                }
                metaRow(
                    label: localization.string("matrix.package.version.hash"),
                    value: skill.contentHash.map(Self.shortHash) ?? localization.string("matrix.package.version.untracked")
                )
                if let installedAt = skill.installedAt, installedAt > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.installedAt"), value: Self.formatTimestamp(installedAt))
                }
                if let updatedAt = skill.updatedAt, updatedAt > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.updatedAt"), value: Self.formatTimestamp(updatedAt))
                }
                if let size = skill.sizeBytes, size > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.size"), value: Self.formatBytes(size))
                }
                if let source = skill.sourceType, !source.isEmpty {
                    metaRow(label: localization.string("matrix.inspector.meta.sourceType"), value: source)
                }
            }
            if let url = skill.sourceURL {
                Link(destination: url) {
                    Label(localization.string("matrix.inspector.meta.openSource"), systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func packageSyncSection(_ package: CapabilityPackage) -> some View {
        let pendingUpdates = packagePendingUpdates(package)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.package.sync.upstream")
            HStack(spacing: 8) {
                syncStatusPill(for: pendingUpdates)
                if store.updatesRefreshInFlight {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(localization.string("matrix.package.sync.checking"))
                    }
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
                } else if let lastCheckedAt = store.lastUpdatesRefreshAt {
                    Text(localization.string("matrix.package.sync.checked", Self.relativeFormatter.localizedString(for: lastCheckedAt, relativeTo: Date())))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                } else {
                    Text(localization.string("matrix.package.sync.notChecked"))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
            }

            if pendingUpdates.isEmpty {
                Text(localization.string("matrix.package.sync.clean"))
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pendingUpdates.prefix(4)) { update in
                        packageSyncUpdateRow(update)
                    }
                    if pendingUpdates.count > 4 {
                        Text(localization.string("matrix.package.sync.more", pendingUpdates.count - 4))
                            .font(.caption2)
                            .foregroundStyle(Color.popTertiaryLabel)
                    }
                }
            }
        }
    }

    private func packageSyncStatusSection(_ package: CapabilityPackage) -> some View {
        let snapshot = package.linkHealthSnapshot(using: store.linkHealth, skills: store.skills)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.package.sync.status", accent: .popSectionGreen)
            LazyVGrid(columns: Self.syncFactColumns, alignment: .leading, spacing: 8) {
                syncFactCard(
                    titleKey: "matrix.package.sync.source",
                    value: package.source.location,
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    tint: Color.accentColor
                )
                syncFactCard(
                    titleKey: "matrix.package.sync.provider",
                    value: syncProviderLabel,
                    systemImage: syncProviderSymbol,
                    tint: Color.popSectionPurple
                )
                syncFactCard(
                    titleKey: "matrix.package.sync.lastSync",
                    value: lastSyncLabel,
                    systemImage: "clock.arrow.circlepath",
                    tint: Color.popSecondaryLabel
                )
                syncFactCard(
                    titleKey: "matrix.package.sync.linkHealth",
                    value: packageLinkHealthLabel(snapshot),
                    systemImage: packageLinkHealthSymbol(snapshot),
                    tint: packageLinkHealthTint(snapshot)
                )
            }

            packageLinkHealthRows(snapshot)
        }
    }

    private var syncProviderLabel: String {
        if let provider = SyncProvider(rawValue: store.lastSyncProvider) {
            return localization.string(provider.titleKey)
        }
        return store.lastSyncProvider
    }

    private var syncProviderSymbol: String {
        SyncProvider(rawValue: store.lastSyncProvider)?.symbol ?? "arrow.triangle.2.circlepath"
    }

    private var lastSyncLabel: String {
        if let lastSyncAt = store.lastSyncAt {
            return Self.relativeFormatter.localizedString(for: lastSyncAt, relativeTo: Date())
        }
        return localization.string("sidebar.sync.never")
    }

    private func packageLinkHealthLabel(_ snapshot: PackageLinkHealthSnapshot?) -> String {
        guard let snapshot else {
            return localization.string("matrix.package.sync.linkHealthNotScanned")
        }
        return localization.string(
            "matrix.package.sync.linkHealthSummary",
            snapshot.okCount,
            snapshot.brokenCount,
            snapshot.inactiveCount
        )
    }

    private func packageLinkHealthSymbol(_ snapshot: PackageLinkHealthSnapshot?) -> String {
        guard let snapshot else { return "checkmark.shield" }
        if snapshot.brokenCount > 0 { return "exclamationmark.triangle.fill" }
        if snapshot.okCount > 0 { return "link" }
        return "circle.dashed"
    }

    private func packageLinkHealthTint(_ snapshot: PackageLinkHealthSnapshot?) -> Color {
        guard let snapshot else { return Color.popTertiaryLabel }
        if snapshot.brokenCount > 0 { return Color.popStatusError }
        if snapshot.okCount > 0 { return Color.popStatusOK }
        return Color.popTertiaryLabel
    }

    private func syncFactCard(titleKey: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                LocalizedText(titleKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.popLabel)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 4)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func packageLinkHealthRows(_ snapshot: PackageLinkHealthSnapshot?) -> some View {
        if let snapshot {
            if snapshot.rows.isEmpty {
                Text(localization.string("matrix.package.sync.linkHealthEmpty"))
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.rows.prefix(4), id: \.skillId) { row in
                        packageLinkHealthRow(row)
                    }
                    if snapshot.rows.count > 4 {
                        Text(localization.string("matrix.package.paths.more", snapshot.rows.count - 4))
                            .font(.caption2)
                            .foregroundStyle(Color.popTertiaryLabel)
                    }
                }
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                Text(localization.string("matrix.package.sync.linkHealthNotScannedDetail"))
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
                Spacer(minLength: 8)
                Button {
                    Task { await refreshPackageLinkHealth() }
                } label: {
                    if linkHealthScanInFlight {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label(localization.string("health.empty.runScan"), systemImage: "play.circle")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(linkHealthScanInFlight)
            }
        }
    }

    private func packageLinkHealthRow(_ row: LinkHealthRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.deployment?.hasBrokenLink == true ? "exclamationmark.triangle.fill" : "link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(row.deployment?.hasBrokenLink == true ? Color.popStatusError : Color.popStatusOK)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.skillName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.popLabel)
                    .lineLimit(1)
                Text(row.deployment?.ssotPath.abbreviatingWithTilde ?? localization.string("matrix.package.sync.noDeployment"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(sortedAppLinks(row.deployment?.appLinks ?? [:]), id: \.key) { key, link in
                    packageLinkStatusBadge(appKey: key, status: link.status)
                }
            }
        }
        .padding(8)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func packageLinkStatusBadge(appKey: String, status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status.lowercased() {
            case "ok":       return (localization.string("matrix.inspector.linkStatus.ok"), Color.popStatusOK)
            case "broken":   return (localization.string("matrix.inspector.linkStatus.broken"), Color.popStatusError)
            case "inactive": return (localization.string("matrix.inspector.linkStatus.inactive"), Color.popTertiaryLabel)
            case "na":       return (localization.string("matrix.inspector.linkStatus.na"), Color.popTertiaryLabel)
            default:         return (status, Color.popSecondaryLabel)
            }
        }()
        return HStack(spacing: 3) {
            Text(packageLinkAppShortLabel(for: appKey))
                .font(.system(size: 8.5, weight: .bold))
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.10), in: Capsule())
    }

    private func packageLinkAppShortLabel(for key: String) -> String {
        switch key.lowercased() {
        case "claude": return "CC"
        case "codex": return "CDX"
        default: return key.prefix(3).uppercased()
        }
    }

    private func syncStatusPill(for pendingUpdates: [SkillUpdateInfo]) -> some View {
        let hasPending = !pendingUpdates.isEmpty
        let color = hasPending ? Color.accentColor : Color.popStatusOK
        let title = hasPending
            ? localization.string("matrix.package.sync.pending", pendingUpdates.count)
            : localization.string("matrix.package.sync.upToDate")

        return Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func packageSyncUpdateRow(_ update: SkillUpdateInfo) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(update.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.popLabel)
                Text(update.currentHash.map { "\(Self.shortHash($0)) -> \(Self.shortHash(update.remoteHash))" } ?? localization.string("updates.row.firstSync"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer(minLength: 8)
        }
        .padding(8)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func packageMetadataSection(_ package: CapabilityPackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.meta")
            VStack(alignment: .leading, spacing: 6) {
                metaRow(label: localization.string("matrix.inspector.meta.directory"), value: package.source.location)
                metaRow(label: localization.string("matrix.inspector.meta.sourceType"), value: package.source.kind)
                metaRow(label: localization.string("matrix.inspector.meta.packageType"), value: package.typeLabel)
                if let installedAt = package.lifecycle?.installedAt, installedAt > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.installedAt"), value: Self.formatTimestamp(installedAt))
                }
                if let updatedAt = package.lifecycle?.updatedAt, updatedAt > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.updatedAt"), value: Self.formatTimestamp(updatedAt))
                }
            }
            if let url = package.sourceURL {
                Link(destination: url) {
                    Label(localization.string("matrix.inspector.meta.openSource"), systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func packagePill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func triggerSection(scenarios: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading(title: "matrix.inspector.section.triggers", accent: .accentColor)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(scenarios, id: \.self) { scenario in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.callout)
                            .foregroundStyle(Color.popTertiaryLabel)
                        Text(scenario)
                            .font(.callout)
                            .foregroundStyle(Color.popLabel)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func skillBundleSection(_ skill: Skill) -> some View {
        let packages = containingPackages(for: skill)
        if !packages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(title: "matrix.inspector.section.bundle", accent: .popSectionPurple)
                ForEach(packages, id: \.id) { package in
                    skillBundleCard(package, skill: skill)
                }
            }
        }
    }

    private func skillBundleCard(_ package: CapabilityPackage, skill: Skill) -> some View {
        let companions = package.companionInstalledSkills(for: skill, in: store.skills)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                PackageAvatar(name: package.name, identifier: package.id, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)
                    Text(PackageComponentCompositionFormatter.composition(for: package, localization: localization))
                    .font(.caption2)
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    store.selectCapability(MatrixCapability.packageCapabilityID(for: package.id))
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help(localization.string("matrix.skill.bundle.open"))
            }

            if !companions.isEmpty {
                Text(localization.string("matrix.skill.bundle.companions", companions.count))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.popSecondaryLabel)

                LazyVGrid(columns: Self.companionGridColumns, alignment: .leading, spacing: 5) {
                    ForEach(companions.prefix(8), id: \.id) { companion in
                        Button {
                            store.selectCapability(MatrixCapability.skillCapabilityID(for: companion.id))
                        } label: {
                            Text(companion.name)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.popControlFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.popSecondaryLabel)
                        .help(localization.string("matrix.skill.bundle.openCompanion", companion.name))
                    }
                    if companions.count > 8 {
                        Text(localization.string("matrix.package.paths.more", companions.count - 8))
                            .font(.caption2)
                            .foregroundStyle(Color.popTertiaryLabel)
                    }
                }
            }
        }
        .padding(9)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.apps")
            HStack(spacing: 12) {
                appToggleButton(.claude)
                appToggleButton(.codex)
                Spacer()
            }
            if !capability.isToggleable {
                Text(localization.string("matrix.inspector.readOnly"))
                    .font(.caption2)
                    .foregroundStyle(Color.popTertiaryLabel)
            }
        }
    }

    private func appToggleButton(_ app: TargetApp) -> some View {
        let isOn = capability.apps.isEnabled(app)
        let pending = store.pendingToggles.contains(toggleKey(app))
        return Button {
            guard capability.isToggleable else { return }
            Task { await toggle(app: app, enabled: !isOn) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: app.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                Text(app.title)
                    .font(.callout.weight(.medium))
                if pending {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.popSecondaryLabel)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isOn ? Color.accentColor.opacity(0.14) : Color.popSubtleFill,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(pending || !capability.isToggleable)
    }

    private func skillPathsSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "matrix.inspector.section.paths")
            if let deployment = capability.deployment {
                VStack(alignment: .leading, spacing: 6) {
                    deploymentRow(
                        title: localization.string("matrix.inspector.deployment.ssot"),
                        path: deployment.ssotPath,
                        status: nil
                    )
                    ForEach(sortedAppLinks(deployment.appLinks), id: \.key) { key, link in
                        deploymentRow(
                            title: appLabel(for: key),
                            path: link.path,
                            status: link.status
                        )
                    }
                }
                if let markdownURL = skill.markdownURL {
                    deploymentRow(
                        title: localization.string("matrix.skill.paths.readme"),
                        path: markdownURL.path,
                        status: "ok"
                    )
                }
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                    Text(localization.string("matrix.inspector.deployment.strategy", deployment.strategy))
                        .font(.caption2)
                }
                .foregroundStyle(Color.popTertiaryLabel)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    deploymentRow(
                        title: localization.string("matrix.inspector.deployment.ssot"),
                        path: skill.localStoreURL.path,
                        status: FileManager.default.fileExists(atPath: skill.localStoreURL.path) ? "ok" : nil
                    )
                    if let markdownURL = skill.markdownURL {
                        deploymentRow(
                            title: localization.string("matrix.skill.paths.readme"),
                            path: markdownURL.path,
                            status: "ok"
                        )
                    }
                }
                Text(localization.string("matrix.inspector.deployment.empty"))
                    .font(.caption2)
                    .foregroundStyle(Color.popTertiaryLabel)
            }
        }
    }

    private func sortedAppLinks(_ links: [String: AppLinkStatus]) -> [(key: String, value: AppLinkStatus)] {
        let priority: [String: Int] = ["claude": 0, "codex": 1]
        return links.sorted { lhs, rhs in
            let l = priority[lhs.key] ?? 99
            let r = priority[rhs.key] ?? 99
            if l != r { return l < r }
            return lhs.key < rhs.key
        }.map { (key: $0.key, value: $0.value) }
    }

    private func appLabel(for key: String) -> String {
        switch key.lowercased() {
        case "claude": return "Claude Code"
        case "codex":  return "Codex"
        case "gemini": return "Gemini"
        case "opencode": return "OpenCode"
        case "hermes": return "Hermes"
        default: return key.capitalized
        }
    }

    private func deploymentRow(title: String, path: String, status: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.popLabel)
                Text(path.isEmpty ? "—" : (path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if let status {
                linkStatusBadge(status)
            }
            if let url = revealableURL(for: path) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.popSecondaryLabel)
                .help(localization.string("matrix.row.menu.revealInFinder"))
            }
        }
        .padding(8)
        .background(Color.popSubtleFill, in: RoundedRectangle(cornerRadius: 6))
    }

    private func revealableURL(for path: String) -> URL? {
        guard !path.isEmpty, path != "—" else {
            return nil
        }
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            return nil
        }
        return URL(fileURLWithPath: expanded)
    }

    private func linkStatusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status.lowercased() {
            case "ok":       return (localization.string("matrix.inspector.linkStatus.ok"), .green)
            case "broken":   return (localization.string("matrix.inspector.linkStatus.broken"), .red)
            case "inactive": return (localization.string("matrix.inspector.linkStatus.inactive"), Color.popTertiaryLabel)
            case "na":       return (localization.string("matrix.inspector.linkStatus.na"), Color.popTertiaryLabel)
            default:         return (status, Color.popSecondaryLabel)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "matrix.inspector.section.meta")
            VStack(alignment: .leading, spacing: 6) {
                metaRow(label: localization.string("matrix.inspector.meta.directory"), value: capability.directory)
                if let source = capability.sourceType, !source.isEmpty {
                    metaRow(label: localization.string("matrix.inspector.meta.sourceType"), value: source)
                }
                if let installedAt = capability.installedAt, installedAt > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.installedAt"), value: Self.formatTimestamp(installedAt))
                }
                if let updatedAt = capability.updatedAt, updatedAt > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.updatedAt"), value: Self.formatTimestamp(updatedAt))
                }
                if let size = capability.sizeBytes, size > 0 {
                    metaRow(label: localization.string("matrix.inspector.meta.size"), value: Self.formatBytes(size))
                }
            }
            if let url = capability.sourceURL {
                Link(destination: url) {
                    Label(localization.string("matrix.inspector.meta.openSource"), systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.popSecondaryLabel)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(Color.popLabel)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private static func formatTimestamp(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        return timestampFormatter.string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func formatTokens(_ value: Int64) -> String {
        if value < 1_000 {
            return decimalFormatter.string(from: NSNumber(value: value)) ?? "0"
        }
        if value < 1_000_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        if value < 1_000_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        return String(format: "%.2fB", Double(value) / 1_000_000_000.0)
    }

    private static func shortHash(_ hash: String) -> String {
        String(hash.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let usageDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M-d"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let usageCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return calendar
    }()

    private static let actionGridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading)
    ]

    private static let machineMetricColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)
    ]

    private static let syncFactColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading)
    ]

    private static let companionGridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 84), spacing: 5, alignment: .leading)
    ]

    private func firstRevealableSkillURL(for package: CapabilityPackage) -> URL? {
        package.matchingInstalledSkills(in: store.skills)
            .first { FileManager.default.fileExists(atPath: $0.localStoreURL.path) }?
            .localStoreURL
    }

    private func readmeSkill(for package: CapabilityPackage) -> Skill? {
        package.matchingInstalledSkills(in: store.skills)
            .first { $0.markdownURL != nil }
    }

    private func packagePendingUpdates(_ package: CapabilityPackage) -> [SkillUpdateInfo] {
        store.updates.filter { package.matchingSkillComponent(for: $0) != nil }
    }

    private func containingPackages(for skill: Skill) -> [CapabilityPackage] {
        store.compositePackages.filter { $0.containsSkill(skill) }
    }

    // MARK: Toggle helpers

    private func toggleKey(_ app: TargetApp) -> String {
        MatrixCapability.toggleKey(capabilityID: capability.id, app: app)
    }

    private func packageToggleKey(skillID: String, app: TargetApp) -> String {
        MatrixCapability.toggleKey(capabilityID: MatrixCapability.skillCapabilityID(for: skillID), app: app)
    }

    private func packageActivationInFlight(for targets: [Skill], app: TargetApp) -> Bool {
        targets.contains { store.pendingToggles.contains(packageToggleKey(skillID: $0.id, app: app)) }
    }

    @MainActor
    private func toggle(app: TargetApp, enabled: Bool) async {
        guard let skillID = capability.underlyingSkillID else { return }
        let key = toggleKey(app)
        guard !store.pendingToggles.contains(key) else { return }
        store.pendingToggles.insert(key)
        defer { store.pendingToggles.remove(key) }

        do {
            try await store.client.toggle(skillID: skillID, app: app, enabled: enabled)
            if let idx = store.skills.firstIndex(where: { $0.id == skillID }) {
                store.skills[idx].apps.setEnabled(enabled, for: app)
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func activatePackage(_ package: CapabilityPackage, app: TargetApp) async {
        let targets = package.installedSkillsRequiringEnablement(for: app, in: store.skills)
        guard !targets.isEmpty else { return }

        let keys = Set(targets.map { packageToggleKey(skillID: $0.id, app: app) })
        guard keys.isDisjoint(with: store.pendingToggles) else { return }
        store.pendingToggles.formUnion(keys)
        defer { store.pendingToggles.subtract(keys) }

        var firstError: Error?
        for target in targets {
            do {
                try await store.client.toggle(skillID: target.id, app: app, enabled: true)
                if let idx = store.skills.firstIndex(where: { $0.id == target.id }) {
                    store.skills[idx].apps.setEnabled(true, for: app)
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            store.errorMessage = firstError.localizedDescription
        }
    }

    @MainActor
    private func refreshPackageLinkHealth() async {
        guard !linkHealthScanInFlight else { return }
        linkHealthScanInFlight = true
        defer { linkHealthScanInFlight = false }

        do {
            store.linkHealth = try await store.client.linkHealth()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var abbreviatingWithTilde: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}

private struct InspectorHeaderChip: Identifiable {
    let id: String
    let title: String
    let tint: Color
}

private struct InspectorMachineMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let tint: Color
}

private struct InspectorSourceFact: Identifiable {
    let id: String
    let title: String
    let value: String
    let icon: String
    var url: URL? = nil
}

private struct UsageTrendBars: View {
    let buckets: [UsageBucketStat]
    let tint: Color

    private var maxEvents: Int {
        max(buckets.map(\.usageEvents).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(buckets) { bucket in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(bucket.usageEvents > 0 ? tint.opacity(0.72) : Color.popControlFill)
                    .frame(height: barHeight(for: bucket))
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .help("\(bucket.usageEvents)")
            }
        }
        .frame(height: 42, alignment: .bottom)
    }

    private func barHeight(for bucket: UsageBucketStat) -> CGFloat {
        guard bucket.usageEvents > 0 else {
            return 4
        }
        let ratio = CGFloat(bucket.usageEvents) / CGFloat(maxEvents)
        return max(7, ratio * 42)
    }
}

private enum InspectorTab: String, CaseIterable, Identifiable {
    case overview
    case readme
    case usage
    case version
    case paths
    case sync
    case metadata

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .overview: "matrix.inspector.tab.overview"
        case .readme: "matrix.inspector.tab.readme"
        case .usage: "matrix.inspector.tab.usage"
        case .version: "matrix.inspector.tab.version"
        case .paths: "matrix.inspector.tab.paths"
        case .sync: "matrix.inspector.tab.sync"
        case .metadata: "matrix.inspector.tab.metadata"
        }
    }
}

private extension CapabilityPackageHealth {
    var inspectorTitleKey: String {
        switch self {
        case .active: "matrix.package.health.active"
        case .partial: "matrix.package.health.partial"
        case .inactive: "matrix.package.health.inactive"
        case .blocked: "matrix.package.health.blocked"
        }
    }

    var inspectorColor: Color {
        switch self {
        case .active: Color.popStatusOK
        case .partial: Color.popStatusWarning
        case .inactive: Color.popTertiaryLabel
        case .blocked: Color.popStatusError
        }
    }
}

private extension PackageComponent {
    var inspectorKindSymbol: String {
        switch kind.lowercased() {
        case "skill": "square.grid.3x3.fill"
        case "agent": "person.crop.square"
        case "cli": "terminal"
        case "mcp": "rectangle.connected.to.line.below"
        default: "circle.grid.2x2"
        }
    }
}

private extension String {
    var usageKindSymbol: String {
        switch lowercased() {
        case "skill": "square.grid.3x3.fill"
        case "agent": "person.crop.square"
        case "cli": "terminal"
        case "mcp": "rectangle.connected.to.line.below"
        default: "circle.grid.2x2"
        }
    }
}

private extension TargetApp {
    var inspectorAccentColor: Color {
        switch self {
        case .claude: .orange
        case .codex: .green
        case .gemini: .blue
        case .opencode: .indigo
        case .hermes: .purple
        }
    }
}
