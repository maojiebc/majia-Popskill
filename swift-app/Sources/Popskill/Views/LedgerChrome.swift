import SwiftUI

/// Custom warm-paper sidebar that replaces the native `List`-based sidebar.
/// Holds only the 6 prototype destinations (no filter shortcuts — those live as
/// chips above the matrix) with the design's restrained blue-tint selection.
struct LedgerSidebar: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    group("sidebar.section.view", [.matrix, .fix])
                    group("sidebar.section.acquire", [.sources])
                    group("sidebar.section.create", [.create, .compose])
                    group("sidebar.section.system", [.settings])
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 222)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.popSurface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.popSeparator).frame(width: 1)
        }
    }

    private func group(_ titleKey: String, _ items: [SidebarSelection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LocalizedText(titleKey)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.popSidebarHeader)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(items, id: \.self) { navItem($0) }
        }
    }

    private func navItem(_ selection: SidebarSelection) -> some View {
        let active = store.currentSelection == selection
        let danger = selection == .fix && store.brokenLinkCount > 0
        let tint: Color = active ? .popAccent : (danger ? .popStatusError : .popSidebarTitle)
        return Button {
            store.currentSelection = selection
        } label: {
            HStack(spacing: 9) {
                LocalizedText(selection.titleKey)
                    .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let badge = badge(selection), badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(active ? Color.popAccent : (danger ? Color.popStatusError : Color.popTertiaryLabel))
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                active ? Color.popAccentSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func badge(_ selection: SidebarSelection) -> Int? {
        switch selection {
        case .fix:     return store.brokenLinkCount
        case .sources: return store.pendingUpdateCount
        default:       return nil
        }
    }

    private var syncCard: some View {
        let provider = SyncProvider(rawValue: store.lastSyncProvider) ?? .git
        let tint = provider.actionable ? Color.popStatusOK : Color.popStatusWarning
        return Button {
            store.showSettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: provider.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    LocalizedText(provider.titleKey)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.popSidebarTitle)
                        .lineLimit(1)
                    Text(syncSubtitle(provider))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.popSecondaryLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Circle().fill(tint).frame(width: 7, height: 7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.popControlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.popControlStroke, lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
    }

    private func syncSubtitle(_ provider: SyncProvider) -> String {
        if !provider.actionable {
            return localization.string("settings.sync.soon")
        }
        guard let lastSyncAt = store.lastSyncAt else {
            return localization.string("sidebar.sync.never")
        }
        let relative = Self.relativeFormatter.localizedString(for: lastSyncAt, relativeTo: Date())
        return localization.string("sidebar.sync.last", relative)
    }
}

/// Custom full-width titlebar that sits above the split view (the native one is
/// hidden). Brand mark + crumb on the left, sync chip + ⌘K + settings on the
/// right. Leading inset clears the traffic lights.
struct LedgerTitlebar: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        HStack(spacing: 7) {
            brandMark
            Button { store.currentSelection = .matrix } label: {
                Text(verbatim: "Popskill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.popLabel)
            }
            .buttonStyle(.plain)

            if store.currentSelection != .matrix {
                HStack(spacing: 4) {
                    Text(verbatim: "/").foregroundStyle(Color.popTertiaryLabel)
                    LocalizedText(store.currentSelection.titleKey).foregroundStyle(Color.popSecondaryLabel)
                }
                .font(.system(size: 12.5))
            }

            Spacer(minLength: 12)

            syncChip
            pillButton { store.spotlightOpen = true } content: {
                Text(verbatim: "⌘K")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x666666))
            }
            pillButton { store.showSettings() } content: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.popSecondaryLabel)
            }
        }
        .padding(.leading, 80)
        .padding(.trailing, 12)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(Color.popSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.popSeparator).frame(height: 1)
        }
    }

    private var brandMark: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.popLabel)
            .frame(width: 18, height: 18)
            .overlay {
                // Symlink mark: two nodes joined by a diagonal link (matches the
                // prototype's brand SVG), not a chain-link glyph.
                Canvas { context, _ in
                    let white = GraphicsContext.Shading.color(.white)
                    var line = Path()
                    line.move(to: CGPoint(x: 7.9, y: 7.9))
                    line.addLine(to: CGPoint(x: 10.1, y: 10.1))
                    context.stroke(line, with: white, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    context.stroke(Path(ellipseIn: CGRect(x: 4.5, y: 4.5, width: 3.8, height: 3.8)), with: white, lineWidth: 1.3)
                    context.stroke(Path(ellipseIn: CGRect(x: 9.7, y: 9.7, width: 3.8, height: 3.8)), with: white, lineWidth: 1.3)
                }
                .frame(width: 18, height: 18)
            }
    }

    private func pillButton<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.popControlStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var syncChip: some View {
        let provider = SyncProvider(rawValue: store.lastSyncProvider) ?? .git
        let synced = provider.actionable && store.lastSyncAt != nil
        return HStack(spacing: 6) {
            Circle().fill(synced ? Color.popStatusOK : Color.popLinkOff).frame(width: 6, height: 6)
            Text(localization.string(synced ? "titlebar.synced" : "titlebar.notSynced"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(synced ? Color(hex: 0x5A7A5F) : Color.popTertiaryLabel)
        }
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .padding(.vertical, 2)
        .background(synced ? Color(hex: 0xF3F8F4) : Color.popMainBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(synced ? Color(hex: 0xCFE0D2) : Color.popControlStroke, lineWidth: 1))
    }
}
