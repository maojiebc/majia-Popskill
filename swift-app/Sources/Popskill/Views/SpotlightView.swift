import SwiftUI

/// ⌘K command palette. Opens over the entire app, search box auto-focused.
/// Two sections shown together, deduped by source:
///   1. **能力** — top package / skill hits ranked by local scorers.
///   2. **操作** — fixed quick actions (refresh / link-health / updates /
///      settings) filtered by query substring match.
///
/// Keyboard: ↑↓ moves highlight, Enter triggers the highlighted row, Esc
/// closes. Clicking the scrim closes too. Pressing ⌘1 / ⌘2 on a skill row
/// toggles Claude / Codex without leaving the palette.
@MainActor
struct SpotlightView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var localQuery: String = ""
    @State private var highlighted: Int = 0
    @FocusState private var queryFocused: Bool

    private let maxCapabilityHits = 8
    private let maxPackageHits = 3

    var body: some View {
        ZStack {
            scrim
            palette
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .onAppear { queryFocused = true }
        .onChange(of: localQuery) { _, _ in
            highlighted = 0
        }
    }

    // MARK: Scrim

    private var scrim: some View {
        Color.popBackdropScrim
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { close() }
    }

    // MARK: Palette card

    private var palette: some View {
        VStack(spacing: 0) {
            queryRow
            Divider()
            if combined.isEmpty {
                emptyRow
            } else {
                resultList
            }
            footerRow
        }
        .frame(maxWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.popSubtleStroke, lineWidth: 0.5)
        )
        .shadow(color: Color.popShadow.opacity(0.20), radius: 30, y: 12)
        .padding(.top, 80)
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var queryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.popSecondaryLabel)
            TextField(
                localization.string("spotlight.placeholder"),
                text: $localQuery
            )
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .focused($queryFocused)
            .onSubmit { activate(index: highlighted) }
            .onKeyPress(.downArrow) {
                moveHighlight(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveHighlight(by: -1)
                return .handled
            }
            .onKeyPress(.escape) {
                close()
                return .handled
            }
            if !localQuery.isEmpty {
                Button { localQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.popTertiaryLabel)
                }
                .buttonStyle(.plain)
                .help(localization.string("spotlight.clear"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyRow: some View {
        VStack(spacing: 6) {
            Text(localization.string("spotlight.empty.title"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.popLabel)
            Text(localization.string("spotlight.empty.body"))
                .font(.caption)
                .foregroundStyle(Color.popSecondaryLabel)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if !capabilityItems.isEmpty {
                        Section {
                            ForEach(Array(capabilityItems.enumerated()), id: \.offset) { offset, item in
                                row(
                                    item: item,
                                    index: offset,
                                    proxy: proxy
                                )
                            }
                        } header: {
                            sectionHeader(localization.string("spotlight.section.capabilities"))
                        }
                    }
                    if !actionHits.isEmpty {
                        Section {
                            ForEach(Array(actionHits.enumerated()), id: \.offset) { offset, action in
                                row(
                                    item: .action(action),
                                    index: capabilityItems.count + offset,
                                    proxy: proxy
                                )
                            }
                        } header: {
                            sectionHeader(localization.string("spotlight.section.actions"))
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
            .onChange(of: highlighted) { _, new in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.popTertiaryLabel)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private func row(item: SpotlightItem, index: Int, proxy: ScrollViewProxy) -> some View {
        let isHighlighted = index == highlighted
        Button {
            activate(index: index)
        } label: {
            HStack(spacing: 10) {
                icon(for: item)
                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryLabel(for: item))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)
                    if let secondary = secondaryLabel(for: item), !secondary.isEmpty {
                        Text(secondary)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.popSecondaryLabel)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                trailing(for: item)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .onHover { hovering in
            if hovering { highlighted = index }
        }
    }

    private func icon(for item: SpotlightItem) -> some View {
        Group {
            switch item {
            case let .package(package, _):
                PackageAvatar(name: package.name, identifier: package.id, size: 24)
            case let .skill(skill, _):
                InitialAvatarView(name: skill.name, identifier: skill.id, size: 24)
            case let .action(action):
                Image(systemName: action.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(action.tint)
                    .frame(width: 24, height: 24)
                    .background(action.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func primaryLabel(for item: SpotlightItem) -> String {
        switch item {
        case let .package(package, _): return package.name
        case let .skill(skill, _): return skill.name
        case let .action(action):  return localization.string(action.titleKey)
        }
    }

    private func secondaryLabel(for item: SpotlightItem) -> String? {
        switch item {
        case let .package(package, hit):
            if !hit.matchedComponents.isEmpty {
                return localization.string(
                    "spotlight.bundle.matchedComponents",
                    hit.matchedComponents.joined(separator: " · ")
                )
            }
            return localization.string(
                "package.componentSummary",
                package.componentCount,
                package.installedComponentCount,
                package.requiredComponentCount
            )
        case let .skill(skill, hit):
            if !hit.matchedTriggers.isEmpty {
                return hit.matchedTriggers.prefix(2).joined(separator: " · ")
            }
            if let summary = skill.capabilitySummary, !summary.isEmpty { return summary }
            return skill.description
        case let .action(action):
            return localization.string(action.subtitleKey)
        }
    }

    @ViewBuilder
    private func trailing(for item: SpotlightItem) -> some View {
        switch item {
        case .package:
            Text(localization.string("matrix.type.bundle").uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.popSectionPurple)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color.popSectionPurple.opacity(0.12), in: Capsule())
        case let .skill(skill, _):
            HStack(spacing: 6) {
                quickToggle(skill: skill, app: .claude, shortcut: "1")
                quickToggle(skill: skill, app: .codex, shortcut: "2")
            }
        case .action:
            Image(systemName: "return")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.popTertiaryLabel)
        }
    }

    private func quickToggle(skill: Skill, app: TargetApp, shortcut: String) -> some View {
        let isOn = skill.apps.isEnabled(app)
        return Button {
            Task { await toggle(skill: skill, app: app, enabled: !isOn) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: app.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                Text("⌘\(shortcut)")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.popTertiaryLabel)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(
                isOn ? Color.accentColor.opacity(0.14) : Color.popSubtleFill,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .help(localization.string("spotlight.quickToggle.help", app.title, shortcut))
    }

    private var footerRow: some View {
        HStack(spacing: 10) {
            footerHint(symbol: "arrow.up.arrow.down", label: localization.string("spotlight.hint.navigate"))
            footerHint(symbol: "return", label: localization.string("spotlight.hint.open"))
            footerHint(symbol: "escape", label: localization.string("spotlight.hint.close"))
            Spacer()
            Text(localization.string("spotlight.title"))
                .font(.caption2)
                .foregroundStyle(Color.popTertiaryLabel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.popSubtleStroke)
                .frame(height: 0.5)
        }
    }

    private func footerHint(symbol: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(Color.popSecondaryLabel)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.popSubtleFill, in: Capsule())
    }

    // MARK: Derived

    private var packageHits: [(package: CapabilityPackage, hit: PackageSearchHit)] {
        let q = localQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return store.compositePackages
                .sorted { ($0.lastLifecycleTimestamp ?? 0) > ($1.lastLifecycleTimestamp ?? 0) }
                .prefix(maxPackageHits)
                .map { ($0, PackageSearchHit.recent) }
        }

        return store.compositePackages
            .compactMap { package -> (CapabilityPackage, PackageSearchHit)? in
                guard let hit = PackageSearchScorer.score(package: package, query: q) else { return nil }
                return (package, hit)
            }
            .sorted { lhs, rhs in
                if lhs.1.score != rhs.1.score { return lhs.1.score > rhs.1.score }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .prefix(maxPackageHits)
            .map { ($0.0, $0.1) }
    }

    private var skillHits: [(skill: Skill, hit: SkillSearchHit)] {
        let q = localQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let remainingSlots = max(0, maxCapabilityHits - packageHits.count)
        guard !q.isEmpty else {
            // Empty query: show recently installed / updated skills (max N).
            return store.skills
                .sorted { ($0.lastLifecycleTimestamp ?? 0) > ($1.lastLifecycleTimestamp ?? 0) }
                .prefix(remainingSlots)
                .map { ($0, SkillSearchHit(score: 0, matchedTriggers: [], matchedOnName: false)) }
        }
        return store.skills
            .compactMap { skill -> (Skill, SkillSearchHit)? in
                guard let hit = SkillSearchScorer.score(skill: skill, query: q) else { return nil }
                return (skill, hit)
            }
            .sorted { $0.1.score > $1.1.score }
            .prefix(remainingSlots)
            .map { ($0.0, $0.1) }
    }

    private var actionHits: [SpotlightAction] {
        let q = SearchTextNormalizer.key(localQuery)
        return SpotlightAction.all.filter { action in
            guard !q.isEmpty else { return true }
            return SearchTextNormalizer.matches(localization.string(action.titleKey), query: q)
                || SearchTextNormalizer.matches(localization.string(action.subtitleKey), query: q)
        }
    }

    private var combined: [SpotlightItem] {
        capabilityItems + actionHits.map { .action($0) }
    }

    private var capabilityItems: [SpotlightItem] {
        packageHits.map { .package($0.package, $0.hit) }
            + skillHits.map { .skill($0.skill, $0.hit) }
    }

    // MARK: Activation

    private func moveHighlight(by delta: Int) {
        let count = combined.count
        guard count > 0 else { return }
        highlighted = ((highlighted + delta) % count + count) % count
    }

    private func activate(index: Int) {
        guard combined.indices.contains(index) else { return }
        switch combined[index] {
        case let .package(package, _):
            store.currentSelection = .matrix
            store.selectCapability(MatrixCapability.packageCapabilityID(for: package.id))
            close()
        case let .skill(skill, _):
            store.currentSelection = .matrix
            store.selectSkill(skill.id)
            close()
        case let .action(action):
            action.run(store: store)
            close()
        }
    }

    private func close() {
        store.spotlightOpen = false
        localQuery = ""
        highlighted = 0
    }

    @MainActor
    private func toggle(skill: Skill, app: TargetApp, enabled: Bool) async {
        let key = MatrixCapability.skillToggleKey(for: skill.id, app: app)
        guard !store.pendingToggles.contains(key) else { return }
        store.pendingToggles.insert(key)
        defer { store.pendingToggles.remove(key) }
        do {
            try await store.client.toggle(skillID: skill.id, app: app, enabled: enabled)
            if let idx = store.skills.firstIndex(where: { $0.id == skill.id }) {
                store.skills[idx].apps.setEnabled(enabled, for: app)
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Items

private enum SpotlightItem {
    case package(CapabilityPackage, PackageSearchHit)
    case skill(Skill, SkillSearchHit)
    case action(SpotlightAction)
}

/// Quick action shown below skill matches. Action runs on @MainActor since
/// it usually mutates the store. Keep these short — heavy work belongs in a
/// dedicated view.
struct SpotlightAction: Identifiable {
    let id: String
    let titleKey: String
    let subtitleKey: String
    let symbol: String
    let tint: Color
    let perform: @MainActor (PopskillStore) -> Void

    @MainActor
    func run(store: PopskillStore) {
        perform(store)
    }

    static let all: [SpotlightAction] = [
        SpotlightAction(
            id: "refresh",
            titleKey: "spotlight.action.refresh.title",
            subtitleKey: "spotlight.action.refresh.subtitle",
            symbol: "arrow.clockwise",
            tint: .accentColor,
            perform: { store in
                Task { await store.bootstrap() }
            }
        ),
        SpotlightAction(
            id: "link-health",
            titleKey: "spotlight.action.linkHealth.title",
            subtitleKey: "spotlight.action.linkHealth.subtitle",
            symbol: "stethoscope",
            tint: .orange,
            perform: { store in
                store.currentSelection = .health
            }
        ),
        SpotlightAction(
            id: "updates",
            titleKey: "spotlight.action.updates.title",
            subtitleKey: "spotlight.action.updates.subtitle",
            symbol: "arrow.triangle.2.circlepath",
            tint: .blue,
            perform: { store in
                store.currentSelection = .updates
            }
        ),
        SpotlightAction(
            id: "settings",
            titleKey: "spotlight.action.settings.title",
            subtitleKey: "spotlight.action.settings.subtitle",
            symbol: "gearshape",
            tint: .gray,
            perform: { store in
                store.currentSelection = .settings
            }
        )
    ]
}
