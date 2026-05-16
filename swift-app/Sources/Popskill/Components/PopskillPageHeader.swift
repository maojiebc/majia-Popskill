import SwiftUI

/// Unified page header used by every top-level view. Encapsulates:
/// - title rendered with `popLargeTitle` (34pt bold)
/// - optional subtitle rendered with `popSubheadline` + `popSecondaryLabel`
/// - trailing slot for toolbar buttons / SummaryMetric clusters
/// - optional secondary row for filter pickers, sort chips, etc.
///
/// Standard padding (28 horizontal, 24 top, 18 bottom) is baked in so callers
/// don't drift from the design token. Removing this drift was the central goal
/// of the visual refactor that introduced this component — five of the seven
/// top-level views were using `Text(...).font(.system(.largeTitle, weight: .bold))`
/// with hand-rolled padding before.
struct PopskillPageHeader<Trailing: View, Secondary: View>: View {
    private let titleKey: String
    private let subtitle: String?
    private let trailing: () -> Trailing
    private let secondary: () -> Secondary

    init(
        titleKey: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder secondary: @escaping () -> Secondary
    ) {
        self.titleKey = titleKey
        self.subtitle = subtitle
        self.trailing = trailing
        self.secondary = secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText(titleKey)
                        .font(.popLargeTitle)
                        .foregroundStyle(Color.popLabel)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.popSubheadline)
                            .foregroundStyle(Color.popSecondaryLabel)
                    }
                }

                Spacer(minLength: 16)

                trailing()
            }

            secondary()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }
}

extension PopskillPageHeader where Secondary == EmptyView {
    init(
        titleKey: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            titleKey: titleKey,
            subtitle: subtitle,
            trailing: trailing,
            secondary: { EmptyView() }
        )
    }
}

extension PopskillPageHeader where Trailing == EmptyView, Secondary == EmptyView {
    init(titleKey: String, subtitle: String? = nil) {
        self.init(
            titleKey: titleKey,
            subtitle: subtitle,
            trailing: { EmptyView() },
            secondary: { EmptyView() }
        )
    }
}
