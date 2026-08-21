import AppKit
import SwiftUI

// 详情 peek（PATCH-01）— 点击能力名称弹出，看完即走；深读走「在编辑器中打开」。
// v2.21：不再只丢一段原文，而是本地提炼「是什么 / 何时用 / 能做什么」。
// 420 宽，锚定点击位置水平居中，下半屏向上翻转。与修复弹层互斥。

struct DetailPeekView: View {
    @Environment(AppModel.self) private var model
    let target: PeekTarget
    let winSize: CGSize

    private let width: CGFloat = 420

    private var fromBundle: Bool { target.entry.id != target.cap.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            ScrollView {
                peekBody
            }
            .frame(maxHeight: max(260, min(500, winSize.height - 180)))
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

    // 2. 主体：人话说明 + 场景/能力 + 链接状态 + 更新与来源
    private var peekBody: some View {
        let detail = SkillInsight.load(for: target.cap)
        return VStack(alignment: .leading, spacing: 0) {
            PeekSectionTitle(maintenanceText("一句话说明", "IN PLAIN LANGUAGE"))
            Text(detail.summary)
                .font(.ui(12))
                .foregroundStyle(Color(hex: 0x444444))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !detail.useCases.isEmpty {
                InsightList(
                    title: maintenanceText("适合什么时候用", "WHEN TO USE"),
                    items: detail.useCases
                )
                .padding(.top, 12)
            }
            if !detail.capabilities.isEmpty {
                InsightList(
                    title: maintenanceText("它能做什么", "WHAT IT DOES"),
                    items: detail.capabilities
                )
                .padding(.top, 12)
            }
            if !detail.keywords.isEmpty {
                Text(detail.keywords.joined(separator: " · "))
                    .font(.mono(9.5))
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(2)
                    .padding(.top, 9)
            }

            if let readme = target.cap.readme {
                VStack(alignment: .leading, spacing: 4) {
                    PeekSectionTitle(L("SKILL.MD · 文档摘要"))
                    Text(readme)
                        .font(.ui(11.5))
                        .foregroundStyle(Ink.monoDim)
                        .lineSpacing(4)
                        .lineLimit(7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Ink.bundleBody))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.hairline2, lineWidth: 1))
                }
                .padding(.top, 12)
            }

            PeekSectionTitle(maintenanceText("挂载状态", "MOUNT STATUS"))
                .padding(.top, 12)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 7) {
                ForEach(model.tools) { t in statRow(t) }
            }

            // v2.16：peek 补更新态——「看完即走」的卡此前回答不了「有没有新版 / 是不是被我跳过了」
            if model.updatingIds.contains(target.entry.id) {
                UpdatingDot().padding(.top, 10)
            } else if target.entry.hasUpdate, let latest = target.entry.latest {
                UpdateBadge(latest: latest, help: target.entry.updateHelp) { model.runUpdate(target.entry.id) }
                    .padding(.top, 10)
            } else if target.entry.skippedUpdate {
                SkippedTag { model.unskipUpdate(target.entry) }.padding(.top, 10)
            }
            if target.entry.hasUpstreamNew {
                VStack(alignment: .leading, spacing: 6) {
                    UpstreamNewBadge(count: target.entry.upstreamNewCount, help: target.entry.upstreamNewHelp) {
                        model.installUpstreamNew(target.entry)
                        model.peekTarget = nil
                    }
                    if let names = target.entry.upstreamNew, !names.isEmpty {
                        Text(names.sorted().joined(separator: L("、")))
                            .font(.mono(10))
                            .foregroundStyle(Ink.tertiary)
                            .lineLimit(3)
                    }
                }
                .padding(.top, 8)
            }
            if let url = target.entry.sourceUrl {
                PeekLink(text: "↗ \(url)", font: .mono(10.5), base: Ink.secondary) {
                    model.openSourceLink(url)
                }
                .padding(.top, 10)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(_ tool: Tool) -> some View {
        let st = target.cap.status(tool.id)
        let stateText = st == .broken ? (target.cap.brokenCause[tool.id] ?? L("断链"))
            : (st == .stub ? L("占位待校验") : st.stateLabel)
        return HStack(spacing: 6) {
            Text(st.glyph).font(.mono(12))
            Text(String(tool.name.split(separator: " ").first ?? ""))
            Text(stateText).font(.ui(10.5, .medium)).opacity(0.85)
        }
        .font(.ui(11, .semibold))
        .foregroundStyle(st == .off ? Ink.tertiary : st.pillText)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// 完整文档文件：CLI 优先 README.md，其余优先 SKILL.md；不存在就不给入口
    private var docURL: URL? {
        let names = target.cap.linkKind == .cli
            ? ["README.md", "SKILL.md"]
            : ["SKILL.md", "README.md"]
        return names
            .map { target.cap.dirURL.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private struct PeekSectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.ui(9.5, .bold)).kerning(0.7)
            .foregroundStyle(Color(hex: 0xB3AE9E))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }
}

private struct InsightList: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PeekSectionTitle(title)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("·")
                        .font(.ui(12, .bold))
                        .foregroundStyle(Ink.blue)
                    Text(item)
                        .font(.ui(11.5))
                        .foregroundStyle(Ink.secondary2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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
