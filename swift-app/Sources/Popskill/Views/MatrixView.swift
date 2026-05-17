import SwiftUI

/// Skills × Tools — the matrix is Popskill's灵魂主视图: rows = capabilities
/// (skill / cli / mcp / agent), columns = AI tools (Claude Code / Codex),
/// the cell is a direct toggle. Selecting a row slides an Inspector pane in
/// from the right showing the position-and-link section.
struct MatrixView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        let sections = filteredSections
        VStack(spacing: 0) {
            header
            Divider()
            // Empty check honors the unified `capabilities` view (skills +
            // agents + future cli/mcp/config), not just raw skills. v0.4 added
            // agents to the matrix but the empty-state guard still pointed at
            // store.skills, so an agent-only install would render "no
            // capabilities yet" while the matrix below was happily populated.
            // v1.0.3 also distinguishes "world is empty" from "filter is too
            // narrow" — the latter shows noResultsState with a reset button.
            if store.capabilities.isEmpty {
                emptyState
            } else if sections.isEmpty {
                noResultsState
            } else {
                matrixTable(sections: sections)
            }
        }
        .popPageBackground()
        .inspector(isPresented: $store.inspectorOpen) {
            if let id = store.selectedSkillID,
               let capability = store.capabilities.first(where: { $0.id == id }) {
                InspectorPane(store: store, capability: capability)
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 480)
            } else {
                emptyInspector
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 480)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("sidebar.matrix")
                        .font(.popLargeTitle)
                        .foregroundStyle(Color.popLabel)
                    Text(subtitle)
                        .font(.popSubheadline)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
                Spacer(minLength: 16)
                searchField
            }
            filterChips
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private var subtitle: String {
        let count = store.capabilities.count
        let active = store.enabledSkillCount
        return localization.string("matrix.subtitle", count, active)
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
            .font(.system(size: 12, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Color.accentColor : Color.popSecondaryLabel)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                active ? Color.popAccentSoft : Color.popControlFill,
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(active ? Color.accentColor.opacity(0.30) : Color.popControlStroke, lineWidth: 0.7))
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
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.accentColor : Color.popSecondaryLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    active ? Color.popAccentSoft : Color.popControlFill,
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(active ? Color.accentColor.opacity(0.30) : Color.popControlStroke, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: Matrix table

    private func matrixTable(sections: [CapabilitySection]) -> some View {
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
                                    MatrixRow(capability: capability, store: store)
                                    Divider().opacity(0.4)
                                }
                            }
                        }
                    }
                }
                Color.clear.frame(height: 24)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(Color.popSurfaceElevated.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.popBorder, lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.035), radius: 12, x: 0, y: 3)
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
                .frame(width: 100, alignment: .center)
            Text("Codex")
                .frame(width: 100, alignment: .center)
            Text(localization.string("matrix.col.source"))
                .frame(width: 220, alignment: .leading)
            Spacer().frame(width: 56)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Color.popSecondaryLabel)
        .padding(.vertical, 8)
        .background(Color.popTableHeaderFill)
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

    private var filteredSections: [CapabilitySection] {
        let q = store.trimmedSearch.lowercased()
        let visible = store.capabilities.filter { capability in
            store.matrixFilter.includes(capability: capability, store: store)
                && store.matrixTypeFilter.includes(capability: capability)
                && (q.isEmpty
                    || capability.name.lowercased().contains(q)
                    || (capability.summary ?? "").lowercased().contains(q)
                    || capability.directory.lowercased().contains(q))
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

// MARK: - Filters

enum MatrixFilter: String, CaseIterable, Identifiable {
    case all
    case updates
    case claudeOnly = "claude-only"
    case codexOnly = "codex-only"
    case inactive

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all:        return "matrix.filter.all"
        case .updates:    return "matrix.filter.updates"
        case .claudeOnly: return "matrix.filter.claudeOnly"
        case .codexOnly:  return "matrix.filter.codexOnly"
        case .inactive:   return "matrix.filter.inactive"
        }
    }

    @MainActor
    func badge(store: PopskillStore) -> Int? {
        switch self {
        case .updates: return store.pendingUpdateCount > 0 ? store.pendingUpdateCount : nil
        default:       return nil
        }
    }

    @MainActor
    func includes(capability: MatrixCapability, store: PopskillStore) -> Bool {
        switch self {
        case .all:
            return true
        case .updates:
            return store.hasPendingUpdate(for: capability)
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
    case skill
    case agent
    case cli
    case mcp

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .allTypes: return "matrix.type.all"
        case .skill:    return "matrix.type.skill"
        case .agent:    return "matrix.type.agent"
        case .cli:      return "matrix.type.cli"
        case .mcp:      return "matrix.type.mcp"
        }
    }

    func includes(capability: MatrixCapability) -> Bool {
        switch self {
        case .allTypes: return true
        case .skill:    return capability.kind == .skill
        case .agent:    return capability.kind == .agent
        case .cli:      return capability.kind == .cli
        case .mcp:      return capability.kind == .mcp
        }
    }
}
