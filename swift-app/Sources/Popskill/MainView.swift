import SwiftUI

// 主屏：能力矩阵（popskill-main.jsx 的 SwiftUI 翻译）
// 自上而下：hero → 健康横幅（条件）→ 类型 chip 行 → 卡片网格（滚动）

enum DisplayItem: Identifiable {
    case bundle(Entry, kids: [Capability]?)               // kids=nil 表示折叠
    case cap(Capability, entry: Entry, fromBundle: String?)

    var id: String {
        switch self {
        case .bundle(let e, _): "b-\(e.id)"
        case .cap(let c, _, _): "c-\(c.id)"
        }
    }
}

/// 主区视图形态（v2.13）：卡片矩阵 / 账本表格——同一份数据、共享键盘导航
enum ViewMode: String { case grid, list }

struct MainView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            hero
            statStrip
            if !model.issues.isEmpty || !model.updates.isEmpty { banner }
            chipRow
            content
        }
        .background(Ink.window)
        .onChange(of: model.searchFocused) { _, want in
            if want { searchFocus = true; model.searchFocused = false }
        }
    }

    // ── hero ─────────────────────────────────────────────

    private var hero: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("能力矩阵"))
                    .font(.ui(25, .bold))
                    .foregroundStyle(Ink.ink)
                Text(heroSub)
                    .font(.ui(12.5))
                    .foregroundStyle(Ink.secondary2)
            }
            Spacer()
            HStack(spacing: 8) {
                searchPill
                Button { model.sheet = .add } label: {
                    Text(L("+ 添加"))
                        .font(.ui(12.5, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Ink.ink))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(EdgeInsets(top: 18, leading: 28, bottom: 14, trailing: 28))
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }

    private var heroSub: String {
        let s = model.stats
        let active = model.tools
            .map { "\($0.name.split(separator: " ").first ?? "") \(s.activeByTool[$0.id] ?? 0)" }
            .joined(separator: " / ")
        return L("\(s.bundles) 套装 · \(s.standalone) 独立能力 · \(active) 已激活")
    }

    // ── 顶部统计条（v2.13）：5 类型计数 + 各工具 已激活/未挂载 拆分 ──

    private static let typeGlyph: [CapType: String] = [
        .skill: "◈", .agent: "◉", .mcp: "▣", .cli: "⌨", .bundle: "▦",
    ]

    private var statStrip: some View {
        let s = model.stats
        return HStack(spacing: 0) {
            ForEach(CapType.allCases) { t in
                typeCell(t, s.byType[t] ?? 0)
            }
            ForEach(Array(model.tools.enumerated()), id: \.element.id) { i, t in
                toolCell(t, on: s.activeByTool[t.id] ?? 0, off: s.inactiveByTool[t.id] ?? 0,
                         last: i == model.tools.count - 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // 只取内容高度，别让内部边框把条撑高
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 9).fill(Ink.card))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Ink.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .padding(EdgeInsets(top: 12, leading: 28, bottom: 2, trailing: 28))
        .accessibilityElement(children: .combine)
    }

    /// cell 右侧 1px 分隔（border-right，overlay 不占布局、不撑高）
    private func cellDivider(_ show: Bool) -> some View {
        Rectangle().fill(Ink.hairline2).frame(width: 1).opacity(show ? 1 : 0)
    }

    private func statKey(_ glyph: String?, _ label: String) -> some View {
        HStack(spacing: 4) {
            if let glyph { Text(glyph).font(.ui(11)).foregroundStyle(Ink.statGlyph) }
            Text(label.uppercased())
                .font(.ui(9, .bold)).tracking(0.6)
                .foregroundStyle(Ink.tertiary).lineLimit(1)
        }
    }

    private func typeCell(_ t: CapType, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            statKey(Self.typeGlyph[t], t.rawValue)
            Text("\(n)").font(.ui(20, .bold)).foregroundStyle(Ink.ink).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(alignment: .trailing) { cellDivider(true) }
    }

    private func toolCell(_ t: Tool, on: Int, off: Int, last: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            statKey(nil, t.name)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(on)").font(.ui(20, .bold)).foregroundStyle(Ink.green).monospacedDigit()
                    Text(L("已激活")).font(.ui(10, .semibold)).foregroundStyle(Ink.statOnLabel)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(off)").font(.ui(13, .semibold)).foregroundStyle(Ink.offGlyph).monospacedDigit()
                    Text(L("未挂载")).font(.ui(10)).foregroundStyle(Ink.offGlyph)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(alignment: .trailing) { cellDivider(!last) }
    }

    // ── 主区：卡片矩阵 / 账本表格 ──

    @ViewBuilder
    private var content: some View {
        switch model.viewMode {
        case .grid: grid
        case .list: grid   // TODO(UI-3): listView
        }
    }

    private var searchPill: some View {
        @Bindable var model = model
        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(searchFocus ? Ink.blue : Ink.tertiary)
            TextField(L("搜索名称 / 描述 / 作者…"), text: $model.query)
                .textFieldStyle(.plain)
                .font(.ui(12))
                .foregroundStyle(Ink.ink)
                .focused($searchFocus)
            if model.query.isEmpty {
                Text("/")
                    .font(.mono(10))
                    .foregroundStyle(Color(hex: 0x666666))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.control2, lineWidth: 1))
            } else {
                Button { model.query = "" } label: {
                    Text("×").font(.ui(15)).foregroundStyle(Ink.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(width: 220, height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(searchFocus ? Ink.blue : Ink.control, lineWidth: 1))
        .shadow(color: searchFocus ? Ink.blue.opacity(0.12) : .clear, radius: 0, x: 0, y: 0)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Ink.blue.opacity(searchFocus ? 0.12 : 0), lineWidth: 3)
                .padding(-2)
        )
    }

    // ── 健康横幅 ──────────────────────────────────────────

    private var banner: some View {
        HStack(spacing: 14) {
            if !model.issues.isEmpty {
                HStack(spacing: 6) {
                    Text("✕").font(.mono(12))
                    Text(L("\(model.issues.count) 个链接问题"))
                }
                .font(.ui(12, .semibold))
                .foregroundStyle(Ink.red)
            }
            if !model.issues.isEmpty && !model.updates.isEmpty {
                Text("·").foregroundStyle(Color(hex: 0xD8CFAE))
            }
            if !model.updates.isEmpty {
                HStack(spacing: 6) {
                    Text("↑").font(.mono(12))
                    Text(L("\(model.updates.count) 个源可更新"))
                }
                .font(.ui(12, .semibold))
                .foregroundStyle(Ink.amberText)
            }
            Text(L("点击 ✕ / ◐ / ↑ 可逐项处理"))
                .font(.ui(11.5))
                .foregroundStyle(Color(hex: 0x8A8268))
            Spacer()
            if !model.issues.isEmpty {
                Button { model.fixAll() } label: {
                    Text(L("全部修复 (\(model.issues.count))"))
                        .font(.ui(11.5, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Ink.ink))
                }
                .buttonStyle(.plain)
            }
            if !model.updates.isEmpty {
                Button { model.updateAll() } label: {
                    Text(L("全部更新 (\(model.updates.count))"))
                        .font(.ui(11.5, .semibold)).foregroundStyle(Color(hex: 0x5A4A14))
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: 0xCDB878), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 9)
        .background(Ink.bannerBg)
        .overlay(alignment: .bottom) { Ink.bannerBorder.frame(height: 1) }
    }

    // ── 类型 chip 行 ──────────────────────────────────────

    private var chipRow: some View {
        HStack(spacing: 6) {
            chip(nil, L("全部"))
            ForEach(CapType.allCases) { t in chip(t, t.rawValue) }
            Spacer()
            let filtering = !model.query.trimmingCharacters(in: .whitespaces).isEmpty || model.typeFilter != nil
            Text(filtering ? L("\(capCount) 项匹配") : L("↑↓ 行 · ←→ 列 · 空格 切换"))
                .font(.ui(11.5, filtering ? .semibold : .regular))
                .foregroundStyle(filtering ? Ink.blue : Color(hex: 0x888888))
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }

    private func chip(_ t: CapType?, _ label: String) -> some View {
        let active = model.typeFilter == t
        return Button { model.typeFilter = t } label: {
            Text(label)
                .font(.ui(11.5, .medium))
                .foregroundStyle(active ? .white : Color(hex: 0x444444))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(active ? Ink.ink : .clear))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(active ? Ink.ink : Ink.control2, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // ── 过滤（JSX 逻辑直译）───────────────────────────────

    private var q: String { model.query.trimmingCharacters(in: .whitespaces).lowercased() }

    private func hit(_ c: Capability) -> Bool {
        q.isEmpty || "\(c.name) \(c.desc) \(c.author ?? "")".lowercased().contains(q)
    }

    private var items: [DisplayItem] {
        var out: [DisplayItem] = []
        if model.typeFilter == .bundle {
            for e in model.entries where e.isBundle && hit(e.cap) {
                out.append(.bundle(e, kids: e.children))
            }
        } else if let tf = model.typeFilter {
            for e in model.entries {
                if e.isBundle {
                    for c in (e.children ?? []) where c.type == tf && hit(c) {
                        out.append(.cap(c, entry: e, fromBundle: e.name))
                    }
                } else if e.cap.type == tf && hit(e.cap) {
                    out.append(.cap(e.cap, entry: e, fromBundle: nil))
                }
            }
        } else {
            for e in model.entries {
                if e.isBundle {
                    if q.isEmpty {
                        out.append(.bundle(e, kids: model.expanded.contains(e.id) ? e.children : nil))
                    } else if hit(e.cap) {
                        out.append(.bundle(e, kids: e.children))
                    } else {
                        let mk = (e.children ?? []).filter(hit)
                        if !mk.isEmpty { out.append(.bundle(e, kids: mk)) }
                    }
                } else if hit(e.cap) {
                    out.append(.cap(e.cap, entry: e, fromBundle: nil))
                }
            }
        }
        return out
    }

    private var capCount: Int {
        items.reduce(0) {
            switch $1 {
            case .cap: $0 + 1
            case .bundle(let e, _): $0 + (e.children?.count ?? 0)
            }
        }
    }

    // ── 卡片网格 ──────────────────────────────────────────

    /// v2.7.1：展开的套装提升到最前（通栏块连续，折叠卡打包不被打断、不再留孤行）
    private func promoteExpanded(_ list: [DisplayItem]) -> [DisplayItem] {
        var expanded: [DisplayItem] = [], rest: [DisplayItem] = []
        for it in list {
            if case .bundle(_, let kids) = it, kids != nil { expanded.append(it) } else { rest.append(it) }
        }
        return expanded + rest
    }

    private var grid: some View {
        let list = promoteExpanded(items)
        return GeometryReader { geo in
            // 自适应列数（v2.7）：~440pt/卡，1280→2 列、1700→3 列、2100+→4 列
            let cols = max(2, min(4, Int((geo.size.width - 56 + 10) / 450)))
            ScrollViewReader { proxy in
                ScrollView {
                    if list.isEmpty {
                        VStack(spacing: 4) {
                            Text(L("无匹配结果")).font(.ui(13, .semibold)).foregroundStyle(Ink.secondary2)
                            noMatchHint
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 64)
                    } else {
                        // 不用 LazyVStack：Lazy 下屏外行不实体化，scrollTo 对未实体化目标
                        // 不滚动，键盘导航焦点移出首屏即失踪（审查实证）。
                        // 这个量级（几十张卡）全量构建成本可接受。
                        VStack(spacing: 10) {
                            ForEach(rows(list, columns: cols), id: \.first!.id) { row in
                                if row.count == 1, case .bundle(_, let kids) = row[0], kids != nil {
                                    itemView(row[0])   // 展开的套装才通栏
                                } else {
                                    HStack(alignment: .top, spacing: 10) {
                                        ForEach(row) { itemView($0).frame(maxWidth: .infinity, alignment: .top) }
                                        ForEach(0..<(cols - row.count), id: \.self) { _ in
                                            Color.clear.frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(EdgeInsets(top: 16, leading: 28, bottom: 28, trailing: 28))
                    }
                }
                .onChange(of: model.kbFocusId) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) } }
                }
            }
        }
        .background(Ink.window)
        .onAppear { syncKbList(list) }
        .onChange(of: kbIds(list)) { _, _ in syncKbList(items) }
    }

    /// 空结果提示按原因分支——类型过滤、空搜索时曾显示病句『没有能力匹配 ""』
    @ViewBuilder
    private var noMatchHint: some View {
        if q.isEmpty, let tf = model.typeFilter {
            Text(L("没有 \(tf.rawValue.uppercased()) 类型的能力。点 + 添加，或切回「全部」。"))
                .font(.ui(12)).foregroundStyle(Ink.tertiary)
        } else {
            (Text(L("没有能力匹配 “")) + Text(model.query).font(.mono(12)).foregroundStyle(Ink.ink) + Text(L("”。试试别的关键词，或 + 添加。")))
                .font(.ui(12)).foregroundStyle(Ink.tertiary)
        }
    }

    /// 键盘焦点序列 = 可见顺序（套装行 + 展开的子项 + 独立卡）
    private func kbIds(_ list: [DisplayItem]) -> [String] {
        list.flatMap { item -> [String] in
            switch item {
            case .bundle(let e, let kids): [e.id] + (kids ?? []).map(\.id)
            case .cap(let c, _, _): [c.id]
            }
        }
    }

    private func syncKbList(_ list: [DisplayItem]) {
        model.kbFocusList = list.flatMap { item -> [KbItem] in
            switch item {
            case .bundle(let e, let kids):
                [KbItem(id: e.id, isBundle: true, entryId: e.id, capId: nil)]
                    + (kids ?? []).map { KbItem(id: $0.id, isBundle: false, entryId: e.id, capId: $0.id) }
            case .cap(let c, let e, _):
                [KbItem(id: c.id, isBundle: false, entryId: e.id, capId: c.id)]
            }
        }
        model.kbValidate()
    }

    /// v2.7 布局：只有「展开的」套装通栏；折叠套装与独立卡一起按列数打包进网格
    private func rows(_ list: [DisplayItem], columns: Int) -> [[DisplayItem]] {
        var rows: [[DisplayItem]] = []
        var pending: [DisplayItem] = []
        for it in list {
            if case .bundle(_, let kids) = it, kids != nil {
                if !pending.isEmpty { rows.append(pending); pending = [] }
                rows.append([it])
            } else {
                pending.append(it)
                if pending.count == columns { rows.append(pending); pending = [] }
            }
        }
        if !pending.isEmpty { rows.append(pending) }
        return rows
    }

    @ViewBuilder
    private func itemView(_ item: DisplayItem) -> some View {
        switch item {
        case .bundle(let e, let kids):
            if kids == nil {
                BundleCompactCard(entry: e, query: q)
            } else {
                BundleCard(entry: e, kids: kids, query: q)
            }
        case .cap(let c, let e, let from):
            CapCard(cap: c, entry: e, fromBundle: from, query: q)
        }
    }
}

// ── 折叠套装紧凑卡（v2.7）：与独立卡同宽混排，展开才通栏 ──

struct BundleCompactCard: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    let query: String
    @State private var hovered = false

    var body: some View {
        let focused = model.kbFocusId == entry.id
        HStack(alignment: .top, spacing: 12) {
            Text("▶")
                .font(.mono(11))
                .foregroundStyle(Color(hex: 0x444444))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9).fill(Ink.bundleHead))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Ink.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(highlight(entry.name, query))
                        .font(.ui(13.5, .bold))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                    TypeTag(type: .bundle)
                    Text(L("\(entry.children?.count ?? 0) 项"))
                        .font(.ui(11))
                        .foregroundStyle(Ink.secondary)
                        .fixedSize()
                    Spacer(minLength: 0)
                    if hovered {
                        HoverAction(symbol: "↗", danger: false, help: L("在编辑器中打开")) { model.openInEditor(entry.cap.dirURL) }
                        if !entry.isManagedExternally {
                            HoverAction(symbol: "✕", danger: true, help: L("移除套装（含全部子项）")) { model.removeEntry(entry) }
                        }
                    }
                }
                .frame(height: 22)
                Text(highlight(entry.cap.desc, query))
                    .font(.ui(11.5))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if entry.isManagedExternally {
                        Text("MARKETPLACE").font(.ui(8.5, .bold)).kerning(0.5).foregroundStyle(Ink.monoDim)
                    }
                    if let v = entry.cap.version { Text("v\(v)") }
                    if model.updatingIds.contains(entry.id) {
                        UpdatingDot()
                    } else if entry.hasUpdate, let latest = entry.latest {
                        UpdateBadge(latest: latest) { model.runUpdate(entry.id) }
                    }
                    if entry.cap.tokens >= 100 { Text(formatTokens(entry.cap.tokens)) }
                    if let url = entry.sourceUrl {
                        Text("↗ \(url)").font(.mono(10)).lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(.ui(11))
                .foregroundStyle(Ink.tertiary)
                .monospacedDigit()
            }
            HStack(spacing: 10) {
                ForEach(model.tools) { t in
                    VStack(spacing: 3) {
                        Text(String(t.name.split(separator: " ").first ?? "").uppercased())
                            .font(.ui(8.5, .bold)).kerning(0.6)
                            .foregroundStyle(Ink.tertiary)
                        FractionCell(agg: aggregate(entry.children ?? [], toolId: t.id))
                    }
                }
            }
            .frame(minWidth: 100)
            .padding(.top, 2)
        }
        .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.bundleBody))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Ink.blue : Ink.hairline, lineWidth: 1))
        .kbRowFocus(focused, radius: 10, model: model)
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { model.expanded.insert(entry.id) }
        .onHover { hovered = $0 }
        .help(L("点击展开套装"))
        // hover 才入树的 ↗/✕ 对 VoiceOver 不存在——动作挂在卡片上兜底
        .accessibilityAction(named: L("在编辑器中打开")) { model.openInEditor(entry.cap.dirURL) }
        .accessibilityAction(named: L("移除套装")) { if !entry.isManagedExternally { model.removeEntry(entry) } }
        .id(entry.id)
    }
}

