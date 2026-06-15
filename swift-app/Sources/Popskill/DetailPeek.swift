import AppKit
import SwiftUI

// 详情 peek（PATCH-01）— 点击能力名称弹出，看完即走；深读走「在编辑器中打开」。
// 380 宽，锚定点击位置水平居中，下半屏向上翻转。与修复弹层互斥。

struct DetailPeekView: View {
    @Environment(AppModel.self) private var model
    let target: PeekTarget
    let winSize: CGSize

    private let width: CGFloat = 380

    private var fromBundle: Bool { target.entry.id != target.cap.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            peekBody
            foot
        }
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Ink.control, lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 18, y: 12)
        .offset(x: clampedX, y: offsetY)
    }

    private var clampedX: CGFloat {
        max(12, min(target.anchor.x - width / 2, winSize.width - width - 12))
    }

    private var offsetY: CGFloat {
        target.flip ? -(winSize.height - target.anchor.y + 28) : target.anchor.y + 6
    }

    // 1. 头部：名称 + 类型 tag + esc；副行 v · author · tokens (· ⊂ bundle)
    private var head: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(target.cap.name)
                    .font(.ui(13.5, .bold))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1).truncationMode(.tail)
                TypeTag(type: target.cap.type)
                Spacer(minLength: 8)
                Button { model.peekTarget = nil } label: {
                    Text("esc")
                        .font(.mono(10))
                        .foregroundStyle(Color(hex: 0x666666))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.control2, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                Text(subline).font(.ui(11)).monospacedDigit()
                if fromBundle {
                    Text(" · ⊂ \(target.entry.name)").font(.mono(10))
                }
            }
            .foregroundStyle(Ink.tertiary)
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 9, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.window)
        .overlay(alignment: .bottom) { Ink.hairline2.frame(height: 1) }
    }

    private var subline: String {
        var parts: [String] = []
        if let v = target.cap.version { parts.append("v\(v)") }
        if let a = target.cap.author { parts.append(a) }
        if target.cap.tokens > 0 { parts.append(formatTokens(target.cap.tokens)) }
        return parts.joined(separator: " · ")
    }

    // 2. 主体：完整描述 + 文档摘要引文块 + 两侧链接状态 + 来源 URL
    private var peekBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 真实 description 可能很长（设计假设单行）——限 6 行防溢出，全文走编辑器
            Text(target.cap.desc.isEmpty ? "—" : target.cap.desc)
                .font(.ui(12))
                .foregroundStyle(Color(hex: 0x444444))
                .lineSpacing(3)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
            if let readme = target.cap.readme {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("SKILL.MD · 文档摘要"))
                        .font(.ui(9.5, .bold)).kerning(0.7)
                        .foregroundStyle(Color(hex: 0xB3AE9E))
                    Text(readme)
                        .font(.ui(11.5))
                        .foregroundStyle(Ink.monoDim)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Ink.bundleBody))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.hairline2, lineWidth: 1))
                }
                .padding(.top, 9)
            }
            HStack(spacing: 14) {
                ForEach(model.tools) { t in statRow(t) }
            }
            .padding(.top, 10)
            if let url = target.entry.sourceUrl {
                PeekLink(text: "↗ \(url)", font: .mono(10.5), base: Ink.secondary) {
                    if let u = URL(string: url.hasPrefix("http") ? url : "https://\(url)") {
                        NSWorkspace.shared.open(u)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(_ tool: Tool) -> some View {
        let st = target.cap.status(tool.id)
        let stateText = st == .broken ? (target.cap.brokenCause[tool.id] ?? L("断链"))
            : (st == .stub ? L("占位待校验") : st.stateLabel)
        return HStack(spacing: 6) {
            Text(st.glyph).font(.mono(12))
            Text(String(tool.name.split(separator: " ").first ?? ""))
            Text(stateText).font(.ui(11.5, .medium)).opacity(0.85)
        }
        .font(.ui(11.5, .semibold))
        .foregroundStyle(st == .off ? Ink.tertiary : st.pillText)
        .lineLimit(1)
    }

    // 3. 底部：编辑器按钮 + 文档直开
    private var foot: some View {
        HStack {
            Button {
                model.openInEditor(target.cap.dirURL)
                model.peekTarget = nil
            } label: {
                Text(L("↗ 在访达中显示"))
                    .font(.ui(11.5, .semibold))
                    .foregroundStyle(Color(hex: 0x444444))
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.control2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            if let doc = docURL {
                PeekLink(text: L("↗ 打开 \(doc.lastPathComponent)"), font: .ui(10.5), base: Color(hex: 0xB3AE9E)) {
                    NSWorkspace.shared.open(doc)
                    model.peekTarget = nil
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14))
        .background(Ink.window)
        .overlay(alignment: .top) { Ink.hairline2.frame(height: 1) }
    }

    /// 完整文档文件：CLI 是 README.md，其余 SKILL.md；不存在就不给入口
    private var docURL: URL? {
        let name = target.cap.linkKind == .cli ? "README.md" : "SKILL.md"
        let u = target.cap.dirURL.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

/// peek 内的文字链接：hover 变交互蓝 + 手型光标，点击执行动作
private struct PeekLink: View {
    let text: String
    let font: Font
    let base: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(font)
                .foregroundStyle(hovered ? Ink.blue : base)
                .underline(hovered)
                .lineLimit(1).truncationMode(.tail)
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
