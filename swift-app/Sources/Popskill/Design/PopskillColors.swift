import SwiftUI

extension Color {
    static let popMainBackground = Color(.windowBackgroundColor)
    static let popCardBackground = Color(.controlBackgroundColor)
    static let popHeaderBackground = Color(.unemphasizedSelectedContentBackgroundColor)
    static let popSeparator = Color(.separatorColor)
    static let popBorder = Color(.separatorColor).opacity(0.6)

    static let popLabel = Color(.labelColor)
    static let popSecondaryLabel = Color(.secondaryLabelColor)
    static let popTertiaryLabel = Color(.tertiaryLabelColor)

    static let popHoverFill = Color(.controlAccentColor).opacity(0.08)
    static let popHighlightFill = Color(.controlAccentColor).opacity(0.16)

    static let popStatusOK = Color.green
    static let popStatusWarning = Color.orange
    static let popStatusError = Color.red
    static let popStatusNeutral = Color(.secondaryLabelColor)
}
