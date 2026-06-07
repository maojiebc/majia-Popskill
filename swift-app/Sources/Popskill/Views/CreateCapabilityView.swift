import SwiftUI

/// 新建能力 — author a single capability. Left: metadata + a Markdown editor;
/// right rail: a live matrix-row preview, install-target toggles, and the exact
/// files / symlinks that would be written. Mirrors the prototype's local-state
/// behavior (no sidecar write yet — the primary action returns to the matrix).
@MainActor
struct CreateCapabilityView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var kind: CreateKind = .skill
    @State private var source: CreateSource = .blank
    @State private var name = "my-translator"
    @State private var desc = "中英对照翻译，保留术语表"
    @State private var author = "me"
    @State private var version = "0.1.0"
    @State private var claudeOn = true
    @State private var codexOn = true
    @State private var code = CreateCapabilityView.starterCode

    private var linkCount: Int { (claudeOn ? 1 : 0) + (codexOn ? 1 : 0) }

    var body: some View {
        VStack(spacing: 0) {
            hero
            toolbar
            HStack(spacing: 0) {
                editor
                rail
            }
            .frame(maxHeight: .infinity)
        }
        .popPageBackground()
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                LocalizedText("sidebar.create")
                    .font(.system(size: 25, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.popLabel)
                LocalizedText("create.subtitle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0x6F6B5E))
                    .frame(maxWidth: 540, alignment: .leading)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                LedgerGhostButton(titleKey: "create.saveDraft") {}
                LedgerPrimaryButton(
                    title: linkCount > 0
                        ? localization.string("create.createAndLink", linkCount)
                        : localization.string("create.saveOnly")
                ) { store.currentSelection = .matrix }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { hairline }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 9) {
                tbLabel("create.field.type")
                LedgerSegmented(
                    options: CreateKind.allCases.map { LedgerSegmentOption(label: $0.rawValue, dot: $0.dotColor) },
                    selection: kind.rawValue
                ) { picked in
                    if let k = CreateKind(rawValue: picked) { kind = k }
                }
            }
            HStack(spacing: 9) {
                tbLabel("create.field.source")
                LedgerSegmented(
                    options: CreateSource.allCases.map { LedgerSegmentOption(label: localization.string($0.titleKey)) },
                    selection: localization.string(source.titleKey)
                ) { picked in
                    if let s = CreateSource.allCases.first(where: { localization.string($0.titleKey) == picked }) {
                        source = s
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 11)
        .background(Color.popMainBackground)
        .overlay(alignment: .bottom) { hairline }
    }

    private func tbLabel(_ key: String) -> some View {
        LocalizedText(key)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Color.popTertiaryLabel)
    }

    // MARK: Editor (left)

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    field("create.field.name", text: $name, mono: true, trailing: localization.string("create.nameAvailable"))
                }
                field("create.field.desc", text: $desc, mono: false)
                HStack(spacing: 12) {
                    field("create.field.author", text: $author, mono: true)
                    field("create.field.version", text: $version, mono: true)
                }
                codeCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func field(_ labelKey: String, text: Binding<String>, mono: Bool, trailing: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                LocalizedText(labelKey)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.popTertiaryLabel)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1A7A3E))
                }
            }
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: mono ? .monospaced : .default))
                .foregroundStyle(Color.popLabel)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color.popControlFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.popControlStroke, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private var codeCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                codeTab(title: kind.fileName, active: true)
                codeTab(title: "popskill.toml", active: false)
                Spacer()
            }
            .background(Color.popSurface)
            .overlay(alignment: .bottom) { hairline }

            TextEditor(text: $code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.popLabel)
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .frame(minHeight: 300)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.popControlStroke, lineWidth: 1))
        .frame(minHeight: 340)
    }

    private func codeTab(title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: active ? .semibold : .medium, design: .monospaced))
            .foregroundStyle(active ? Color.popLabel : Color.popTertiaryLabel)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(active ? Color.white : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle().fill(active ? Color.popAccent : Color.clear).frame(height: 2)
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.popSeparator).frame(width: 1)
            }
    }

    // MARK: Rail (right)

    private var rail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                railSection("create.rail.preview") {
                    previewCard
                }
                railSection("create.rail.targets") {
                    targetsCard
                }
                railSection("create.rail.willWrite") {
                    writeTerminal
                }
            }
            .padding(18)
        }
        .frame(width: 360)
        .background(Color.popMainBackground)
        .overlay(alignment: .leading) { Rectangle().fill(Color.popSeparator).frame(width: 1) }
    }

    private func railSection<Content: View>(_ titleKey: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText(titleKey)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(Color.popTertiaryLabel)
            content()
        }
    }

    private var previewCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LocalizedText("matrix.col.capability").frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "Claude").frame(width: 46)
                Text(verbatim: "Codex").frame(width: 46)
            }
            .font(.system(size: 10, weight: .bold)).tracking(0.5).textCase(.uppercase)
            .foregroundStyle(Color.popTertiaryLabel)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.popRowDivider).frame(height: 1) }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(name.isEmpty ? "—" : name)
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.popLabel)
                        LedgerTypeTag(kind: kind.capabilityKind)
                    }
                    Text(desc).font(.system(size: 11)).foregroundStyle(Color.popSecondaryLabel).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LedgerStatusGlyph(state: claudeOn ? .on : .off).frame(width: 46)
                LedgerStatusGlyph(state: codexOn ? .on : .off).frame(width: 46)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.popSeparator, lineWidth: 1))
    }

    private var targetsCard: some View {
        VStack(spacing: 0) {
            targetRow(mark: "C", markColor: Color(hex: 0xC8643C), title: "Claude Code", isOn: $claudeOn, last: false)
            targetRow(mark: "Cx", markColor: Color(hex: 0x111111), title: "Codex CLI", isOn: $codexOn, last: true)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.popSeparator, lineWidth: 1))
    }

    private func targetRow(mark: String, markColor: Color, title: String, isOn: Binding<Bool>, last: Bool) -> some View {
        HStack(spacing: 11) {
            Text(mark)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(markColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.popLabel)
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden().controlSize(.mini)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Color.popRowDivider).frame(height: 1) }
        }
    }

    private var writeTerminal: some View {
        let folder = kind.folder
        var lines: [(String, Color)] = []
        lines.append(("$ popskill create \(kind.rawValue.lowercased()) \(name)", Color(hex: 0xE6E9EC)))
        lines.append(("  + store/\(folder)/\(name)-\(version)/\(kind.fileName)", Color(hex: 0x5FD29C)))
        lines.append(("  + store/\(folder)/\(name)-\(version)/popskill.toml", Color(hex: 0x5FD29C)))
        if linkCount > 0 {
            let flags = [claudeOn ? "--claude" : nil, codexOn ? "--codex" : nil].compactMap { $0 }.joined(separator: " ")
            lines.append(("$ popskill link \(flags)", Color(hex: 0xE6E9EC)))
        } else {
            lines.append((localization.string("create.term.noTarget"), Color(hex: 0x6B7280)))
        }
        if claudeOn { lines.append(("  + ~/.claude/\(folder)/\(name)", Color(hex: 0x5FD29C))) }
        if codexOn { lines.append(("  + ~/.codex/\(folder)/\(name)", Color(hex: 0x5FD29C))) }
        lines.append((localization.string("create.term.summary", linkCount), Color(hex: 0x6B7280)))

        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.0)
                    .font(.system(size: 11.5, design: .monospaced))
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

    static let starterCode = """
    ---
    name: my-translator
    description: 中英对照翻译，保留术语表
    author: me
    version: 0.1.0
    tags: [translate, zh, en]
    ---

    # 角色
    你是一名专业的中英技术翻译。

    # 步骤
    1. 读取输入文本，识别专有名词
    2. 输出术语对照表（原文 | 译法）
    3. 给出通顺、地道的译文

    # 约束
    - 代码块、变量名保持原样
    - 不臆造未出现的术语
    """
}

private enum CreateKind: String, CaseIterable, Identifiable {
    case skill = "Skill"
    case agent = "Agent"
    case mcp = "MCP"
    case cli = "CLI"

    var id: String { rawValue }

    var capabilityKind: CapabilityKind {
        switch self {
        case .skill: return .skill
        case .agent: return .agent
        case .mcp:   return .mcp
        case .cli:   return .cli
        }
    }

    var folder: String {
        switch self {
        case .skill: return "skills"
        case .agent: return "agents"
        case .mcp:   return "mcp"
        case .cli:   return "bin"
        }
    }

    var fileName: String { rawValue.uppercased() + ".md" }

    var dotColor: Color {
        switch self {
        case .skill: return Color(hex: 0xC9B478)
        case .agent: return Color(hex: 0x7FAACD)
        case .mcp:   return Color(hex: 0xA98CC9)
        case .cli:   return Color(hex: 0x74B291)
        }
    }
}

private enum CreateSource: String, CaseIterable {
    case blank, template, importFile

    var titleKey: String {
        switch self {
        case .blank:      return "create.source.blank"
        case .template:   return "create.source.template"
        case .importFile: return "create.source.import"
        }
    }
}
