import SwiftUI

struct AppToggle: View {
    let title: String
    let isOn: Bool
    let isPending: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 5) {
                if isPending {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? Color.accentColor : Color.popStatusNeutral)
                }
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 74, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .background(isOn ? Color.popHighlightFill : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isOn ? Color.accentColor.opacity(0.25) : Color.popBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .help(title)
    }
}

struct SummaryMetric: View {
    let title: String
    let value: Int
    var color: Color = .popLabel

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 86, alignment: .trailing)
    }
}

struct InitialAvatarView: View {
    let name: String
    let identifier: String

    private var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "S"
    }

    private var color: Color {
        let palette: [Color] = [.orange, .purple, .blue, .green, .pink, .teal]
        let index = Int(identifier.hashValue.magnitude % UInt(palette.count))
        return palette[index]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.gradient)
            Text(initial)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }
}

struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.10), in: Capsule())
    }
}

struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.popStatusWarning)
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: onRetry)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.popStatusWarning.opacity(0.08))
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.popSecondaryLabel)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

struct DetailField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}
