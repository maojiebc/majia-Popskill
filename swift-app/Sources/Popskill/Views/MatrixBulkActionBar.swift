import SwiftUI

@MainActor
struct MatrixBulkActionBar: View {
    let store: PopskillStore
    let capabilities: [MatrixCapability]
    let onExport: ([MatrixCapability]) -> Void
    @Environment(\.popskillLocalization) private var localization

    private var summary: MatrixBulkSelectionSummary {
        store.matrixBulkSelectionSummary(capabilities: capabilities)
    }

    var body: some View {
        if summary.hasSelection {
            HStack(spacing: 0) {
                MatrixBulkCountSegment(summary: summary)
                MatrixBulkActionButton(
                    titleKey: "matrix.bulk.enableClaude",
                    systemImage: TargetApp.claude.symbolName,
                    tint: TargetApp.claude.matrixBulkTint,
                    action: .enableClaude,
                    inFlightAction: store.matrixBulkActionInFlight,
                    perform: enableClaude
                )
                MatrixBulkActionButton(
                    titleKey: "matrix.bulk.enableCodex",
                    systemImage: TargetApp.codex.symbolName,
                    tint: TargetApp.codex.matrixBulkTint,
                    action: .enableCodex,
                    inFlightAction: store.matrixBulkActionInFlight,
                    perform: enableCodex
                )
                MatrixBulkActionButton(
                    titleKey: "matrix.bulk.update",
                    systemImage: "arrow.up.circle",
                    tint: Color(hex: 0x7FAACD),
                    action: .update,
                    inFlightAction: store.matrixBulkActionInFlight,
                    disabled: store.matrixBulkSelectedUpdates(capabilities: capabilities).isEmpty,
                    perform: updateSelected
                )
                MatrixBulkActionButton(
                    titleKey: "matrix.bulk.export",
                    systemImage: "arrow.down.doc",
                    tint: Color(hex: 0xB8C0CC),
                    action: .export,
                    inFlightAction: store.matrixBulkActionInFlight,
                    perform: exportSelected
                )
                MatrixBulkActionButton(
                    titleKey: "matrix.bulk.uninstall",
                    systemImage: "minus.circle",
                    tint: Color(hex: 0xFF8A7A),
                    action: .uninstall,
                    inFlightAction: store.matrixBulkActionInFlight,
                    disabled: true,
                    perform: {}
                )
                Button {
                    store.clearMatrixBulkSelection()
                } label: {
                    MatrixBulkCancelLabel()
                }
                .buttonStyle(.plain)
                .help(localization.string("matrix.bulk.cancel"))
            }
            .background(Color(hex: 0x15161A), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: Color.black.opacity(0.28), radius: 18, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.38), lineWidth: 1)
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.16), value: summary.selectedRowCount)
        }
    }

    private func enableClaude() {
        Task {
            await store.matrixBulkSetSelectedSkills(app: .claude, enabled: true, capabilities: capabilities)
        }
    }

    private func enableCodex() {
        Task {
            await store.matrixBulkSetSelectedSkills(app: .codex, enabled: true, capabilities: capabilities)
        }
    }

    private func updateSelected() {
        Task {
            await store.matrixBulkUpdateSelectedSkills(capabilities: capabilities)
        }
    }

    private func exportSelected() {
        onExport(capabilities)
    }
}

private struct MatrixBulkCountSegment: View {
    let summary: MatrixBulkSelectionSummary
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        HStack(spacing: 8) {
            Text("\(summary.topLevelCount)")
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(localization.string("matrix.bulk.selected"))
                .font(.system(size: 12.5, weight: .semibold))
            if summary.leafCount != summary.topLevelCount {
                Text(localization.string("matrix.bulk.leafCount", summary.leafCount))
                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.70))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(Color.popAccent)
    }
}

private struct MatrixBulkActionButton: View {
    let titleKey: String
    let systemImage: String
    let tint: Color
    let action: MatrixBulkAction
    let inFlightAction: MatrixBulkAction?
    var disabled = false
    let perform: () -> Void
    @Environment(\.popskillLocalization) private var localization

    private var inFlight: Bool { inFlightAction == action }

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 7) {
                if inFlight {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(tint)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 14, height: 14)
                }
                Text(localization.string(titleKey))
                    .font(.system(size: 12.2, weight: .medium))
            }
            .foregroundStyle(disabled ? Color(hex: 0x7B8290) : Color(hex: 0xE6E9EC))
            .padding(.horizontal, 13)
            .frame(height: 38)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled || inFlightAction != nil)
        .help(localization.string(disabled && action == .uninstall ? "matrix.bulk.uninstallDisabled" : titleKey))
    }
}

private struct MatrixBulkCancelLabel: View {
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 12, weight: .semibold))
            Text(localization.string("matrix.bulk.cancel"))
                .font(.system(size: 12.2, weight: .medium))
        }
        .foregroundStyle(Color(hex: 0x9CA3AF))
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

struct MatrixBulkCheckbox: View {
    let state: MatrixBulkSelectionState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(state.isActive ? Color.popAccent : Color.popControlFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(state.isActive ? Color.popAccent : Color.popControlStroke, lineWidth: 1.4)
                )
            if state.isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            } else if state.isMixed {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 7, height: 1.7)
                    .clipShape(Capsule())
            }
        }
        .frame(width: 15, height: 15)
    }
}

private extension TargetApp {
    var matrixBulkTint: Color {
        switch self {
        case .claude: Color(hex: 0xF3A45B)
        case .codex: Color(hex: 0x5FD29C)
        case .gemini: Color(hex: 0x7FAACD)
        case .opencode: Color(hex: 0xB8C0CC)
        case .hermes: Color(hex: 0xB8C0CC)
        }
    }
}
