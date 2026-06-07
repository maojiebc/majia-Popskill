import SwiftUI

/// Root window. Custom warm-paper `LedgerSidebar` (6 prototype destinations, no
/// native List chrome) on the left, the selected screen on the right, plus the
/// ⌘K Spotlight overlay, global error toast, and first-run onboarding sheet.
@MainActor
struct RootView: View {
    @State private var store = PopskillStore()
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                LedgerTitlebar(store: store)
                HStack(spacing: 0) {
                    LedgerSidebar(store: store)
                    detailArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
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

            // Global error toast — pinned to top of the window.
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
        .background(Color.popCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.popBorder, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
        .padding(.top, 50)
        .padding(.horizontal, 24)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailArea: some View {
        switch store.currentSelection {
        case .matrix:   MatrixView(store: store)
        case .fix:      FixView(store: store)
        case .sources:  SourcesView(store: store)
        case .create:   CreateCapabilityView(store: store)
        case .compose:  ComposeBundleView(store: store)
        case .settings: SettingsView(store: store)
        }
    }
}
