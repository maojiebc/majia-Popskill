import SwiftUI

// 行内修复弹层 — 锚定被点单元格，320 宽，下半屏向上翻。

struct FixPopoverView: View {
    @Environment(AppModel.self) private var model
    let target: FixTarget
    let winSize: CGSize

    private let width: CGFloat = 320

    var body: some View {
        let headColor = target.issueKind == .stub ? Ink.amber : Ink.red
        let headSym = target.issueKind == .stub ? "◐" : "✕"
        let headLabel = target.issueKind == .stub
            ? (target.cap.brokenCause[target.tool.id] ?? L("占位 (stub)"))
            : (target.cap.brokenCause[target.tool.id] ?? L("断链"))

        VStack(alignment: .leading, spacing: 0) {
            // 头部：成因标题 + 来源行
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(headSym).font(.mono(12.5))
                    Text(headLabel)
                    Text("— \(target.cap.name)").foregroundStyle(Ink.ink)
                    Text("· \(target.tool.name)").font(.ui(12.5, .medium)).foregroundStyle(Ink.tertiary)
                }
                .font(.ui(12.5, .bold))
                .foregroundStyle(headColor)
                if let url = target.entry.sourceUrl {
                    HStack(spacing: 0) {
                        Text("↗ \(url)")
                        if let latest = target.entry.hasUpdate ? target.entry.latest : nil {
                            Text("  ↑ \(latest)").fontWeight(.bold).foregroundStyle(Ink.amberText)
                        }
                    }
                    .font(.mono(10.5))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 9, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.window)
            .overlay(alignment: .bottom) { Ink.hairline2.frame(height: 1) }

            // 方案列表（v2.16：↑↓/回车/数字可选——kbFocused 画键盘焦点）
            VStack(spacing: 2) {
                ForEach(Array(model.fixOptions(for: target).enumerated()), id: \.element.id) { i, opt in
                    FixOptionRow(option: opt, kbFocused: model.fixKbIdx == i) { model.applyFix(opt, target: target) }
                }
            }
            .padding(6)
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

    /// 非翻转：单元格底边 +6；翻转：弹层底边在单元格上方 30
    private var offsetY: CGFloat {
        target.flip ? -(winSize.height - target.anchor.y + 30) : target.anchor.y + 6
    }
}

struct FixOptionRow: View {
    let option: FixOption
    var kbFocused = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(option.label)
                        .font(.ui(12, .semibold))
                        .foregroundStyle(option.rec ? Ink.greenText : Ink.ink)
                    if option.rec {
                        Text(L("推荐"))
                            .font(.ui(9.5, .bold)).kerning(0.5)
                            .foregroundStyle(Ink.greenText)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Ink.greenBorder, lineWidth: 1))
                    }
                }
                Text(option.desc)
                    .font(.ui(11))
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            .background(RoundedRectangle(cornerRadius: 6).fill(option.rec ? Ink.greenBg : (hovered || kbFocused ? Ink.chrome : .clear)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                kbFocused ? Ink.blue.opacity(0.45) : (option.rec ? Ink.greenBorder : .clear),
                lineWidth: kbFocused ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
