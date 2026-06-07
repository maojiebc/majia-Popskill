import SwiftUI

// Shared building blocks for the "01 紧凑账本" ledger design language.
// Used by the matrix (and reusable by the other ledger screens).

// MARK: - Type tag (matrix 类型 column)

/// Colored capability-type tag: Skill 金 / Agent 青蓝 / MCP 紫 / CLI 绿 /
/// Bundle 实心黑 / Config 灰. Replaces the old inline kind badge.
struct LedgerTypeTag: View {
    let kind: CapabilityKind
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        let palette = LedgerTypeTagPalette.colors(for: kind)
        Text(localization.string(kind.titleKey).uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(palette.text)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(palette.fill, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(kind == .bundle ? Color.clear : palette.border.opacity(0.9), lineWidth: 0.8)
            )
    }
}

// MARK: - Link-status glyph (matrix Claude / Codex cells)

/// The four link states a capability can have against one tool.
enum LedgerLinkState {
    case on, off, stub, broken

    var glyph: String {
        switch self {
        case .on: return "●"
        case .off: return "—"
        case .stub: return "◐"
        case .broken: return "✕"
        }
    }

    var color: Color {
        switch self {
        case .on: return .popLinkOn
        case .off: return .popLinkOff
        case .stub: return .popLinkStub
        case .broken: return .popLinkBroken
        }
    }
}

/// A status glyph (●/—/◐/✕) that stays tappable when `onToggle` is provided.
/// The affordance changed from a switch to a glyph, but the toggle behavior is
/// preserved: tapping a skill cell flips that tool's link.
struct LedgerStatusGlyph: View {
    let state: LedgerLinkState
    var isPending: Bool = false
    var help: String? = nil
    var onToggle: (() -> Void)? = nil

    var body: some View {
        let glyph = Text(state.glyph)
            .font(.system(size: 14, weight: state == .off ? .regular : .bold, design: .monospaced))
            .foregroundStyle(state.color)
            .frame(width: 26, height: 26)
            .opacity(isPending ? 0.4 : 1)
            .contentShape(Rectangle())

        return Group {
            if let onToggle {
                Button(action: onToggle) { glyph }
                    .buttonStyle(.plain)
                    .disabled(isPending)
            } else {
                glyph
            }
        }
        .help(help ?? "")
    }
}

// MARK: - Bundle coverage (matrix Claude / Codex cells on package rows)

/// Fraction `7/8` over a 36×3 mini bar: blue = enabled share, neutral = rest.
/// (Full on/stub/broken/off segmentation would need per-app counts on the
/// package model; the enabled-vs-rest split reads the same at a glance.)
struct LedgerCoverageBar: View {
    let enabled: Int
    let total: Int
    var help: String? = nil

    private var ratioColor: Color {
        guard total > 0, enabled > 0 else { return .popTertiaryLabel }
        return enabled == total ? .popLinkOn : .popLinkStub
    }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(enabled)/\(total)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(ratioColor)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.popCoverageOn)
                        .frame(width: total > 0 ? geo.size.width * CGFloat(enabled) / CGFloat(total) : 0)
                    Rectangle().fill(Color.popCoverageOff)
                }
            }
            .frame(width: 36, height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .help(help ?? "")
    }
}

// MARK: - Foot status bar (window foot under the matrix)

/// `~/.popskill/store · N symlinks · 断链/占位 · 同步于 … · popskill vX`.
struct LedgerStatusBar: View {
    let store: PopskillStore
    /// Total active tool-links (precomputed by the caller from `capabilities`).
    let symlinks: Int
    @Environment(\.popskillLocalization) private var localization

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 9) {
            Text(verbatim: "~/.popskill/store")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: 0x5E5A4E))
            separator
            Text(localization.string("matrix.statusbar.symlinks", symlinks))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: 0x5E5A4E))
            separator
            Text(localization.string("matrix.statusbar.health", store.brokenLinkCount, store.stubs.count))
                .font(.system(size: 11))
                .foregroundStyle(Color.popSecondaryLabel)

            Spacer(minLength: 8)

            Circle()
                .fill(syncIsActionable ? Color.popStatusOK : Color.popLinkOff)
                .frame(width: 6, height: 6)
            Text(syncText)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x5A7A5F))
            separator
            Text(localization.string("matrix.statusbar.version", appVersion))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: 0x5E5A4E))
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 26)
        .background(Color.popSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.popSeparator).frame(height: 0.7)
        }
    }

    private var separator: some View {
        Text(verbatim: "·").foregroundStyle(Color(hex: 0xC4BFB0))
    }

    private var syncIsActionable: Bool {
        (SyncProvider(rawValue: store.lastSyncProvider) ?? .git).actionable
    }

    private var syncText: String {
        guard syncIsActionable, let at = store.lastSyncAt else {
            return localization.string("matrix.statusbar.syncNever")
        }
        let relative = Self.relativeFormatter.localizedString(for: at, relativeTo: Date())
        return localization.string("matrix.statusbar.syncedAt", relative)
    }

    private var appVersion: String {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !v.isEmpty {
            return "popskill v\(v)"
        }
        return "popskill"
    }
}

// MARK: - Buttons & segmented control

/// Ghost (outline) button used in ledger screen heroes.
struct LedgerGhostButton: View {
    let titleKey: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LocalizedText(titleKey)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.popLabel)
                .padding(.horizontal, 13)
                .frame(height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.popControlStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Solid-black primary button used in ledger screen heroes.
struct LedgerPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Color.popLabel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LedgerSegmentOption {
    let label: String
    var dot: Color? = nil
}

/// Segmented control: black-fill selected segment, optional leading dot.
struct LedgerSegmented: View {
    let options: [LedgerSegmentOption]
    let selection: String
    var fill: Bool = false
    let onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let active = option.label == selection
                Button { onPick(option.label) } label: {
                    HStack(spacing: 6) {
                        if let dot = option.dot {
                            Circle().fill(dot).frame(width: 7, height: 7)
                        }
                        Text(option.label)
                            .font(.system(size: 12, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? .white : Color(hex: 0x5E5A4E))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .background(active ? Color.popLabel : Color.clear)
                    .overlay(alignment: .trailing) {
                        if index < options.count - 1 {
                            Rectangle().fill(Color(hex: 0xECE9E0)).frame(width: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.popControlStroke, lineWidth: 1)
        )
        .fixedSize(horizontal: !fill, vertical: true)
    }
}
