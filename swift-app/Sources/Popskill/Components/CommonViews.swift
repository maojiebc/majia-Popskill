import SwiftUI

struct AppToggle: View {
    let app: TargetApp
    let isOn: Bool
    let isPending: Bool
    let onChange: (Bool) -> Void
    var size: CGFloat = 28
    @Environment(\.popskillLocalization) private var localization

    private var cornerRadius: CGFloat {
        max(6, size * 0.34)
    }

    private var statusLabel: String {
        localization.string(isOn ? "common.enabled" : "common.disabled")
    }

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            ZStack {
                if isPending {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: app.symbolName)
                        .font(.system(size: max(10, size * 0.42), weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? app.accentColor : Color.popStatusNeutral)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .background(
            isOn ? app.accentColor.opacity(0.14) : Color.popCardBackground.opacity(0.34),
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(isOn ? app.accentColor.opacity(0.38) : Color.popBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .help(localization.string("appToggle.help", app.title, statusLabel))
        .accessibilityLabel(Text(app.title))
        .accessibilityValue(Text(statusLabel))
    }
}

struct AppToggleRow: View {
    let apps: [TargetApp]
    let isOn: (TargetApp) -> Bool
    let isPending: (TargetApp) -> Bool
    let onToggle: (TargetApp, Bool) -> Void
    var showsEnabledSummary: Bool = true
    var toggleSize: CGFloat = 26
    @Environment(\.popskillLocalization) private var localization

    private var enabledCount: Int {
        apps.filter { app in
            isOn(app)
        }.count
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(apps, id: \.id) { app in
                    AppToggle(
                        app: app,
                        isOn: isOn(app),
                        isPending: isPending(app),
                        onChange: { enabled in
                        onToggle(app, enabled)
                    },
                        size: toggleSize
                    )
                }
            }

            if showsEnabledSummary {
                Text("\(enabledCount)/\(apps.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.popCardBackground.opacity(0.52), in: Capsule())
                    .help(localization.string("appToggle.enabledSummary"))
                    .accessibilityLabel(Text(localization.string("appToggle.enabledSummary")))
                    .accessibilityValue(Text(localization.string("appToggle.enabledValue", enabledCount, apps.count)))
            }
        }
    }
}

struct AppCountBar: View {
    let apps: [TargetApp]
    let count: (TargetApp) -> Int
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        HStack(spacing: 6) {
            ForEach(apps, id: \.id) { app in
                let enabled = count(app)
                HStack(spacing: 4) {
                    Image(systemName: app.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(enabled > 0 ? app.accentColor : Color.popStatusNeutral)
                    Text("\(enabled)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    enabled > 0 ? app.accentColor.opacity(0.10) : Color.popCardBackground.opacity(0.44),
                    in: RoundedRectangle(cornerRadius: PopskillRadius.button, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PopskillRadius.button, style: .continuous)
                        .stroke(enabled > 0 ? app.accentColor.opacity(0.25) : Color.popBorder, lineWidth: 1)
                )
                .help(localization.string("appToggle.countHelp", app.title, enabled))
            }
        }
    }
}

// PackageAppCoverageBar removed in S2 — its mock dependency `PackageAppEnabledCount`
// lived inside LibraryViewModel. S3 will reintroduce coverage chips on the new
// matrix row if needed.

private extension TargetApp {
    var accentColor: Color {
        switch self {
        case .claude: .orange
        case .codex: .green
        case .gemini: .blue
        case .opencode: .indigo
        case .hermes: .purple
        }
    }
}

struct SummaryMetric: View {
    let title: String
    let value: Int
    var color: Color = .popLabel

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            LocalizedText(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 92, alignment: .trailing)
    }
}

struct InitialAvatarView: View {
    let name: String
    let identifier: String
    var size: CGFloat = 44

    private var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "S"
    }

    private var color: Color {
        let index = Self.stablePaletteIndex(for: identifier, paletteCount: Color.popAvatarPalette.count)
        return Color.popAvatarPalette[index]
    }

    static func stablePaletteIndex(for identifier: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else {
            return 0
        }

        var hash: UInt64 = 5381
        for byte in identifier.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash % UInt64(paletteCount))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PopskillRadius.smallCard)
                .fill(color.gradient)
            Text(initial)
                .font(.system(size: max(10, size * 0.45), weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        LocalizedText(title)
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
            Button(action: onRetry) {
                LocalizedText("Retry")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.popStatusWarning.opacity(0.08))
    }
}

struct LocalizedLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            LocalizedText(title)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    var accent: Color = .popSectionOrange
    @ViewBuilder var content: Content

    var body: some View {
        PopskillCard(padding: 16, cornerRadius: PopskillRadius.card) {
            SectionHeading(title: title, accent: accent)
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
            LocalizedText(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

struct SectionHeading: View {
    let title: String
    var accent: Color = .popSectionOrange

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 4, height: 13)
            LocalizedText(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(accent)
        }
    }
}
