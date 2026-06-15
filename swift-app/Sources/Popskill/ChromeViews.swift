import SwiftUI

// 窗口 chrome 与共享小件 — popskill-ui.jsx 的 SwiftUI 翻译。

// ── 品牌 mark：18×18 黑圆角方 + 两圆一线 ─────────────────

struct PsMark: View {
    var body: some View {
        Canvas { ctx, _ in
            let rect = Path(roundedRect: CGRect(x: 0, y: 0, width: 18, height: 18), cornerRadius: 5)
            ctx.fill(rect, with: .color(Ink.ink))
            var c1 = Path(); c1.addEllipse(in: CGRect(x: 4.5, y: 4.5, width: 3.8, height: 3.8))
            var c2 = Path(); c2.addEllipse(in: CGRect(x: 9.7, y: 9.7, width: 3.8, height: 3.8))
            var line = Path(); line.move(to: CGPoint(x: 7.9, y: 7.9)); line.addLine(to: CGPoint(x: 10.1, y: 10.1))
            let stroke = StrokeStyle(lineWidth: 1.3, lineCap: .round)
            ctx.stroke(c1, with: .color(.white), style: stroke)
            ctx.stroke(c2, with: .color(.white), style: stroke)
            ctx.stroke(line, with: .color(.white), style: stroke)
        }
        .frame(width: 18, height: 18)
    }
}

// ── 标题栏（38px）────────────────────────────────────────

struct Titlebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            // 原生红绿灯占位（hiddenTitleBar 下系统按钮悬浮在此区域）
            Spacer().frame(width: 58)
            HStack(spacing: 6) {
                PsMark()
                Text("Popskill").font(.ui(12.5, .semibold)).foregroundStyle(Ink.ink)
            }
            Spacer()
            syncChip
            Button { model.sheet = .sched; model.reloadSched() } label: {
                Text("◷")
                    .font(.ui(11))
                    .foregroundStyle(Color(hex: 0x666666))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.control2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(L("定时任务（launchd / crontab）"))
            Button { model.sheet = .settings } label: {
                Text("⚙")
                    .font(.ui(11))
                    .foregroundStyle(Color(hex: 0x666666))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.control2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(L("设置"))
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Ink.chrome)
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }

    @ViewBuilder
    private var syncChip: some View {
        let connected = model.syncInfo.isGitRepo && !model.isEmpty
        // 新用户的 ~/.agents 默认就不是 git 仓库——别用「未连接」吓人，
        // 跨设备同步本就是可选项，措辞改中性 + tooltip 说清
        let label = !connected ? L("同步未开启") : (model.syncInfo.clean ? L("已同步") : L("有未提交改动"))
        let dotColor: Color = !connected ? Ink.offDot : (model.syncInfo.clean ? Ink.green : Ink.amber)
        let textColor: Color = !connected ? Ink.tertiary : (model.syncInfo.clean ? Color(hex: 0x5A7A5F) : Ink.amberText)
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
            Text(label).font(.ui(11, .medium))
        }
        .foregroundStyle(textColor)
        .padding(.leading, 8).padding(.trailing, 9).padding(.vertical, 2)
        .background(Capsule().fill(connected && model.syncInfo.clean ? Ink.greenBg : Ink.window))
        .overlay(Capsule().stroke(connected && model.syncInfo.clean ? Color(hex: 0xCFE0D2) : Color(hex: 0xE2DFD3), lineWidth: 1))
        .help(connected ? "" : L("把 store（~/.agents）做成 git 仓库即可在多台 Mac 间同步——这是可选项，不影响本机使用。"))
    }
}

