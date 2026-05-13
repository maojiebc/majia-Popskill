import SwiftUI

struct PopskillCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = PopskillRadius.largeCard
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .popMaterialCard(cornerRadius: cornerRadius)
    }
}

struct PopskillSelectableCard<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = PopskillRadius.largeCard
    @ViewBuilder var content: Content
    @State private var isHovering = false

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                    if isHovering && !isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(0.035))
                    }
                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.36) : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.25 : 0.7
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.055 : 0.032), radius: isSelected ? 12 : 8, x: 0, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onTapGesture(perform: action)
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.16), value: isSelected)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

struct PopskillSectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LocalizedText(title)
                .font(.popHeadline)
                .foregroundStyle(Color.popLabel)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.popFootnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PopMaterialCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let borderOpacity: Double
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: 10, x: 0, y: 3)
    }
}

extension View {
    func popMaterialCard(
        cornerRadius: CGFloat = PopskillRadius.largeCard,
        borderOpacity: Double = 0.08,
        shadowOpacity: Double = 0.032
    ) -> some View {
        modifier(
            PopMaterialCardModifier(
                cornerRadius: cornerRadius,
                borderOpacity: borderOpacity,
                shadowOpacity: shadowOpacity
            )
        )
    }
}