/// 后台换版进行中的指示（v2.8：曾经更新期间界面毫无表示）
struct UpdatingDot: View {
    var body: some View {
        HStack(spacing: 4) {
            ProgressView().controlSize(.mini)
            Text(L("更新中…")).font(.ui(10, .medium)).foregroundStyle(Ink.amberText)
        }
        .accessibilityLabel(L("更新中"))
    }
}

// ── 独立能力卡（双列）────────────────────────────────────

struct CapCard: View {
    @Environment(AppModel.self) private var model
    let cap: Capability
    let entry: Entry
    let fromBundle: String?
    let query: String
    @State private var hovered = false

    var body: some View {
        let flashing = model.flashId == entry.id
        HStack(alignment: .top, spacing: 12) {
            Text(String(cap.name.prefix(1)).uppercased())
                .font(.ui(15, .bold))
                .foregroundStyle(broken ? Ink.red : Ink.monoDim)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9).fill(broken ? Ink.brokenBadgeBg : Ink.chrome))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(broken ? Ink.brokenBadgeBorder : Ink.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    PeekableName(cap: cap, entry: entry, font: .ui(13.5, .bold), color: broken ? Ink.red : Ink.ink, query: query)
                    TypeTag(type: cap.type)
                    if broken { BrokenBadge(cause: brokenCause) }
                    Spacer(minLength: 0)
                    if hovered {
                        HoverAction(symbol: "↗", danger: false, help: L("在编辑器中打开")) { model.openInEditor(cap.dirURL) }
                        if fromBundle == nil {
                            HoverAction(symbol: "✕", danger: true, help: L("移除")) { model.removeEntry(entry) }
                        }
                    }
                }
                .frame(height: 22)
                Text(highlight(cap.desc.isEmpty ? "—" : cap.desc, query))
                    .font(.ui(11.5))
                    .foregroundStyle(broken ? Ink.brokenDesc : Ink.secondary)
                    .lineLimit(2)
                metaRow
            }
            // v2.11：pill 自适应内容宽、整列右对齐——省出的宽度还给左侧信息区
            VStack(alignment: .trailing, spacing: 5) {
                ForEach(Array(model.tools.enumerated()), id: \.element.id) { i, t in
                    TogglePill(status: cap.status(t.id), label: pillLabel(t)) {
                        cellTap(tool: t)
                    }
                    .kbCellRing(focused && model.kbToolIdx == i)
                }
            }
            .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
        .background(RoundedRectangle(cornerRadius: 10).fill(flashing ? Ink.flashBg : (broken ? Ink.brokenCardBg : Ink.card)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused || flashing ? Ink.blue : (broken ? Ink.brokenCardBorder : Ink.hairline), lineWidth: 1))
        .kbRowFocus(focused, radius: 10, model: model)
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 1.2), value: flashing)
        .accessibilityAction(named: L("在编辑器中打开")) { model.openInEditor(cap.dirURL) }
        .accessibilityAction(named: L("移除")) { if fromBundle == nil { model.removeEntry(entry) } }
        .id(cap.id)
    }

    private var focused: Bool { model.kbFocusId == cap.id }
    /// 任一工具侧断链 ⇒ 整卡红（设计稿 cardBroken）
    private var broken: Bool { model.tools.contains { cap.status($0.id) == .broken } }
    private var brokenCause: String {
        guard let t = model.tools.first(where: { cap.status($0.id) == .broken }) else { return L("断链") }
        return cap.brokenCause[t.id] ?? L("断链")
    }

    private func pillLabel(_ t: Tool) -> String {
        String(t.name.split(separator: " ").first ?? "")
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            if let v = cap.version { Text("v\(v)") }
            if fromBundle == nil, model.updatingIds.contains(entry.id) {
                UpdatingDot()
            } else if entry.hasUpdate, fromBundle == nil, let latest = entry.latest {
                UpdateBadge(latest: latest) { model.runUpdate(entry.id) }
            }
            if let a = cap.author { Text(highlight(a, query)) }
            if cap.tokens >= 100 { Text(formatTokens(cap.tokens)) }
            if let from = fromBundle {
                Text("⊂ \(from)").font(.mono(10))
            } else if let url = entry.sourceUrl {
                Text("↗ \(url)")
                    .font(.mono(10))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .leading)
            }
        }
        .font(.ui(11))
        .foregroundStyle(Ink.tertiary)
        .monospacedDigit()
        .padding(.top, 1)
    }

    private func cellTap(tool: Tool) {
        let st = cap.status(tool.id)
        if st == .on || st == .off {
            model.toggle(cap: cap, entry: entry, tool: tool)
        } else {
            model.openFix(FixTarget(issueKind: st, cap: cap, entry: entry, tool: tool,
                                    anchor: currentClickPoint(), flip: shouldFlip()))
        }
    }
}

