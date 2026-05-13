import SwiftUI

extension Color {
    static let popMainBackground = Color(.windowBackgroundColor)
    static let popCardBackground = Color(.controlBackgroundColor)
    static let popHeaderBackground = Color(.unemphasizedSelectedContentBackgroundColor)
    static let popSeparator = Color(.separatorColor)
    static let popBorder = Color(.separatorColor).opacity(0.58)

    static let popLabel = Color(.labelColor)
    static let popSecondaryLabel = Color(.secondaryLabelColor)
    static let popTertiaryLabel = Color(.tertiaryLabelColor)
    static let popSidebarHeader = Color(.secondaryLabelColor)
    static let popSidebarTitle = Color(.labelColor)

    static let popHoverFill = Color(.controlAccentColor).opacity(0.08)
    static let popHighlightFill = Color(.controlAccentColor).opacity(0.16)

    static let popSectionOrange = Color.orange
    static let popSectionPurple = Color.purple
    static let popSectionBlue = Color.blue
    static let popSectionGreen = Color.green

    static let popStatusOK = Color.green
    static let popStatusWarning = Color.orange
    static let popStatusError = Color.red
    static let popStatusNeutral = Color(.secondaryLabelColor)

    static let popAvatarPalette: [Color] = [
        .orange,
        .purple,
        .blue,
        .green,
        .pink,
        .teal
    ]
}

enum PopskillSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum PopskillRadius {
    static let button: CGFloat = 8
    static let smallCard: CGFloat = 12
    static let card: CGFloat = 18
    static let largeCard: CGFloat = 20
}

enum PopskillSectionAccent {
    static let colors: [Color] = [
        .popSectionOrange,
        .popSectionPurple,
        .popSectionBlue,
        .popSectionGreen
    ]

    static func index(for position: Int) -> Int {
        guard !colors.isEmpty else {
            return 0
        }
        return ((position % colors.count) + colors.count) % colors.count
    }

    static func color(for position: Int) -> Color {
        colors[index(for: position)]
    }
}

struct PopskillCanvasBackground: View {
    var body: some View {
        ZStack {
            Color.popMainBackground
            LinearGradient(
                colors: [
                    Color.popHeaderBackground.opacity(0.30),
                    Color.popSectionBlue.opacity(0.045),
                    Color.popSectionOrange.opacity(0.030)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct PopPageBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            PopskillCanvasBackground()
        }
    }
}

private struct PopCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let borderOpacity: Double
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08 * borderOpacity), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func popPageBackground() -> some View {
        modifier(PopPageBackgroundModifier())
    }

    func popCard(
        cornerRadius: CGFloat = PopskillRadius.card,
        borderOpacity: Double = 1,
        shadowOpacity: Double = 0.035
    ) -> some View {
        modifier(
            PopCardModifier(
                cornerRadius: cornerRadius,
                borderOpacity: borderOpacity,
                shadowOpacity: shadowOpacity
            )
        )
    }
}
