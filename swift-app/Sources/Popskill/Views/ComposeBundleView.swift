import SwiftUI

/// 组装套装 — pick standalone capabilities on the left; they assemble into a
/// bundle on the right with live coverage fractions and a generated
/// `popskill.toml` manifest. Candidates are the real non-bundle capabilities
/// from the store; selection is local state (publish returns to the matrix).
@MainActor
struct ComposeBundleView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var name = "my-toolkit"
    @State private var version = "0.1.0"
    @State private var upstream: ComposeUpstream = .github

    private var allCandidates: [MatrixCapability] {
        store.capabilities.filter { $0.kind != .bundle }
    }

    private var candidates: [MatrixCapability] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allCandidates }
        return allCandidates.filter {
            ($0.name + " " + ($0.summary ?? "") + " " + ($0.repoOwner ?? "")).lowercased().contains(q)
        }
    }

    private var chosen: [MatrixCapability] {
        allCandidates.filter { selected.contains($0.id) }
    }

    private var claudeOn: Int { chosen.filter { $0.apps.claude }.count }
    private var codexOn: Int { chosen.filter { $0.apps.codex }.count }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            HStack(spacing: 0) {
                leftPane
                rightPane
            }
            .frame(maxHeight: .infinity)
        }
        .popPageBackground()
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                LocalizedText("sidebar.compose")
                    .font(.system(size: 25, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.popLabel)
                LocalizedText("compose.subtitle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0x6F6B5E))
                    .frame(maxWidth: 540, alignment: .leading)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                LedgerGhostButton(titleKey: "create.saveDraft") {}
                LedgerPrimaryButton(title: localization.string("compose.publish", chosen.count)) {
                    store.currentSelection = .matrix
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { hairline }
    }

    // MARK: Left — candidates

    private var leftPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(localization.string("compose.candidates", chosen.count, allCandidates.count))
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.popTertiaryLabel)
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.popTertiaryLabel)
                    TextField(localization.string("compose.filter"), text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .frame(width: 230, height: 28)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.popControlStroke, lineWidth: 1))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.popMainBackground)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.popRowDivider).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(candidates, id: \.id) { cap in
                        candidateRow(cap)
                        Rectangle().fill(Color(hex: 0xF0EEE6)).frame(height: 1)
                    }
                    if candidates.isEmpty {
                        LocalizedText("compose.noMatch")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.popTertiaryLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.popSeparator).frame(width: 1) }
    }

    private func candidateRow(_ cap: MatrixCapability) -> some View {
        let on = selected.contains(cap.id)
        return HStack(spacing: 12) {
            checkbox(on)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(cap.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)
                    LedgerTypeTag(kind: cap.kind)
                }
                Text("\(cap.summary ?? "") · \(cap.repoOwner ?? "")")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LedgerStatusGlyph(state: cap.apps.claude ? .on : .off).frame(width: 30)
            LedgerStatusGlyph(state: cap.apps.codex ? .on : .off).frame(width: 30)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(on ? Color.popSelectedRowFill : Color.clear)
        .overlay(alignment: .leading) {
            if on { Rectangle().fill(Color.popAccent).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(cap.id) }
    }

    private func checkbox(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(on ? Color.popAccent : Color.white)
            .frame(width: 15, height: 15)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(on ? Color.popAccent : Color(hex: 0xB8B3A3), lineWidth: 1.5)
            )
            .overlay {
                if on {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
            }
    }

    // MARK: Right — assembly

    private var rightPane: some View {
        ScrollView {
            VStack(spacing: 0) {
                section("compose.section.info") {
                    HStack(alignment: .bottom, spacing: 9) {
                        field("create.field.name", text: $name).frame(maxWidth: .infinity)
                        field("create.field.version", text: $version).frame(width: 88)
                    }
                    LedgerSegmented(
                        options: ComposeUpstream.allCases.map { LedgerSegmentOption(label: localization.string($0.titleKey)) },
                        selection: localization.string(upstream.titleKey),
                        fill: true
                    ) { picked in
                        if let u = ComposeUpstream.allCases.first(where: { localization.string($0.titleKey) == picked }) {
                            upstream = u
                        }
                    }
                    .padding(.top, 9)
                }

                section("compose.section.coverage") {
                    HStack(spacing: 0) {
                        covCell(value: "\(chosen.count)", labelKey: "compose.cov.items", tint: .popLabel, last: false)
                        covCell(value: "\(claudeOn)/\(chosen.count)", labelKey: "compose.cov.claude", tint: .popLinkOn, last: false)
                        covCell(value: "\(codexOn)/\(chosen.count)", labelKey: "compose.cov.codex", tint: .popLinkOn, last: true)
                    }
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.popSeparator, lineWidth: 1))
                }

                section("compose.section.contents") {
                    if chosen.isEmpty {
                        LocalizedText("compose.empty")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.popTertiaryLabel)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(Color.popControlStroke)
                            )
                    } else {
                        VStack(spacing: 6) {
                            ForEach(chosen, id: \.id) { cap in
                                HStack(spacing: 9) {
                                    Text(verbatim: "⠿").foregroundStyle(Color(hex: 0xC4BFB0))
                                    LedgerTypeTag(kind: cap.kind)
                                    Text(cap.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.popLabel).lineLimit(1)
                                    Spacer()
                                    Button { toggle(cap.id) } label: {
                                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.popTertiaryLabel)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.popSeparator, lineWidth: 1))
                            }
                        }
                    }
                }

                section("compose.section.manifest") {
                    manifestTerminal
                }
            }
        }
        .frame(width: 420)
        .background(Color.popMainBackground)
        .overlay(alignment: .leading) { Rectangle().fill(Color.popSeparator).frame(width: 1) }
    }

    private func section<Content: View>(_ titleKey: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LocalizedText(titleKey)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(Color.popTertiaryLabel)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { hairline }
    }

    private func field(_ labelKey: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LocalizedText(labelKey)
                .font(.system(size: 10, weight: .bold)).tracking(0.4).textCase(.uppercase)
                .foregroundStyle(Color.popTertiaryLabel)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Color.popLabel)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.popControlStroke, lineWidth: 1))
        }
    }

    private func covCell(value: String, labelKey: String, tint: Color, last: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 19, weight: .bold)).monospacedDigit().foregroundStyle(tint)
            LocalizedText(labelKey)
                .font(.system(size: 10, weight: .semibold)).tracking(0.5).textCase(.uppercase)
                .foregroundStyle(Color(hex: 0x9A9180))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .overlay(alignment: .trailing) {
            if !last { Rectangle().fill(Color.popRowDivider).frame(width: 1) }
        }
    }

    private var manifestTerminal: some View {
        var lines: [(String, Color)] = []
        let section = Color(hex: 0x7FAACD)
        let dim = Color(hex: 0x6B7280)
        let body = Color(hex: 0xCBD0D6)
        lines.append(("[bundle]", section))
        lines.append(("name = \"\(name)\"", body))
        lines.append(("version = \"\(version)\"", body))
        lines.append(("upstream = \"\(localization.string(upstream.titleKey))\"", body))
        lines.append(("", dim))
        lines.append(("# \(chosen.count) 项", dim))
        for cap in chosen {
            lines.append(("[[items]]", section))
            lines.append(("id = \"\(cap.id)\"  # \(localization.string(cap.kind.titleKey))", body))
        }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.0.isEmpty ? " " : line.0)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(hex: 0x15161A), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var hairline: some View {
        Rectangle().fill(Color.popSeparator).frame(height: 1)
    }
}

enum ComposeUpstream: String, CaseIterable {
    case github, npm, local

    var titleKey: String {
        switch self {
        case .github: return "compose.upstream.github"
        case .npm:    return "compose.upstream.npm"
        case .local:  return "compose.upstream.local"
        }
    }
}