// ── 套装卡（通栏）────────────────────────────────────────

struct BundleCard: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    let kids: [Capability]?
    let query: String
    @State private var hovered = false
    @State private var hoverChild: String?

    var body: some View {
        let flashing = model.flashId == entry.id
        VStack(spacing: 0) {
            header
            if let kids, !kids.isEmpty { childList(kids) }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(flashing ? Ink.flashBg : Ink.bundleBody))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(headFocused || flashing ? Ink.blue : Ink.hairline, lineWidth: 1))
        .kbRowFocus(headFocused, radius: 10, model: model)
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
        .onHover { hovered = $0 }
        .id(entry.id)
    }

    private var headFocused: Bool { model.kbFocusId == entry.id }

    private var bundleUpdateHelp: String {
        guard let changed = entry.changedMembers, !changed.isEmpty else { return L("更新此套装") }
        let members = changed.sorted().joined(separator: L("、"))
        return L("有新版：\(members)——点击全部更新")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(kids != nil ? "▼" : "▶")
                .font(.mono(9))
                .foregroundStyle(Color(hex: 0x444444))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(highlight(entry.name, query))
                        .font(.ui(14, .bold))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                    TypeTag(type: .bundle)
                    if entry.isManagedExternally {
                        Text("MARKETPLACE")
                            .font(.ui(9.5, .bold)).kerning(0.6)
                            .foregroundStyle(Ink.monoDim)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Ink.control2, lineWidth: 1))
                            .help(L("Claude Code Marketplace 插件——只读展示，操作用 /plugin"))
                    }
                    Text(L("\(entry.children?.count ?? 0) 项"))
                        .font(.ui(11.5))
                        .foregroundStyle(Ink.secondary)
                }
                HStack(spacing: 4) {
                    Text(highlight(entry.cap.desc, query))
                        .font(.ui(11.5))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                    // PATCH-02：套装头部补总 tokens
                    Text("· \(formatTokens(entry.cap.tokens))\(entry.sourceUrl.map { " · ↗ \($0)" } ?? "")")
                        .font(.mono(10))
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            // PATCH-02：固定列宽，与子项清单列对齐
            ForEach(model.tools) { t in
                VStack(spacing: 3) {
                    Text(String(t.name.split(separator: " ").first ?? "").uppercased())
                        .font(.ui(9, .bold)).kerning(0.7)
                        .foregroundStyle(Ink.tertiary)
                    FractionCell(agg: aggregate(entry.children ?? [], toolId: t.id))
                }
                .frame(width: 52)
            }
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                if let v = entry.cap.version { Text("v\(v)").lineLimit(1).fixedSize() }
                if model.updatingIds.contains(entry.id) {
                    UpdatingDot()
                } else if entry.hasUpdate, let latest = entry.latest {
                    UpdateBadge(latest: latest, help: bundleUpdateHelp) { model.runUpdate(entry.id) }
                }
            }
            .font(.ui(11.5))
            .foregroundStyle(Ink.secondary)
            .monospacedDigit()
            .frame(width: 104)
            HStack(spacing: 2) {
                if hovered {
                    HoverAction(symbol: "↗", danger: false, help: L("在编辑器中打开")) { model.openInEditor(entry.cap.dirURL) }
                    if !entry.isManagedExternally {
                        HoverAction(symbol: "✕", danger: true, help: L("移除套装（含全部子项）")) { model.removeEntry(entry) }
                    }
                }
            }
            .frame(width: 46, alignment: .trailing)
        }
        .padding(EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15))
        .background(Ink.bundleHead)
        .overlay(alignment: .bottom) { Ink.hairline2.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture {
            guard query.isEmpty else { return }
            if model.expanded.contains(entry.id) { model.expanded.remove(entry.id) }
            else { model.expanded.insert(entry.id) }
        }
    }

    private func childList(_ kids: [Capability]) -> some View {
        // v2.7.1：子项自适应分栏——1280 单栏（PATCH-02 原样），~1900 双栏，2400+ 三栏
        let cols = max(1, min(3, Int((model.winSize.width - 120) / 620)))
        let rows = stride(from: 0, to: kids.count, by: cols).map { Array(kids[$0..<min($0 + cols, kids.count)]) }
        return VStack(spacing: 0) {
            if cols == 1 {
                HStack(spacing: 10) {
                    Spacer()
                    ForEach(model.tools) { t in
                        Text(String(t.name.split(separator: " ").first ?? "").uppercased())
                            .frame(width: 52)
                    }
                    Text(L("版本")).frame(width: 96, alignment: .trailing)
                    Color.clear.frame(width: 46)
                }
                .font(.ui(9, .bold)).kerning(0.7)
                .foregroundStyle(Color(hex: 0xB3AE9E))
                .padding(EdgeInsets(top: 6, leading: 8, bottom: 3, trailing: 8))
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { ri, row in
                HStack(alignment: .top, spacing: 18) {
                    ForEach(row) { c in
                        childRow(c, isLast: ri == rows.count - 1)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(0..<(cols - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
    }

    private func childRow(_ c: Capability, isLast: Bool) -> some View {
        let cf = model.kbFocusId == c.id
        return HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(treeGlyph(isLast: isLast))
                    .font(.mono(12))
                    .foregroundStyle(Ink.offGlyph)
                PeekableName(cap: c, entry: entry, font: .ui(12, .semibold), color: Color(hex: 0x222222), query: query)
                TypeTag(type: c.type)
                Text(highlight(c.desc, query))
                    .font(.ui(11))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(model.tools.enumerated()), id: \.element.id) { i, t in
                StatusCell(status: c.status(t.id), a11y: "\(c.name) · \(t.name)") { childCellTap(c, tool: t) }
                    .frame(width: 52)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(cf && model.kbToolIdx == i ? Ink.blue.opacity(0.12) : .clear))
            }
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                if entry.changedMembers?.contains(c.name) == true { MemberUpdateDot() }
                Text(c.version ?? "—")
                    .font(.ui(11))
                    .foregroundStyle(Ink.tertiary)
                    .monospacedDigit()
            }
            .frame(width: 96, alignment: .trailing)
            HStack {
                if hoverChild == c.id {
                    HoverAction(symbol: "↗", danger: false, help: L("在编辑器中打开")) { model.openInEditor(c.dirURL) }
                }
            }
            .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(cf ? Color(hex: 0xEEF3FD) : (hoverChild == c.id ? Ink.chrome : .clear)))
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            if cf { model.kbFocusFrame = frame }
        }
        .onHover { hoverChild = $0 ? c.id : (hoverChild == c.id ? nil : hoverChild) }
        .accessibilityAction(named: L("在编辑器中打开")) { model.openInEditor(c.dirURL) }
        .id(c.id)
    }

    private func childCellTap(_ c: Capability, tool: Tool) {
        let st = c.status(tool.id)
        if st == .on || st == .off {
            model.toggle(cap: c, entry: entry, tool: tool)
        } else {
            model.openFix(FixTarget(issueKind: st, cap: c, entry: entry, tool: tool,
                                    anchor: currentClickPoint(), flip: shouldFlip()))
        }
    }
}

// ── 空 store 态 ──────────────────────────────────────────

struct EmptyPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Text(L("\(abbrev(model.fs.env.storeRoot.path)) — 空"))
                .font(.mono(13))
                .foregroundStyle(Ink.tertiary)
                .padding(.bottom, 14)
            Text(L("还没有任何能力"))
                .font(.ui(18, .bold))
                .foregroundStyle(Ink.ink)
                .padding(.bottom, 6)
            Text(L("粘贴一个 GitHub 仓库或本地路径，\n安装一次，挂载到所有 AI 工具。"))
                .font(.ui(12.5))
                .foregroundStyle(Ink.secondary2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.bottom, 18)
            HStack(spacing: 8) {
                Button { model.sheet = .add } label: {
                    Text(L("+ 粘贴 URL 添加"))
                        .font(.ui(12.5, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Ink.ink))
                }
                .buttonStyle(.plain)
                Button {
                    model.scanLocalForOnboarding()
                } label: {
                    Text(L("扫描本地目录"))
                        .font(.ui(12.5, .semibold)).foregroundStyle(Color(hex: 0x444444))
                        .padding(.horizontal, 14).frame(height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.control2, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.window)
    }
}

// ── 点击锚点（窗口坐标，左上原点）────────────────────────

@MainActor
func currentClickPoint() -> CGPoint {
    guard let event = NSApp.currentEvent, let window = event.window else { return CGPoint(x: 640, y: 300) }
    let p = event.locationInWindow
    return CGPoint(x: p.x, y: window.frame.height - p.y)
}

// ── 键盘焦点视觉（PATCH-02）──────────────────────────────

extension View {
    /// 行焦点环：蓝描边 + 2px 外环；并把行的窗口坐标回填给 model（修复弹层锚点）
    func kbRowFocus(_ focused: Bool, radius: CGFloat, model: AppModel) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(Ink.blue.opacity(focused ? 0.18 : 0), lineWidth: 2)
                .padding(-2)
        )
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            if focused { model.kbFocusFrame = frame }
        }
    }

    /// pill / 单元格的工具列焦点环
    @ViewBuilder
    func kbCellRing(_ active: Bool) -> some View {
        if active {
            overlay(Capsule().stroke(Ink.blue.opacity(0.40), lineWidth: 2).padding(-2))
        } else {
            self
        }
    }
}

@MainActor
func shouldFlip(threshold: CGFloat = 0.63) -> Bool {
    // 设计空间 820 高：修复弹层 y>520（0.63），详情 peek y>430（0.52）向上翻
    guard let event = NSApp.currentEvent, let window = event.window else { return false }
    let yTop = window.frame.height - event.locationInWindow.y
    return yTop > window.frame.height * threshold
}

/// 可点击的能力名称（PATCH-01）：悬停下划线提示，点击开详情 peek
struct PeekableName: View {
    @Environment(AppModel.self) private var model
    let cap: Capability
    let entry: Entry
    let font: Font
    let color: Color
    let query: String
    @State private var hovered = false

    var body: some View {
        Button {
            model.openPeek(cap: cap, entry: entry, anchor: currentClickPoint(), flip: shouldFlip(threshold: 0.52))
        } label: {
            Text(highlight(cap.name, query))
                .font(font)
                .foregroundStyle(color)
                .underline(hovered)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(L("查看详情"))
    }
}
