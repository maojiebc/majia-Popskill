import SwiftUI

/// New v0.3 RootView — replaces the 11→7 sidebar single-flat list of v0.1-v0.2
/// with 3 sectioned groups (操控台 / 来源 / 维护) + Settings + Spotlight trigger.
/// Each detail-area view is its own file and pulls data straight off the
/// shared `PopskillStore`.
@MainActor
struct RootView: View {
    @State private var store = PopskillStore()
    @Environment(\.popskillLocalization) private var localization
    private static let sidebarRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        ZStack(alignment: .top) {
            NavigationSplitView {
                sidebar
            } detail: {
                detailArea
            }
            .navigationSplitViewStyle(.balanced)
            .background(PopskillCanvasBackground())

            // Invisible button registers the ⌘K shortcut. Placing it inside the
            // ZStack rather than .background keeps the shortcut active in every
            // detail view (including ones that swallow keyboard via TextField).
            Button("") { store.spotlightOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if store.spotlightOpen {
                SpotlightView(store: store)
                    .zIndex(1)
            }

            // Global error toast — pinned to top of the window. Before this
            // existed, `store.errorMessage` was written by every sidecar
            // failure but never displayed, so users hit silent breakage.
            // Dismiss with the X button or by `store.errorMessage = nil`.
            if let message = store.errorMessage {
                errorToast(message: message)
                    .zIndex(2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.14), value: store.spotlightOpen)
        .animation(.easeOut(duration: 0.14), value: store.errorMessage)
        .task {
            await store.bootstrap()
            // First launch hook: open wizard if the user has never finished
            // onboarding AND the bootstrap shows an empty world. Avoids
            // re-prompting when a user already has the matrix populated.
            if !OnboardingState.hasFinished() && store.skills.isEmpty {
                store.onboardingOpen = true
            }
        }
        .sheet(isPresented: $store.onboardingOpen) {
            OnboardingWizardView(store: store)
        }
        .frame(minWidth: 1180, minHeight: 720)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: Binding(
            get: { store.currentSelection },
            set: { if let new = $0 { store.currentSelection = new } }
        )) {
            Section {
                row(.matrix)
                matrixShortcutRows
                sidebarSyncStatus
            } header: { sectionHeader(.control) }

            Section {
                row(.sources)
            } header: { sectionHeader(.sources) }

            Section {
                row(.updates, badge: store.pendingUpdateCount, warning: true)
                row(.backups, badge: store.backups.count)
                row(.idle)
                row(.insights)
                row(.health, badge: store.brokenLinkCount, warning: store.brokenLinkCount > 0)
            } header: { sectionHeader(.maintenance) }

            Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
    }

    @ViewBuilder
    private func sectionHeader(_ group: SidebarGroup) -> some View {
        if let key = group.titleKey {
            LocalizedText(key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.popTertiaryLabel)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    @ViewBuilder
    private func row(_ item: SidebarSelection, badge: Int? = nil, warning: Bool = false) -> some View {
        NavigationLink(value: item) {
            HStack(spacing: 9) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18)
                LocalizedText(item.titleKey)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(warning ? Color.popStatusWarning : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                (warning ? Color.popStatusWarning : Color.secondary).opacity(0.14)
                            )
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var matrixShortcutRows: some View {
        let statusFilters: [MatrixFilter] = [.claudeOnly, .codexOnly, .brokenLinks]
        let typeFilters: [MatrixTypeFilter] = [.bundle, .skill, .agent, .mcp, .cli]
        if !store.capabilities.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                shortcutHeader("sidebar.matrixFilters")
                ForEach(statusFilters) { filter in
                    let count = store.matrixFilterCount(filter)
                    if count > 0 {
                        sidebarShortcutButton(
                            titleKey: filter.titleKey,
                            count: count,
                            symbolName: sidebarSymbol(for: filter),
                            warning: filter == .brokenLinks,
                            active: store.currentSelection == .matrix
                                && store.matrixFilter == filter
                                && store.matrixTypeFilter == .allTypes
                        ) {
                            store.showMatrix(filter: filter)
                        }
                    }
                }

                shortcutHeader("sidebar.matrixTypes")
                    .padding(.top, 4)
                ForEach(typeFilters) { filter in
                    let count = store.matrixTypeFilterCount(filter)
                    if count > 0 {
                        sidebarShortcutButton(
                            titleKey: filter.titleKey,
                            count: count,
                            symbolName: sidebarSymbol(for: filter),
                            active: store.currentSelection == .matrix
                                && store.matrixFilter == .all
                                && store.matrixTypeFilter == filter
                        ) {
                            store.showMatrix(typeFilter: filter)
                        }
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
            .listRowInsets(EdgeInsets(top: 2, leading: 18, bottom: 6, trailing: 12))
        }
    }

    private var sidebarSyncStatus: some View {
        let provider = SyncProvider(rawValue: store.lastSyncProvider) ?? .git
        let statusTint = provider.actionable ? Color.accentColor : Color.popStatusWarning
        return Button {
            store.showSettings()
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(localization.string("sidebar.sync"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.popTertiaryLabel)
                        .textCase(.uppercase)
                        .tracking(0.4)
                    Spacer(minLength: 8)
                    Label(localization.string("sidebar.sync.settings"), systemImage: "gearshape")
                        .font(.system(size: 10.5, weight: .medium))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
                HStack(spacing: 8) {
                    Image(systemName: provider.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(statusTint)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(localization.string(provider.titleKey))
                            .font(.system(size: 12.2, weight: .medium))
                            .foregroundStyle(Color.popSidebarTitle)
                            .lineLimit(1)
                        Text(syncStatusSubtitle(provider: provider))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.popSecondaryLabel)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Circle()
                        .fill(statusTint)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.popControlFill.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.popControlStroke.opacity(0.75), lineWidth: 0.7)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(localization.string("sidebar.sync.openSettings"))
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 12))
    }

    private func syncStatusSubtitle(provider: SyncProvider) -> String {
        if !provider.actionable {
            return localization.string("settings.sync.soon")
        }
        guard let lastSyncAt = store.lastSyncAt else {
            return localization.string("sidebar.sync.never")
        }
        let relative = Self.sidebarRelativeFormatter.localizedString(for: lastSyncAt, relativeTo: Date())
        return localization.string("sidebar.sync.last", relative)
    }

    private func shortcutHeader(_ key: String) -> some View {
        Text(localization.string(key))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.popTertiaryLabel)
            .textCase(.uppercase)
            .tracking(0.4)
            .padding(.leading, 4)
    }

    private func sidebarShortcutButton(
        titleKey: String,
        count: Int,
        symbolName: String,
        warning: Bool = false,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(active ? Color.accentColor : Color.popSecondaryLabel)
                    .frame(width: 16)
                Text(localization.string(titleKey))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.popSidebarTitle)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(warning && count > 0 ? Color.popStatusWarning : Color.popSecondaryLabel)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule().fill(
                            (warning && count > 0 ? Color.popStatusWarning : Color.popSecondaryLabel).opacity(0.13)
                        )
                    )
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                active ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func sidebarSymbol(for filter: MatrixFilter) -> String {
        switch filter {
        case .all:         return "square.grid.3x3"
        case .updates:     return "arrow.triangle.2.circlepath"
        case .brokenLinks: return "exclamationmark.triangle"
        case .claudeOnly:  return TargetApp.claude.symbolName
        case .codexOnly:   return TargetApp.codex.symbolName
        case .inactive:    return "moon"
        }
    }

    private func sidebarSymbol(for filter: MatrixTypeFilter) -> String {
        switch filter {
        case .allTypes: return "square.stack.3d.up"
        case .bundle:   return CapabilityKind.bundle.symbol
        case .skill:    return CapabilityKind.skill.symbol
        case .agent:    return CapabilityKind.agent.symbol
        case .cli:      return CapabilityKind.cli.symbol
        case .mcp:      return CapabilityKind.mcp.symbol
        }
    }

    // MARK: Error toast

    private func errorToast(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.popStatusWarning)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.popLabel)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 10)
            Button {
                store.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.popSecondaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(localization.string("common.dismiss")))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.popBorder, lineWidth: 0.5)
        )
        .padding(.top, 12)
        .padding(.horizontal, 24)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailArea: some View {
        switch store.currentSelection {
        case .matrix:   MatrixView(store: store)
        case .sources:  SourcesView(store: store)
        case .updates:  UpdatesView(store: store)
        case .backups:  BackupsView(store: store)
        case .idle:     IdleView(store: store)
        case .insights: InsightsView(store: store)
        case .health:   LinkHealthView(store: store)
        case .settings: SettingsView(store: store)
        }
    }
}
