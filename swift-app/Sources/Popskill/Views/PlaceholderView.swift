import SwiftUI

/// Shared placeholder used by every v0.3 view file during the S2-S6 build-out.
/// Each subsequent sprint replaces the corresponding view's body with its real
/// implementation; this keeps the app launchable and navigable end-to-end
/// while individual sprints fill in the meat.
struct PlaceholderView: View {
    let symbol: String
    let titleKey: String
    let sprintLabel: String

    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            LocalizedText(titleKey)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.popLabel)
            Text(sprintLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .popPageBackground()
    }
}
