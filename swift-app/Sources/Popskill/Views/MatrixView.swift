import SwiftUI

/// Skills × Tools — the matrix is Popskill's灵魂主视图: rows = capabilities
/// (skill / cli / mcp / agent), columns = AI tools (Claude Code / Codex),
/// the cell is a direct toggle. Selecting a row slides an Inspector pane in
/// from the right showing the position-and-link section.
struct MatrixView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.skills.isEmpty {
                emptyState
            } else {
                matrixTable
            }
        }
        .popPageBackground()
        .inspector(isPresented: $store.inspectorOpen) {
            if let id = store.selectedSkillID,
               let skill = store.skills.first(where: { $0.id == id }) {
                InspectorPane(store: store, skill: skill)
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
        let count = store.skills.count
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .frame(maxWidth: 320)
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
                active ? Color.accentColor.opacity(0.14) : Color.black.opacity(0.04),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
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
                    active ? Color.accentColor.opacity(0.14) : Color.black.opacity(0.04),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Matrix table

    private var matrixTable: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    matrixColumnHeader
                }
                ForEach(filteredGroups) { group in
                    Section {
                        MatrixGroupHeader(group: group, store: store)
                        if !store.collapsedGroups.contains(group.id) {
                            ForEach(group.skills, id: \.id) { skill in
                                MatrixRow(skill: skill, store: store)
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
                Color.clear.frame(height: 24)
            }
        }
        .background(Color.popCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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
        .background(Color.black.opacity(0.02))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
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

    private var filteredGroups: [MatrixGroup] {
        let q = store.trimmedSearch.lowercased()
        let visible = store.skills.filter { skill in
            store.matrixFilter.includes(skill: skill, store: store)
                && store.matrixTypeFilter.includes(skill: skill)
                && (q.isEmpty
                    || skill.name.lowercased().contains(q)
                    || skill.description.lowercased().contains(q)
                    || (skill.capabilitySummary ?? "").lowercased().contains(q)
                    || skill.directory.lowercased().contains(q))
        }
        return SkillGrouping.group(visible)
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
    func includes(skill: Skill, store: PopskillStore) -> Bool {
        switch self {
        case .all:
            return true
        case .updates:
            return store.updates.contains { $0.id == skill.id }
        case .claudeOnly:
            return skill.apps.claude && !skill.apps.codex
        case .codexOnly:
            return skill.apps.codex && !skill.apps.claude
        case .inactive:
            return !skill.apps.claude && !skill.apps.codex
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

    func includes(skill: Skill) -> Bool {
        // v0.3: every InstalledSkill is a "skill"; CLI / MCP / agent are
        // surfaced via Sources / Agents views and will get full matrix rows
        // when the sidecar contract is extended. For now, only allTypes and
        // skill ever return true.
        switch self {
        case .allTypes: return true
        case .skill:    return true
        case .agent:    return false
        case .cli:      return false
        case .mcp:      return false
        }
    }
}