// ── 状态栏（26px）────────────────────────────────────────

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 9) {
            Text(abbrev(model.fs.env.storeRoot.path)).font(.mono(11)).foregroundStyle(Ink.monoDim)
            if model.isEmpty {
                dot
                Text(L("store 为空"))
            } else {
                Button { model.openStore() } label: {
                    Text(L("↗ 在访达中显示")).font(.ui(11, .medium)).foregroundStyle(Ink.blue)
                }
                .buttonStyle(.plain)
                dot
                Text(L("\(model.stats.symlinks) symlinks")).font(.mono(11)).foregroundStyle(Ink.monoDim)
                dot
                Text(L("\(model.stats.broken) 断链"))
                    .foregroundStyle(model.stats.broken > 0 ? Ink.red : Ink.secondary)
                    .fontWeight(model.stats.broken > 0 ? .semibold : .regular)
                Text("/").foregroundStyle(Ink.offDot)
                Text(L("\(model.stats.stubs) 占位"))
            }
            Spacer()
            if model.isEmpty || !model.syncInfo.isGitRepo {
                HStack(spacing: 6) {
                    Circle().fill(Ink.offDot).frame(width: 6, height: 6)
                    Text(L("同步未开启（可选）"))
                }
                .foregroundStyle(Ink.tertiary)
                .help(L("把 store（~/.agents）做成 git 仓库即可在多台 Mac 间同步——这是可选项，不影响本机使用。"))
            } else {
                HStack(spacing: 6) {
                    Circle().fill(Ink.green).frame(width: 6, height: 6)
                    Text(syncLabel)
                }
                .font(.ui(11, .medium))
                .foregroundStyle(Color(hex: 0x5A7A5F))
            }
            dot
            Text("popskill v\(popskillVersion)").font(.mono(11)).foregroundStyle(Ink.monoDim)
        }
        .font(.ui(11))
        .foregroundStyle(Ink.secondary)
        .padding(.horizontal, 16)
        .frame(height: 26)
        .background(Ink.chrome)
        .overlay(alignment: .top) { Ink.hairline.frame(height: 1) }
    }

    private var dot: some View {
        Text("·").foregroundStyle(Ink.offDot)
    }

    private var syncLabel: String {
        guard let d = model.syncInfo.lastSync else { return L("已同步") }
        let f = RelativeDateTimeFormatter()
        f.locale = l10nLocale
        f.unitsStyle = .short
        return L("同步于\(f.localizedString(for: d, relativeTo: Date()))")
    }
}

// ── 类型 tag ─────────────────────────────────────────────

struct TypeTag: View {
    let type: CapType

    var body: some View {
        let style = TypeTagStyle.of(type)
        Text(type.rawValue.uppercased())
            .font(.ui(9.5, .bold))
            .kerning(0.6)
            .foregroundStyle(style.text)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .frame(minWidth: 50)
            .background(RoundedRectangle(cornerRadius: 3).fill(style.bg))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(style.border, lineWidth: 1))
            .fixedSize()
    }
}

// ── 断链徽标（v2.13）：✕ + 成因，整卡红的标识 ──────────────

struct BrokenBadge: View {
    let cause: String

    var body: some View {
        Text("✕ \(cause)")
            .font(.ui(9.5, .bold))
            .kerning(0.5)
            .foregroundStyle(Ink.red)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Ink.brokenBadgeBg))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Ink.brokenBadgeBorder, lineWidth: 1))
            .fixedSize()
            .accessibilityLabel(L("断链") + "：" + cause)
    }
}

// ── 状态单元格（28×24 命中区，子项清单用）────────────────

struct StatusCell: View {
    let status: LinkStatus
    var a11y: String?         // "<能力> · <工具>"，VoiceOver 念语义而不是 "black circle"
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(status.glyph)
                .font(.mono(14, status == .off ? .regular : .bold))
                .foregroundStyle(status.color)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(hovered ? Color.black.opacity(0.05) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(L("点击切换 / 处理"))
        .accessibilityLabel(a11y.map { L("\($0)：\(status.stateLabel)") } ?? status.stateLabel)
        .accessibilityHint(L("点击切换或处理"))
    }
}

// ── 工具 pill（独立能力卡右列）──────────────────────────

struct TogglePill: View {
    let status: LinkStatus
    let label: String
    let action: () -> Void
    @State private var hovered = false

