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
    @State private var updateHovered = false
    @State private var cliHovered = false
    @State private var upstreamHovered = false

    var body: some View {
        VStack(spacing: 0) {
            hero
            statStrip
            let envW = model.activeEnvWarnings()
            if !envW.isEmpty { envBanner(envW) }
            if !model.issues.isEmpty || !model.updates.isEmpty || !model.cliUpdates.isEmpty
                || model.upstreamNewItemCount > 0 { banner }
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
                checkUpdatesButton
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

    /// 手动检查更新（v2.14）：曾只埋在设置弹层里，用户找不到——常驻 hero 右侧。
    /// 检查中变 spinner 防重入（checkUpdates 内部也有 guard），结果走 toast 如实报告。
    private var checkUpdatesButton: some View {
        Button { model.checkUpdates() } label: {
            HStack(spacing: 5) {
                if model.checkingUpdates {
                    ProgressView().controlSize(.small).frame(width: 12, height: 12)
                } else {
                    Text("↻").font(.mono(13, .semibold))
                }
                Text(model.checkingUpdates ? L("检查中…") : L("检查更新"))
                    .font(.ui(12.5, .semibold))
            }
            .foregroundStyle(Ink.secondary2)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.control, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(model.checkingUpdates)
        .help(L("逐源比对上游内容，发现新版亮出更新徽标"))
        .accessibilityLabel(L("检查更新"))
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
            if t.connected {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(on)").font(.ui(20, .bold)).foregroundStyle(Ink.green).monospacedDigit()
                        Text(L("已激活")).font(.ui(10, .semibold)).foregroundStyle(Ink.statOnLabel)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        // 未挂载是有意义的统计数（不是装饰），用 secondary2 过 AA（曾用 offGlyph 仅 2.55:1）
                        Text("\(off)").font(.ui(14, .semibold)).foregroundStyle(Ink.secondary2).monospacedDigit()
                        Text(L("未挂载")).font(.ui(10)).foregroundStyle(Ink.secondary2)
                    }
                }
            } else {
                // 没装这个工具：不显示会让人误以为「装了」的数字，直接标未安装
                Text(L("未安装")).font(.ui(13, .semibold)).foregroundStyle(Ink.tertiary)
                    .frame(height: 24, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .opacity(t.connected ? 1 : 0.6)
        .overlay(alignment: .trailing) { cellDivider(!last) }
    }

    // ── 主区：卡片矩阵 / 账本表格 ──

    @ViewBuilder
    private var content: some View {
        switch model.viewMode {
        case .grid: grid
        case .list: listView
        }
    }

    // ── 账本表格视图（v2.13）：与卡片同数据、同过滤、同键盘焦点 ──

    private var listView: some View {
        let list = items
        return VStack(spacing: 0) {
            if list.isEmpty {
                VStack(spacing: 4) {
                    Text(L("无匹配结果")).font(.ui(13, .semibold)).foregroundStyle(Ink.secondary2)
                    noMatchHint
                }
                .frame(maxWidth: .infinity).padding(.vertical, 64)
            } else {
                VStack(spacing: 0) {
                    TableHeader(tools: model.tools)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(list) { tableRow($0) }
                            }
                        }
                        .onChange(of: model.kbFocusId) { _, id in
                            if let id { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) } }
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Ink.card))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(EdgeInsets(top: 6, leading: 28, bottom: 24, trailing: 28))
            }
        }
        .background(Ink.window)
        .onAppear { syncKbList(list) }
        // v2.16 修复：曾回填未提升的 items——展开套装被 promoteExpanded 挪到最前后，
        // ↑↓ 键盘顺序与屏幕顺序脱节（回填必须用实际渲染的 list）
        .onChange(of: kbIds(list)) { _, _ in syncKbList(list) }
    }

    @ViewBuilder
    private func tableRow(_ item: DisplayItem) -> some View {
        switch item {
        case .bundle(let e, let kids):
            TableBundleRow(entry: e, open: kids != nil, query: q)
            if let kids {
                ForEach(kids) { c in
                    TableCapRow(cap: c, entry: e, fromBundle: e.name, child: true, query: q)
                }
            }
        case .cap(let c, let e, let from):
            TableCapRow(cap: c, entry: e, fromBundle: from, child: false, query: q)
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

    // ── 环境横幅（v2.17）──────────────────────────────────

    private func envBanner(_ warnings: [EnvWarning]) -> some View {
        VStack(spacing: 0) {
            ForEach(warnings) { w in
                HStack(spacing: 10) {
                    Text("⚠").font(.mono(12))
                    Text(w.message)
                        .font(.ui(12))
                        .foregroundStyle(Color(hex: 0x3A4A6A))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button { model.dismissEnvWarning(w.id) } label: {
                        Text(L("知道了"))
                            .font(.ui(11, .semibold))
                            .foregroundStyle(Ink.blue)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ink.blue.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28).padding(.vertical, 8)
                .background(Color(hex: 0xE8F0FF))
                .overlay(alignment: .bottom) { Color(hex: 0xC5D4F0).frame(height: 1) }
            }
        }
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
            if !model.issues.isEmpty && (!model.updates.isEmpty || model.upstreamNewItemCount > 0) {
                Text("·").foregroundStyle(Color(hex: 0xD8CFAE))
            }
            if !model.updates.isEmpty {
                // 可点击：跳到待更新条目（展开套装+闪烁定位），多个时循环跳——
                // 计数是技能数不是源数：套装里 3 个成员有新版，这里就是 3
                Button { model.jumpToNextUpdate() } label: {
                    HStack(spacing: 6) {
                        Text("↑").font(.mono(12))
                        Text(L("\(model.updateItemCount) 个技能可更新"))
                            .underline(updateHovered)
                    }
                    .font(.ui(12, .semibold))
                    .foregroundStyle(Ink.amberText)
                }
                .buttonStyle(.plain)
                .onHover { updateHovered = $0 }
                .help(model.updates.count > 1 ? L("点击逐个定位待更新的技能（循环）") : L("点击定位待更新的技能"))
            }
            if model.upstreamNewItemCount > 0 {
                if !model.issues.isEmpty || !model.updates.isEmpty {
                    Text("·").foregroundStyle(Color(hex: 0xD8CFAE))
                }
                Button { model.jumpToNextUpstreamNew() } label: {
                    HStack(spacing: 6) {
                        Text("+").font(.mono(12, .bold))
                        Text(L("上游新增 \(model.upstreamNewItemCount) 个未装"))
                            .underline(upstreamHovered)
                    }
                    .font(.ui(12, .semibold))
                    .foregroundStyle(Ink.blue)
                }
                .buttonStyle(.plain)
                .onHover { upstreamHovered = $0 }
                .help(L("点击定位有上游新增技能的套装（循环）"))
            }
            if !model.cliUpdates.isEmpty {
                if !model.issues.isEmpty || !model.updates.isEmpty || model.upstreamNewItemCount > 0 {
                    Text("·").foregroundStyle(Color(hex: 0xD8CFAE))
                }
                // 全局 CLI 的更新提醒（v2.14）：点击打开 CLI 巡检矩阵
                Button { model.sheet = .cli } label: {
                    HStack(spacing: 6) {
                        Text("⌨").font(.mono(12))
                        Text(L("\(model.cliUpdates.count) 个 CLI 可升级"))
                            .underline(cliHovered)
                    }
                    .font(.ui(12, .semibold))
                    .foregroundStyle(Ink.amberText)
                }
                .buttonStyle(.plain)
                .onHover { cliHovered = $0 }
                .help(L("npm 全局安装的命令行工具有新版——点击查看版本矩阵"))
            }
            Text(L("点击 ✕ / ◐ / ↑ / + 可逐项处理"))
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
                    Text(L("全部更新 (\(model.updateItemCount))"))
                        .font(.ui(11.5, .semibold)).foregroundStyle(Color(hex: 0x5A4A14))
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: 0xCDB878), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            if model.upstreamNewItemCount > 0 {
                Button { model.installAllUpstreamNew() } label: {
                    Text(L("全部安装 (\(model.upstreamNewItemCount))"))
                        .font(.ui(11.5, .semibold)).foregroundStyle(Ink.blue)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ink.blue.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(L("把检查到的上游新增技能全部装进 store 并按默认工具挂载"))
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
            if filtering {
                Text(L("\(capCount) 项匹配"))
                    .font(.ui(11.5, .semibold)).foregroundStyle(Ink.blue)
            } else {
                statusLegend   // 常驻图例，两视图都显示——● —— ◐ ✕ 不再是密码表
            }
            viewToggle
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }

    /// 状态符号图例：普通用户一眼看懂矩阵里的 ● — ◐ ✕ 是什么
    private var statusLegend: some View {
        HStack(spacing: 10) {
            ForEach([LinkStatus.on, .off, .stub, .broken], id: \.self) { st in
                HStack(spacing: 3) {
                    Text(st.glyph).font(.mono(11, st == .off ? .regular : .bold)).foregroundStyle(st.color)
                    Text(st.stateLabel).font(.ui(11)).foregroundStyle(Ink.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("图例") + "：" + [LinkStatus.on, .off, .stub, .broken].map { $0.stateLabel }.joined(separator: "、"))
    }

    /// 卡片 / 表格 双视图分段切换（v2.13，过滤行右端）
    private var viewToggle: some View {
        HStack(spacing: 0) {
            toggleBtn(.grid, "square.grid.2x2", L("卡片视图"))
            toggleBtn(.list, "line.3.horizontal", L("表格视图"))
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.control2, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.leading, 4)
    }

    private func toggleBtn(_ mode: ViewMode, _ symbol: String, _ label: String) -> some View {
        let active = model.viewMode == mode
        return Button { model.viewMode = mode } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? .white : Ink.tertiary)
                .frame(width: 28, height: 24)
                .background(active ? Ink.ink : Ink.card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
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
        // 计数按实际展示的子集（v2.16 修复：搜索命中套装成员时只列匹配子集，
        // 计数却按全员报——界面列 1 个、chip 行说「8 项匹配」）
        items.reduce(0) {
            switch $1 {
            case .cap: $0 + 1
            case .bundle(let e, let kids): $0 + (kids ?? e.children ?? []).count
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
        // v2.16 修复：曾回填未提升的 items——展开套装被 promoteExpanded 挪到最前后，
        // ↑↓ 键盘顺序与屏幕顺序脱节（回填必须用实际渲染的 list）
        .onChange(of: kbIds(list)) { _, _ in syncKbList(list) }
    }

    /// 空结果提示按原因分支——类型过滤、空搜索时曾显示病句『没有能力匹配 ""』
    @ViewBuilder
    private var noMatchHint: some View {
        if q.isEmpty, let tf = model.typeFilter {
            Text(L("没有 \(tf.rawValue) 类型的能力。点 + 添加，或切回「全部」。"))
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
                        HoverAction(symbol: "↗", danger: false, help: L("在访达中显示")) { model.openInEditor(entry.cap.dirURL) }
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
                    } else if entry.skippedUpdate {
                        SkippedTag { model.unskipUpdate(entry) }
                    }
                    if entry.hasUpstreamNew {
                        UpstreamNewBadge(count: entry.upstreamNewCount, help: entry.upstreamNewHelp) {
                            model.installUpstreamNew(entry)
                        }
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
        .contextMenu { bundleContextMenu(entry, model: model) }
        // hover 才入树的 ↗/✕ 对 VoiceOver 不存在——动作挂在卡片上兜底。
        // marketplace 套装不宣告「移除」（v2.16：曾宣告动作但闭包内静默 no-op）
        .accessibilityAction(named: L("在访达中显示")) { model.openInEditor(entry.cap.dirURL) }
        .accessibilityActions {
            if !entry.isManagedExternally {
                Button(L("移除套装")) { model.removeEntry(entry) }
            }
        }
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
                        HoverAction(symbol: "↗", danger: false, help: L("在访达中显示")) { model.openInEditor(cap.dirURL) }
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
                    .opacity(t.connected ? 1 : 0.5)   // 没装的工具淡显，点了会先确认
                    .help(t.connected ? "" : L("\(t.name) 似乎还没安装"))
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
        .contextMenu { capContextMenu(cap, entry, fromBundle: fromBundle, model: model) }
        .accessibilityAction(named: L("在访达中显示")) { model.openInEditor(cap.dirURL) }
        .accessibilityAction(named: L("移除")) { if fromBundle == nil { model.removeEntry(entry) } }
        .id(cap.id)
    }

    private var focused: Bool { model.kbFocusId == cap.id }
    private var broken: Bool { cap.isBroken(model.tools) }
    private var brokenCause: String { cap.firstBrokenCause(model.tools) }

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
            } else if fromBundle == nil, entry.skippedUpdate {
                SkippedTag { model.unskipUpdate(entry) }
            } else if fromBundle != nil, entry.changedMembers?.contains(cap.name) == true {
                // 套装子项的待更新标记：类型过滤下平铺成员看不到套装头徽标，提醒补到行。
                // 更新单位是整个源（applyUpdate 只换有变化的成员），点它更新所属套装
                if model.updatingIds.contains(entry.id) {
                    UpdatingDot()
                } else {
                    MemberUpdateDot { model.runUpdate(entry.id) }
                }
            }
            if fromBundle == nil, entry.hasUpstreamNew {
                UpstreamNewBadge(count: entry.upstreamNewCount, help: entry.upstreamNewHelp) {
                    model.installUpstreamNew(entry)
                }
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
                    UpdateBadge(latest: latest, help: entry.updateHelp) { model.runUpdate(entry.id) }
                } else if entry.skippedUpdate {
                    SkippedTag { model.unskipUpdate(entry) }
                }
                    if entry.hasUpstreamNew {
                        UpstreamNewBadge(count: entry.upstreamNewCount, help: entry.upstreamNewHelp) {
                            model.installUpstreamNew(entry)
                        }
                    }
            }
            .font(.ui(11.5))
            .foregroundStyle(Ink.secondary)
            .monospacedDigit()
            .frame(width: 104)
            HStack(spacing: 2) {
                if hovered {
                    HoverAction(symbol: "↗", danger: false, help: L("在访达中显示")) { model.openInEditor(entry.cap.dirURL) }
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
            // Bundle chip 下套装是强制展开的——曾照样暗改 expanded 集合，
            // 界面毫无反应、切回「全部」后套装莫名多开多合（v2.16）
            guard query.isEmpty, model.typeFilter != .bundle else { return }
            if model.expanded.contains(entry.id) { model.expanded.remove(entry.id) }
            else { model.expanded.insert(entry.id) }
        }
        .contextMenu { bundleContextMenu(entry, model: model) }
        // hover 才入树的 ↗/✕ 对 VoiceOver 不存在——展开态头行此前漏了兜底（v2.16）
        .accessibilityAction(named: L("在访达中显示")) { model.openInEditor(entry.cap.dirURL) }
        .accessibilityAction(named: L("移除套装")) { if !entry.isManagedExternally { model.removeEntry(entry) } }
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
                    HoverAction(symbol: "↗", danger: false, help: L("在访达中显示")) { model.openInEditor(c.dirURL) }
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
        // v2.16：卡片子行曾是全应用唯一没有右键菜单的行（表格同款行有）
        .contextMenu { capContextMenu(c, entry, fromBundle: entry.name, model: model) }
        .accessibilityAction(named: L("在访达中显示")) { model.openInEditor(c.dirURL) }
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
            // 给完全没用过的人讲清这东西是干嘛的——别假设他懂 skill/挂载/symlink
            Text(L("Popskill 帮你把一份 AI 技能装一次，同时挂给 Claude Code 和 Codex 等工具。\n粘贴一个 GitHub 仓库或本地文件夹，就能开始。"))
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
                .help(L("粘贴一个 GitHub 仓库或本地文件夹，安装进 store 并挂载到所选工具"))
                Button {
                    model.scanLocalForOnboarding()
                } label: {
                    Text(L("扫描本地目录"))
                        .font(.ui(12.5, .semibold)).foregroundStyle(Color(hex: 0x444444))
                        .padding(.horizontal, 14).frame(height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.control2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(L("找出你已经手动放进 Claude / Codex 的技能，收编进 Popskill 统一管理（动手前会先让你确认）"))
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

// ── 账本表格视图组件（v2.13）──────────────────────────────

/// 表格列宽（名称列弹性，其余固定）——表头与各行必须用同一套，列才对齐
enum TableCols {
    static let type: CGFloat = 64
    static let author: CGFloat = 104
    static let tool: CGFloat = 60
    static let version: CGFloat = 84
    static let tokens: CGFloat = 74
}

/// 工具列短名（"Claude Code" → "Claude"）
private func toolShort(_ t: Tool) -> String { String(t.name.split(separator: " ").first ?? "") }
/// 表格用紧凑 token（"220.5k"，不带 " tokens"）
private func tokenK(_ n: Int) -> String { n > 0 ? String(format: "%.1fk", Double(n) / 1000) : "—" }

struct TableHeader: View {
    let tools: [Tool]
    var body: some View {
        HStack(spacing: 0) {
            th(L("名称")).frame(maxWidth: .infinity, alignment: .leading)
            th(L("类型")).frame(width: TableCols.type, alignment: .leading)
            th(L("作者")).frame(width: TableCols.author, alignment: .leading)
            ForEach(tools) { t in th(toolShort(t)).frame(width: TableCols.tool) }
            th(L("版本")).frame(width: TableCols.version, alignment: .trailing)
            th("Tokens").frame(width: TableCols.tokens, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Ink.tableHeadBg)
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }
    private func th(_ s: String) -> some View {
        Text(s.uppercased()).font(.ui(9.5, .bold)).tracking(0.5)
            .foregroundStyle(Ink.tertiary).lineLimit(1)
    }
}

/// 独立能力 / 套装子项 的表格行
struct TableCapRow: View {
    @Environment(AppModel.self) private var model
    let cap: Capability
    let entry: Entry
    let fromBundle: String?
    let child: Bool
    let query: String
    @State private var hovered = false

    private var focused: Bool { model.kbFocusId == cap.id }
    private var broken: Bool { cap.isBroken(model.tools) }
    private var brokenCause: String { cap.firstBrokenCause(model.tools) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if child {
                    Text("│").font(.mono(11)).foregroundStyle(Ink.offDot).padding(.leading, 6)
                }
                PeekableName(cap: cap, entry: entry,
                             font: .ui(child ? 12 : 12.5, child ? .medium : .semibold),
                             color: broken ? Ink.red : (child ? Ink.secondary2 : Ink.ink), query: query)
                if broken { BrokenBadge(cause: brokenCause) }
                // v2.14：表格行的更新提示——独立行整徽标，套装子行迷你角标（点了都更新所属源）
                if fromBundle == nil, model.updatingIds.contains(entry.id) {
                    UpdatingDot()
                } else if fromBundle == nil, entry.hasUpdate, let latest = entry.latest {
                    UpdateBadge(latest: latest) { model.runUpdate(entry.id) }
                } else if fromBundle == nil, entry.skippedUpdate {
                    SkippedTag { model.unskipUpdate(entry) }
                } else if fromBundle != nil, entry.changedMembers?.contains(cap.name) == true,
                          !model.updatingIds.contains(entry.id) {
                    MemberUpdateDot { model.runUpdate(entry.id) }
                }
                if fromBundle == nil, entry.hasUpstreamNew {
                    UpstreamNewBadge(count: entry.upstreamNewCount, help: entry.upstreamNewHelp) {
                        model.installUpstreamNew(entry)
                    }
                }
                Spacer(minLength: 6)
                if hovered {
                    HoverAction(symbol: "↗", danger: false, help: L("在访达中显示")) { model.openInEditor(cap.dirURL) }
                    if fromBundle == nil {
                        HoverAction(symbol: "✕", danger: true, help: L("移除")) { model.removeEntry(entry) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if child { Color.clear } else { TypeTag(type: cap.type) }
            }
            .frame(width: TableCols.type, alignment: .leading)
            author.frame(width: TableCols.author, alignment: .leading)
            ForEach(Array(model.tools.enumerated()), id: \.element.id) { i, t in
                // 焦点环贴住 28×24 状态格本体，再 frame 到列宽居中——
                // 别套在 60pt 列上(会被 Capsule 拉成横椭圆)
                StatusCell(status: cap.status(t.id), a11y: "\(cap.name) · \(toolShort(t))") { cellTap(t) }
                    .overlay {
                        if focused && model.kbToolIdx == i {
                            RoundedRectangle(cornerRadius: 5).stroke(Ink.blue.opacity(0.40), lineWidth: 2)
                                .frame(width: 30, height: 26)
                        }
                    }
                    .opacity(t.connected ? 1 : 0.5)
                    .frame(width: TableCols.tool)
            }
            Text(cap.version.map { "v\($0)" } ?? "—")
                .font(.mono(11)).foregroundStyle(Ink.tertiary)
                .frame(width: TableCols.version, alignment: .trailing)
            Text(tokenK(cap.tokens))
                .font(.mono(11)).foregroundStyle(Ink.tertiary).monospacedDigit()
                .frame(width: TableCols.tokens, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(rowBg)
        .overlay(alignment: .bottom) { Ink.tableHairline.frame(height: 1) }
        .kbRowFocus(focused, radius: 4, model: model)
        .onHover { hovered = $0 }
        .contextMenu { capContextMenu(cap, entry, fromBundle: fromBundle, model: model) }
        .accessibilityElement(children: .contain)
        // 表格行的 hover 动作对 VoiceOver 不存在——补与卡片同款兜底（v2.16）
        .accessibilityAction(named: L("在访达中显示")) { model.openInEditor(cap.dirURL) }
        .accessibilityActions {
            if fromBundle == nil { Button(L("移除")) { model.removeEntry(entry) } }
        }
        .id(cap.id)
    }

    @ViewBuilder private var author: some View {
        if let a = cap.author {
            Text(highlight(a, query)).font(.ui(11)).foregroundStyle(Ink.tertiary).lineLimit(1)
        } else {
            Text("—").font(.ui(11)).foregroundStyle(Ink.tertiary)
        }
    }

    private var rowBg: Color {
        if focused { return Ink.blue.opacity(0.07) }
        if broken { return Ink.brokenCardBg }
        return child ? Ink.tableRowAlt : Ink.card
    }

    private func cellTap(_ tool: Tool) {
        let st = cap.status(tool.id)
        if st == .on || st == .off {
            model.toggle(cap: cap, entry: entry, tool: tool)
        } else {
            model.openFix(FixTarget(issueKind: st, cap: cap, entry: entry, tool: tool,
                                    anchor: currentClickPoint(), flip: shouldFlip()))
        }
    }
}

/// 套装表头行（可展开）：分数聚合 + 披露三角
struct TableBundleRow: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    let open: Bool
    let query: String
    @State private var hovered = false

    private var focused: Bool { model.kbFocusId == entry.id }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(open ? "▼" : "▶").font(.mono(9)).foregroundStyle(Color(hex: 0x444444)).frame(width: 16)
                Text(highlight(entry.name, query)).font(.ui(12.5, .semibold)).foregroundStyle(Ink.ink).lineLimit(1)
                Text(L("\(entry.children?.count ?? 0) 项")).font(.ui(11)).foregroundStyle(Ink.secondary).fixedSize()
                // v2.14：表格视图曾完全没有更新徽标（v2.13 引入表格时的疏漏）——补到头行
                if model.updatingIds.contains(entry.id) {
                    UpdatingDot()
                } else if entry.hasUpdate, let latest = entry.latest {
                    UpdateBadge(latest: latest, help: entry.updateHelp) { model.runUpdate(entry.id) }
                } else if entry.skippedUpdate {
                    SkippedTag { model.unskipUpdate(entry) }
                }
                    if entry.hasUpstreamNew {
                        UpstreamNewBadge(count: entry.upstreamNewCount, help: entry.upstreamNewHelp) {
                            model.installUpstreamNew(entry)
                        }
                    }
                Spacer(minLength: 6)
                if hovered {
                    HoverAction(symbol: "↗", danger: false, help: L("在访达中显示")) { model.openInEditor(entry.cap.dirURL) }
                    if !entry.isManagedExternally {
                        HoverAction(symbol: "✕", danger: true, help: L("移除套装（含全部子项）")) { model.removeEntry(entry) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TypeTag(type: .bundle).frame(width: TableCols.type, alignment: .leading)
            Text(entry.cap.author ?? "—").font(.ui(11)).foregroundStyle(Ink.tertiary).lineLimit(1)
                .frame(width: TableCols.author, alignment: .leading)
            ForEach(model.tools) { t in
                FractionCell(agg: aggregate(entry.children ?? [], toolId: t.id))
                    .frame(width: TableCols.tool)
            }
            Text(entry.cap.version.map { "v\($0)" } ?? "—")
                .font(.mono(11)).foregroundStyle(Ink.tertiary)
                .frame(width: TableCols.version, alignment: .trailing)
            Text(tokenK(entry.cap.tokens))
                .font(.mono(11)).foregroundStyle(Ink.tertiary).monospacedDigit()
                .frame(width: TableCols.tokens, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(focused ? Ink.blue.opacity(0.07) : Ink.bundleHead)
        .overlay(alignment: .bottom) { Ink.tableHairline.frame(height: 1) }
        .kbRowFocus(focused, radius: 4, model: model)
        .onHover { hovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            guard query.isEmpty, model.typeFilter != .bundle else { return }
            if model.expanded.contains(entry.id) { model.expanded.remove(entry.id) }
            else { model.expanded.insert(entry.id) }
        }
        .contextMenu { bundleContextMenu(entry, model: model) }
        .accessibilityAction(named: L("在访达中显示")) { model.openInEditor(entry.cap.dirURL) }
        .accessibilityActions {
            if !entry.isManagedExternally {
                Button(L("移除套装")) { model.removeEntry(entry) }
            }
        }
        .id(entry.id)
    }
}

// ── 右键菜单（v2.13.1）：核心动作不再只藏在 hover 里，符合 mac 肌肉记忆 ──

@MainActor @ViewBuilder
func capContextMenu(_ cap: Capability, _ entry: Entry, fromBundle: String?, model: AppModel) -> some View {
    Button(L("查看详情")) {
        model.openPeek(cap: cap, entry: entry, anchor: currentClickPoint(), flip: shouldFlip(threshold: 0.52))
    }
    Button(L("在访达中显示")) { model.openInEditor(cap.dirURL) }
    // 跳过作用于源级；套装成员行也给入口（类型过滤平铺时套装头行不可见，v2.16）
    if entry.hasUpdate {
        Button(L("跳过此版本")) { model.skipUpdate(entry) }
    } else if entry.skippedUpdate {
        Button(L("恢复更新提醒")) { model.unskipUpdate(entry) }
    }
    if entry.hasUpstreamNew {
        Button(L("安装上游新增 (\(entry.upstreamNewCount))")) { model.installUpstreamNew(entry) }
    }
    if fromBundle == nil, !entry.isManagedExternally {
        Divider()
        Button(L("移除"), role: .destructive) { model.removeEntry(entry) }
    }
}

@MainActor @ViewBuilder
func bundleContextMenu(_ entry: Entry, model: AppModel) -> some View {
    // 套装头行曾没有任何「查看详情」入口——能力名可 peek、套装名不可（v2.16）
    Button(L("查看详情")) {
        model.openPeek(cap: entry.cap, entry: entry, anchor: currentClickPoint(), flip: shouldFlip(threshold: 0.52))
    }
    Button(L("在访达中显示")) { model.openInEditor(entry.cap.dirURL) }
    if entry.hasUpdate {
        Button(L("跳过此版本")) { model.skipUpdate(entry) }
    } else if entry.skippedUpdate {
        Button(L("恢复更新提醒")) { model.unskipUpdate(entry) }
    }
    if entry.hasUpstreamNew {
        Button(L("安装上游新增 (\(entry.upstreamNewCount))")) { model.installUpstreamNew(entry) }
    }
    if !entry.isManagedExternally {
        Divider()
        Button(L("移除套装（含全部子项）"), role: .destructive) { model.removeEntry(entry) }
    }
}
