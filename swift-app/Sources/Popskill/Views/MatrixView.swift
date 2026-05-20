import SwiftUI

enum MatrixTableLayout {
    static let appColumnWidth: CGFloat = 92
    static let sourceColumnWidth: CGFloat = 184
    static let tokensColumnWidth: CGFloat = 78
    static let callsColumnWidth: CGFloat = 62
    static let actionColumnWidth: CGFloat = 52
}

/// Skills × Tools — the matrix is Popskill's灵魂主视图: rows = capabilities
/// (skill / cli / mcp / agent), columns = AI tools (Claude Code / Codex),
/// the cell is a direct toggle. Selecting a row slides an Inspector pane in
/// from the right showing the position-and-link section.
@MainActor
struct MatrixView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        let capabilities = store.capabilities
        let usageIndex = MatrixUsageIndex(
            summary: store.usageSummary,
            skills: store.skills,
            packages: store.compositePackages
        )
        let sections = filteredSections(in: capabilities)
        VStack(spacing: 0) {
            header(capabilities: capabilities)
            Divider()
            // Empty check honors the unified `capabilities` view (skills +
            // agents + future cli/mcp/config), not just raw skills. v0.4 added
            // agents to the matrix but the empty-state guard still pointed at
            // store.skills, so an agent-only install would render "no
            // capabilities yet" while the matrix below was happily populated.
            // v1.0.3 also distinguishes "world is empty" from "filter is too
            // narrow" — the latter shows noResultsState with a reset button.
            if capabilities.isEmpty {
                emptyState
            } else if sections.isEmpty {
                noResultsState
            } else {
                matrixTable(sections: sections, usageIndex: usageIndex)
            }
        }
        .popPageBackground()
        .inspector(isPresented: $store.inspectorOpen) {
            if let id = store.selectedSkillID,
               let capability = capabilities.first(where: { $0.id == id }) {
                InspectorPane(store: store, capability: capability)
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 480)
            } else {
                emptyInspector
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 480)
            }
        }
    }

    // MARK: Header

    private func header(capabilities: [MatrixCapability]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("sidebar.matrix")
                        .font(.popLargeTitle)
                        .foregroundStyle(Color.popLabel)
                    Text(subtitle(capabilities: capabilities))
                        .font(.popSubheadline)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
                Spacer(minLength: 16)
                searchField
            }
            metricStrip(capabilities: capabilities)
            HStack(spacing: 10) {
                filterChips
                Spacer(minLength: 8)
                Label(localization.string("matrix.sort.typeDescending"), systemImage: "arrow.down")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private func subtitle(capabilities: [MatrixCapability]) -> String {
        let count = capabilities.count
        let active = store.enabledSkillCount
        return localization.string("matrix.subtitle", store.bundleCount, count, active)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.popTertiaryLabel)
            TextField(localization.string("matrix.search.placeholder"), text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchIsFocused)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.popTertiaryLabel)
                }
                .buttonStyle(.plain)
                .help(localization.string("spotlight.clear"))
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.popControlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(searchIsFocused ? Color.accentColor.opacity(0.42) : Color.popControlStroke, lineWidth: 0.8)
        )
        .frame(maxWidth: 320)
        .accessibilityLabel(Text(localization.string("matrix.search.placeholder")))
    }

    private func metricStrip(capabilities: [MatrixCapability]) -> some View {
        let metrics = summaryMetrics(capabilities: capabilities)
        return HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                MatrixSummaryMetricView(metric: metric)
                    .frame(minWidth: metric.preferredWidth, alignment: .leading)
                if index < metrics.count - 1 {
                    Rectangle()
                        .fill(Color.popSeparator.opacity(0.65))
                        .frame(width: 0.5, height: 32)
                        .padding(.horizontal, 16)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func summaryMetrics(capabilities: [MatrixCapability]) -> [MatrixSummaryMetric] {
        [
            MatrixSummaryMetric(
                id: "capabilities",
                value: "\(capabilities.count)",
                title: localization.string("matrix.metric.capabilities"),
                tint: .popLabel
            ),
            MatrixSummaryMetric(
                id: "claude",
                value: "\(capabilities.filter { $0.apps.claude }.count)",
                title: localization.string("matrix.metric.claudeActive"),
                tint: .popLabel
            ),
            MatrixSummaryMetric(
                id: "codex",
                value: "\(capabilities.filter { $0.apps.codex }.count)",
                title: localization.string("matrix.metric.codexActive"),
                tint: .popLabel
            ),
            MatrixSummaryMetric(
                id: "stubs",
                value: "\(store.stubs.count)",
                title: localization.string("matrix.metric.stubs"),
                tint: store.stubs.isEmpty ? .popSecondaryLabel : .popStatusWarning
            ),
            MatrixSummaryMetric(
                id: "broken-links",
                value: "\(store.brokenLinkCount)",
                title: localization.string("matrix.metric.brokenLinks"),
                tint: store.brokenLinkCount > 0 ? .popStatusError : .popSecondaryLabel
            ),
            MatrixSummaryMetric(
                id: "tokens",
                value: store.usageSummary.map { UsageDisplayFormatter.compactTokens($0.totalTokens) } ?? "—",
                title: localization.string("matrix.metric.tokenUsage"),
                tint: .popLabel,
                preferredWidth: 116
            )
        ]
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MatrixFilter.allCases) { filter in
                    chipButton(filter: filter)
                }
                Divider().frame(height: 16).padding(.horizontal, 4)
                ForEach(MatrixTypeFilter.allCases) { filter in
                    typeChipButton(filter: filter)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipButton(filter: MatrixFilter) -> some View {
        let active = store.matrixFilter == filter
        return Button {
            store.matrixFilter = filter
        } label: {
            HStack(spacing: 4) {
                Text(localization.string(filter.titleKey))
                if let badge = filter.badge(store: store), badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                }
            }
            .font(.system(size: 11.5, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Color.popCardBackground : Color.popLabel)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                active ? Color.popLabel : Color.popControlFill,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(active ? Color.popLabel.opacity(0.10) : Color.popControlStroke, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func typeChipButton(filter: MatrixTypeFilter) -> some View {
        let active = store.matrixTypeFilter == filter
        return Button {
            store.matrixTypeFilter = filter
        } label: {
            Text(localization.string(filter.titleKey))
                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.popCardBackground : Color.popLabel)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    active ? Color.popLabel : Color.popControlFill,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(active ? Color.popLabel.opacity(0.10) : Color.popControlStroke, lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: Matrix table

    private func matrixTable(sections: [CapabilitySection], usageIndex: MatrixUsageIndex) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    matrixColumnHeader
                }
                ForEach(sections) { section in
                    if sections.count > 1 {
                        kindSectionHeader(section)
                    }
                    ForEach(section.groups) { group in
                        Section {
                            MatrixGroupHeader(group: group, store: store)
                            if !store.collapsedGroups.contains(group.id) {
                                ForEach(group.capabilities, id: \.id) { capability in
                                    if capability.kind == .bundle {
                                        MatrixPackageRow(capability: capability, store: store, usageIndex: usageIndex)
                                    } else {
                                        MatrixRow(capability: capability, store: store, usageIndex: usageIndex)
                                    }
                                    Divider().opacity(0.4)
                                }
                            }
                        }
                    }
                }
                Color.clear.frame(height: 24)
            }
        }
        .background(Color.popSurfaceElevated.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.popBorder.opacity(0.82), lineWidth: 0.7)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    /// Big-band header that separates capability kinds in the matrix when
    /// more than one kind is currently visible. Hidden in single-kind views
    /// (e.g. when the user clicks the "Skill" type chip) to avoid noise.
    private func kindSectionHeader(_ section: CapabilitySection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: section.kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            LocalizedText(section.kind.titleKey)
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.accentColor)
            Text("\(section.totalCount)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.popSecondaryLabel)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.popAccentSoft.opacity(0.72))
    }

    private var matrixColumnHeader: some View {
        HStack(spacing: 0) {
            Text(localization.string("matrix.col.capability"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
            Text("Claude Code")
                .frame(width: MatrixTableLayout.appColumnWidth, alignment: .center)
            Text("Codex")
                .frame(width: MatrixTableLayout.appColumnWidth, alignment: .center)
            Text(localization.string("matrix.col.source"))
                .frame(width: MatrixTableLayout.sourceColumnWidth, alignment: .leading)
            Text(localization.string("matrix.col.tokens"))
                .frame(width: MatrixTableLayout.tokensColumnWidth, alignment: .trailing)
            Text(localization.string("matrix.col.calls"))
                .frame(width: MatrixTableLayout.callsColumnWidth, alignment: .trailing)
            Spacer().frame(width: MatrixTableLayout.actionColumnWidth)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(Color.popTertiaryLabel)
        .textCase(.uppercase)
        .padding(.vertical, 7)
        .background(Color.popTableHeaderFill.opacity(0.70))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.popSeparator)
                .frame(height: 0.5)
        }
    }

    // MARK: Inspector empty

    private var emptyInspector: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            LocalizedText("matrix.inspector.empty.title")
                .font(.body.weight(.semibold))
            LocalizedText("matrix.inspector.empty.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.popCardBackground.opacity(0.62))
    }

    // MARK: Filtering & grouping

    private func filteredSections(in capabilities: [MatrixCapability]) -> [CapabilitySection] {
        let q = SearchTextNormalizer.key(store.trimmedSearch)
        let visible = capabilities.filter { capability in
                store.matrixFilter.includes(capability: capability, store: store)
                && store.matrixTypeFilter.includes(capability: capability)
                && (q.isEmpty
                    || SearchTextNormalizer.matches(capability.name, query: q)
                    || SearchTextNormalizer.matches(capability.summary ?? "", query: q)
                    || SearchTextNormalizer.matches(capability.directory, query: q)
                    || capability.package?.components.all.contains { component in
                        SearchTextNormalizer.matches(component.name, query: q)
                            || SearchTextNormalizer.matches(component.id, query: q)
                            || SearchTextNormalizer.matches(component.location ?? "", query: q)
                    } == true)
        }
        return SkillGrouping.sections(visible)
    }

    private var noResultsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            LocalizedText("spotlight.empty.title")
                .font(.title3.weight(.semibold))
            LocalizedText("library.search.emptyHint")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                store.searchText = ""
                store.matrixFilter = .all
                store.matrixTypeFilter = .allTypes
            } label: {
                Label(localization.string("spotlight.clear"), systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            LocalizedText("matrix.empty.title")
                .font(.title3.weight(.semibold))
            LocalizedText("matrix.empty.body")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if store.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await store.bootstrap() } } label: {
                    Label(localization.string("matrix.empty.refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MatrixSummaryMetric: Identifiable {
    let id: String
    let value: String
    let title: String
    let tint: Color
    var preferredWidth: CGFloat = 92
}

private struct MatrixSummaryMetricView: View {
    let metric: MatrixSummaryMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(metric.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(metric.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.popSecondaryLabel)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Filters

enum MatrixFilter: String, CaseIterable, Identifiable {
    case all
    case updates
    case brokenLinks = "broken-links"
    case claudeOnly = "claude-only"
    case codexOnly = "codex-only"
    case inactive

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all:        return "matrix.filter.all"
        case .updates:    return "matrix.filter.updates"
        case .brokenLinks: return "matrix.filter.brokenLinks"
        case .claudeOnly: return "matrix.filter.claudeOnly"
        case .codexOnly:  return "matrix.filter.codexOnly"
        case .inactive:   return "matrix.filter.inactive"
        }
    }

    @MainActor
    func badge(store: PopskillStore) -> Int? {
        switch self {
        case .updates:
            return store.pendingUpdateCount > 0 ? store.pendingUpdateCount : nil
        case .brokenLinks:
            return store.brokenLinkCount > 0 ? store.brokenLinkCount : nil
        default:
            return nil
        }
    }

    @MainActor
    func includes(capability: MatrixCapability, store: PopskillStore) -> Bool {
        switch self {
        case .all:
            return true
        case .updates:
            return store.hasPendingUpdate(for: capability)
        case .brokenLinks:
            return capability.hasBrokenLink || capability.package?.hasBrokenLinks(in: store.skills) == true
        case .claudeOnly:
            return capability.apps.claude && !capability.apps.codex
        case .codexOnly:
            return capability.apps.codex && !capability.apps.claude
        case .inactive:
            return !capability.apps.claude && !capability.apps.codex
        }
    }
}

enum MatrixTypeFilter: String, CaseIterable, Identifiable {
    case allTypes
    case bundle
    case skill
    case agent
    case cli
    case mcp

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .allTypes: return "matrix.type.all"
        case .bundle:   return "matrix.type.bundle"
        case .skill:    return "matrix.type.skill"
        case .agent:    return "matrix.type.agent"
        case .cli:      return "matrix.type.cli"
        case .mcp:      return "matrix.type.mcp"
        }
    }

    func includes(capability: MatrixCapability) -> Bool {
        switch self {
        case .allTypes: return true
        case .bundle:   return capability.kind == .bundle
        case .skill:    return capability.kind == .skill
        case .agent:    return capability.kind == .agent
        case .cli:      return capability.kind == .cli
        case .mcp:      return capability.kind == .mcp
        }
    }
}