    // v2.11 压缩：常态（on/off）圆点配色已携带完整状态语义，不再常驻状态文字，
    // pill 自适应内容宽（原先内部 Spacer 撑满 118pt 列）；
    // 警示态（stub/broken）的文字是问题可见性，保留
    private var showState: Bool { status == .stub || status == .broken }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(status.pillGlyph).font(.mono(11)).frame(width: 12)
                Text(label)
                if showState {
                    Text(status.stateLabel).font(.ui(10, .medium)).opacity(0.75)
                }
            }
            .font(.ui(11, .semibold))
            .foregroundStyle(status.pillText)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(status.pillBg))
            .overlay(Capsule().stroke(status.pillBorder, lineWidth: 1))
            .shadow(color: hovered ? .black.opacity(0.04) : .clear, radius: 0, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(L("\(label)：\(status.stateLabel)。点击切换 / 处理"))
        .accessibilityLabel(L("\(label)：\(status.stateLabel)"))
        .accessibilityHint(L("点击切换或处理"))
    }
}

// ── 套装聚合：分数 + 36×3 迷你覆盖条 ─────────────────────

struct FractionCell: View {
    let agg: ToolAgg

    var body: some View {
        let color: Color = agg.on == agg.total ? Ink.green : (agg.on == 0 && agg.stub == 0 ? Color(hex: 0x888888) : Ink.amber)
        VStack(spacing: 3) {
            Text("\(agg.on)/\(agg.total)")
                .font(.mono(11, .bold))
                .foregroundStyle(color)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    seg(Ink.green, agg.on, width: geo.size.width)
                    seg(Color(hex: 0xE1A51A), agg.stub, width: geo.size.width)
                    seg(Ink.red, agg.broken, width: geo.size.width)
                    seg(Color(hex: 0xE6E2D4), agg.off, width: geo.size.width)
                }
            }
            .frame(width: 36, height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L("\(agg.total) 项中 \(agg.on) 项已激活")
                + (agg.broken > 0 ? L("，\(agg.broken) 项断链") : "")
                + (agg.stub > 0 ? L("，\(agg.stub) 项占位") : "")
        )
    }

    @ViewBuilder
    private func seg(_ color: Color, _ n: Int, width: CGFloat) -> some View {
        if n > 0, agg.total > 0 {
            color.frame(width: width * CGFloat(n) / CGFloat(agg.total))
        }
    }
}

// ── 更新徽标 ↑ x.y.z ─────────────────────────────────────

struct UpdateBadge: View {
    let latest: String
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("↑ \(latest)")
                .font(.mono(10, .bold))
                .foregroundStyle(Ink.amberText)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Ink.amberBadgeBg))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Ink.amberBadgeBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help ?? L("更新到 \(latest)"))
        .accessibilityLabel(help ?? L("更新到 \(latest)"))
    }
}

/// 套装子项行的「有新版」迷你角标（v2.5：提醒到具体成员）
struct MemberUpdateDot: View {
    var body: some View {
        Text("↑")
            .font(.mono(10, .bold))
            .foregroundStyle(Ink.amberText)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(Ink.amberBadgeBg))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Ink.amberBadgeBorder, lineWidth: 1))
            .help(L("上游有新版——点套装头部 ↑ 徽标更新"))
    }
}

// ── 悬停操作钮 ↗ / ✕ ────────────────────────────────────

struct HoverAction: View {
    let symbol: String        // "↗" / "✕"
    let danger: Bool
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.ui(12))
                .foregroundStyle(hovered ? (danger ? Ink.red : Ink.blue) : Ink.tertiary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// ── toast：底部居中黑底白字 ──────────────────────────────

struct ToastView: View {
    let msg: String
    var isError = false

    var body: some View {
        Text(msg)
            .font(.ui(12, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(isError ? Ink.red : Ink.ink))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
            .accessibilityLabel(isError ? L("错误：\(msg)") : msg)
    }
}

// ── 搜索命中高亮 ─────────────────────────────────────────

func highlight(_ text: String, _ query: String) -> AttributedString {
    var attr = AttributedString(text)
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty, let range = attr.range(of: q, options: .caseInsensitive) else { return attr }
    attr[range].backgroundColor = Ink.highlight
    attr[range].foregroundColor = Ink.ink
    return attr
}

func treeGlyph(isLast: Bool) -> String { isLast ? "└─" : "├─" }
