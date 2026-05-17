import SwiftUI

/// New v0.3 RootView — replaces the 11→7 sidebar single-flat list of v0.1-v0.2
/// with 3 sectioned groups (操控台 / 来源 / 维护) + Settings + Spotlight trigger.
/// Each detail-area view is its own file and pulls data straight off the
/// shared `PopskillStore`.
struct RootView: View {
    @State private var store = PopskillStore()
    @Environment(\.popskillLocalization) private var localization

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
            .accessibilityLabel(Text("Dismiss"))
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
