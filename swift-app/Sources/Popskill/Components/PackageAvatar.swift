import SwiftUI

struct PackageAvatar: View {
    let name: String
    let identifier: String
    var size: CGFloat = 44

    private var initials: String {
        Self.computeInitials(for: name)
    }

    private var color: Color {
        let index = Self.stablePaletteIndex(for: identifier, paletteCount: Color.popAvatarPalette.count)
        return Color.popAvatarPalette[index]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initials)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospaced()
                .minimumScaleFactor(0.78)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(name)
    }

    static func computeInitials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = trimmed
            .split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)

        let letters: String
        if segments.count <= 1 {
            letters = firstAlphanumericCharacters(in: trimmed, maxCount: 2)
        } else {
            letters = segments
                .prefix(segments.count == 2 ? 2 : 3)
                .compactMap(firstAlphanumericCharacter)
                .map(String.init)
                .joined()
        }

        let normalized = letters.uppercased()
        return normalized.isEmpty ? "S" : normalized
    }

    static func stablePaletteIndex(for identifier: String, paletteCount: Int) -> Int {
        InitialAvatarView.stablePaletteIndex(for: identifier, paletteCount: paletteCount)
    }

    private var fontSize: CGFloat {
        switch initials.count {
        case 0...2:
            return size * 0.44
        default:
            return size * 0.36
        }
    }

    private static func firstAlphanumericCharacter(in value: String) -> Character? {
        value.first { character in
            character.isLetter || character.isNumber
        }
    }

    private static func firstAlphanumericCharacters(in value: String, maxCount: Int) -> String {
        String(value.filter { $0.isLetter || $0.isNumber }.prefix(maxCount))
    }
}
