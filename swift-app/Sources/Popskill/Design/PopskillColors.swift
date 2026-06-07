import SwiftUI

// MARK: - Hex initializer

extension Color {
    /// Build a Color from a 0xRRGGBB integer (sRGB) with optional opacity.
    /// The whole warm-paper palette below is authored as fixed hex, so this is
    /// the one place that knows how to turn a design token into a `Color`.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Ledger palette ("01 紧凑账本" — warm-paper, light-only)
//
// Every screen references these `pop*` tokens, so repointing them here reskins
// the entire app to the warm-paper ledger language in one place. The design is
// light-only by intent (the app forces `.light` in PopskillApp); these are
// fixed sRGB values rather than adaptive system colors on purpose.

extension Color {
    // Surfaces
    static let popMainBackground = Color(hex: 0xFAFAF8)    // window / page base (奶白)
    static let popSurface = Color(hex: 0xF4F2EC)           // sidebar / titlebar / statusbar / group header
    static let popHeaderBackground = Color(hex: 0xF4F2EC)
    static let popSurfaceElevated = Color(hex: 0xFFFFFF)   // table surface
    static let popCardBackground = Color(hex: 0xFFFFFF)    // white surfaces / inverse text on black chips
    static let popControlFill = Color(hex: 0xFFFFFF)       // search pill / unselected chip background
    static let popSubtleFill = Color(hex: 0xF4F1E8)        // bundle parent row tint
    static let popChildRowFill = Color(hex: 0xFCFBF6)      // bundle child row tint

    // Hover / selection — single electric-blue accent
    static let popSurfaceHover = Color(hex: 0x1F4ED8, opacity: 0.05)
    static let popSelectedRowFill = Color(hex: 0x1F4ED8, opacity: 0.10)
    static let popHoverFill = Color(hex: 0x1F4ED8, opacity: 0.06)
    static let popHighlightFill = Color(hex: 0x1F4ED8, opacity: 0.16)
    static let popAccentSoft = Color(hex: 0x1F4ED8, opacity: 0.12)
    static let popSearchHighlight = Color(hex: 0xFDE68A)   // search match (yellow)

    // Lines / borders — hairlines
    static let popSeparator = Color(hex: 0xE8E6DF)
    static let popBorder = Color(hex: 0xE8E6DF)
    static let popCardStroke = Color(hex: 0xE8E6DF)
    static let popControlStroke = Color(hex: 0xD8D5CB)
    static let popSubtleStroke = Color(hex: 0xE8E6DF)
    static let popRowDivider = Color(hex: 0xEFEDE5)        // lighter table row divider

    // Text
    static let popLabel = Color(hex: 0x111111)
    static let popSecondaryLabel = Color(hex: 0x7C7869)
    static let popTertiaryLabel = Color(hex: 0x9A9684)
    static let popSidebarHeader = Color(hex: 0x9A9684)
    static let popSidebarTitle = Color(hex: 0x3A382F)

    // Table header
    static let popTableHeaderFill = Color(hex: 0xFAFAF8)

    // Backdrop / shadow
    static let popBackdropScrim = Color.black.opacity(0.30)
    static let popShadow = Color.black

    // Brand accent — single electric blue
    static let popAccent = Color(hex: 0x1F4ED8)

    // Link-status glyphs (matrix ● / — / ◐ / ✕)
    static let popLinkOn = Color(hex: 0x1F4ED8)      // ● blue
    static let popLinkOff = Color(hex: 0xCDC8B9)     // — gray
    static let popLinkStub = Color(hex: 0xB88300)    // ◐ amber
    static let popLinkBroken = Color(hex: 0xC01818)  // ✕ red

    // Coverage bar segments (bundle fraction mini-bar)
    static let popCoverageOn = Color(hex: 0x1F4ED8)
    static let popCoverageStub = Color(hex: 0xE1A51A)
    static let popCoverageBroken = Color(hex: 0xC01818)
    static let popCoverageOff = Color(hex: 0xE6E2D4)

    // Section accents — kept for any kind-banner usage, muted into the palette
    static let popSectionOrange = Color(hex: 0xB88300)
    static let popSectionPurple = Color(hex: 0x7C5CBF)
    static let popSectionBlue = Color(hex: 0x1F4ED8)
    static let popSectionGreen = Color(hex: 0x1A7D4E)

    // Semantic status
    static let popStatusOK = Color(hex: 0x1A9A4E)       // sync green
    static let popStatusWarning = Color(hex: 0xB88300)  // amber
    static let popStatusError = Color(hex: 0xC01818)    // red
    static let popStatusNeutral = Color(hex: 0x9A9684)

    static let popAvatarPalette: [Color] = [
        Color(hex: 0xB88300),
        Color(hex: 0x7C5CBF),
        Color(hex: 0x1F4ED8),
        Color(hex: 0x1A7D4E),
        Color(hex: 0xC0508A),
        Color(hex: 0x2C8A8A)
    ]
}

// MARK: - Type-tag palette (capability kind → colored tag)

enum LedgerTypeTagPalette {
    /// border / text / fill for the `LedgerTypeTag` shown in the matrix 类型 column.
    static func colors(for kind: CapabilityKind) -> (border: Color, text: Color, fill: Color) {
        switch kind {
        case .skill:
            return (Color(hex: 0xC9B478), Color(hex: 0x5A4A14), Color(hex: 0xC9B478, opacity: 0.16))
        case .agent:
            return (Color(hex: 0x7FAACD), Color(hex: 0x1D3C63), Color(hex: 0x7FAACD, opacity: 0.16))
        case .mcp:
            return (Color(hex: 0xA98CC9), Color(hex: 0x3C1D5A), Color(hex: 0xA98CC9, opacity: 0.16))
        case .cli:
            return (Color(hex: 0x74B291), Color(hex: 0x1A4D33), Color(hex: 0x74B291, opacity: 0.16))
        case .bundle:
            return (Color(hex: 0x111111), Color(hex: 0xFFFFFF), Color(hex: 0x111111))
        case .config:
            return (Color(hex: 0x9A9684), Color(hex: 0x5E5A4E), Color(hex: 0x9A9684, opacity: 0.16))
        }
    }
}

// MARK: - Spacing / radius / shadow tokens (unchanged)

enum PopskillSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum PopskillRadius {
    static let button: CGFloat = 6
    static let smallCard: CGFloat = 8
    static let card: CGFloat = 8
    static let largeCard: CGFloat = 12
}

enum PopskillShadow {
    static let cardRadius: CGFloat = 12
    static let cardYOffset: CGFloat = 3
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
        Color.popMainBackground
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
            .background(Color.popCardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.popCardStroke.opacity(borderOpacity), lineWidth: 0.7)
            )
            .shadow(color: Color.popShadow.opacity(shadowOpacity), radius: PopskillShadow.cardRadius, x: 0, y: PopskillShadow.cardYOffset)
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
