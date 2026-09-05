import SwiftUI

// 两个覆盖层：添加（粘贴 URL → 安装计划）与设置 — popskill-sheets.jsx 翻译。

// ── 共享件 ──────────────────────────────────────────────

struct SheetButton: View {
    let label: String
    var primary = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.ui(13, .semibold))
                .foregroundStyle(primary ? .white : Color(hex: 0x444444))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 7).fill(primary ? (disabled ? Color(hex: 0xB3AEA0) : Ink.ink) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(primary ? .clear : Ink.control2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.ui(10.5, .bold)).kerning(0.6)
            .foregroundStyle(Ink.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
    }
}

struct KindTag: View {
    let kind: SourceKind
    var body: some View {
        Text(kind.rawValue.uppercased())
            .font(.ui(9.5, .bold)).kerning(0.6)
            .foregroundStyle(Ink.monoDim)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Ink.control2, lineWidth: 1))
            .fixedSize()
    }
}

struct SheetRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.hairline, lineWidth: 1))
    }
}

// ── 添加弹层 ─────────────────────────────────────────────

struct AddSheet: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var plan: StoreFS.ResolvedSource?
    @State private var targets: [String: Bool] = [:]
    @State private var resolving = false
    @State private var resolveTask: Task<Void, Never>?
    @State private var error: String?
    @FocusState private var urlFocus: Bool

    private let examples = ["github.com/dotey/prompt-engineering", "github.com/anthropics/skills", "~/work/my-skills/ppt-generator"]

    var body: some View {
        Group {
            VStack(spacing: 0) {
                head
                if let plan { planBody(plan) } else { urlBody }
                foot
            }
        }
        .frame(width: 660)
        .background(Ink.window)
        .interactiveDismissDisabled(model.installing)
        // 任何方式离开弹层（取消/遮罩/esc/安装完成）都清掉临时 staging——
        // 曾经取消即把整仓副本泄漏在临时目录；解析进行中离开由 resolve 的取消回调兜底
        .onDisappear { resolveTask?.cancel(); if !model.installing { discardPlan(plan) } }
        .onAppear {
            // 未安装的工具默认不挂载（避免给新用户凭空创建 ~/.codex）
            targets = Dictionary(uniqueKeysWithValues: model.tools.map { ($0.id, $0.defaultTarget && $0.connected) })
            model.installError = nil
            urlFocus = true
            // 深链接 popskill://install?src=…（v2.17）优先于调试钩子
            if let pending = model.pendingAddURL, plan == nil {
                model.pendingAddURL = nil
                url = pending
                resolve()
            } else if let preset = ProcessInfo.processInfo.environment["POPSKILL_ADD_URL"], plan == nil {
                // 调试钩子：POPSKILL_ADD_URL 预填并自动解析（截图验证用）
                url = preset
                resolve()
            }
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("添加能力")).font(.ui(15.5, .bold)).foregroundStyle(Ink.ink)
            Text(L("粘贴 GitHub 仓库 / 本地路径 — 安装一次进 store，再选择挂载到哪些工具。"))
                .font(.ui(11.5)).foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 13, trailing: 20))
        .background(Ink.chrome)
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }

    private var urlBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: L("来源 URL"))
            TextField("github.com/owner/repo · ~/path", text: $url)
                .textFieldStyle(.plain)
                .font(.mono(12.5))
                .foregroundStyle(Ink.ink)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.control, lineWidth: 1))
                .focused($urlFocus)
                .onSubmit { resolve() }
            HStack(spacing: 6) {
                ForEach(examples, id: \.self) { x in
                    Button { url = x } label: {
                        Text(x)
                            .font(.mono(10.5))
                            .foregroundStyle(Ink.monoDim)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.white))
                            .overlay(Capsule().stroke(Color(hex: 0xE2DFD3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            if let error {
                Text(error).font(.ui(11.5)).foregroundStyle(Ink.red).padding(.top, 10)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
    }

    private func planBody(_ plan: StoreFS.ResolvedSource) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: L("来源"))
                    SheetRow {
                        KindTag(kind: plan.kind)
                        Text(plan.url)
                            .font(.mono(11.5)).foregroundStyle(Ink.ink)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer()
                        if let v = plan.version {
                            Text("v\(v)").font(.ui(11)).foregroundStyle(Ink.secondary).monospacedDigit()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: L("提供 \(plan.items.count) 项"))
                    VStack(spacing: 6) {
                        ForEach(plan.items) { item in
                            SheetRow {
                                Text(item.name).font(.ui(13, .semibold)).foregroundStyle(Ink.ink)
                                TypeTag(type: item.type)
                                Spacer()
                                if item.tokens > 0 {
                                    Text(formatTokens(item.tokens)).font(.ui(11)).foregroundStyle(Ink.tertiary)
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: L("挂载到"))
                    VStack(spacing: 6) {
                        ForEach(model.tools) { t in
                            SheetRow {
                                Text(t.name).font(.ui(13, .semibold)).foregroundStyle(Ink.ink)
                                Text("\(t.rootDisplay)\(CapType.skill.dirName)/")
                                    .font(.mono(10.5)).foregroundStyle(Ink.tertiary)
                                if !t.connected {
                                    // v2.16：曾无任何标识——随手拨开就静默建出 ~/.codex（安装时会再确认）
                                    Text(L("未安装"))
                                        .font(.ui(9.5, .bold)).kerning(0.4)
                                        .foregroundStyle(Ink.amberText)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(RoundedRectangle(cornerRadius: 3).fill(Ink.amberBadgeBg))
                                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Ink.amberBadgeBorder, lineWidth: 1))
                                        .help(L("该工具目录不存在——挂载会创建它，安装时会先跟你确认"))
                                }
                                Spacer()
                                Toggle(L("挂载到 \(t.name)"), isOn: Binding(
                                    get: { targets[t.id] ?? false }, set: { targets[t.id] = $0 }
                                )).toggleStyle(.switch).labelsHidden().disabled(model.installing)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: L("将写入"))
                    // 设计：pre 不折行 + 横向滚动
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(terminalPreview(plan))
                            .font(.mono(11))
                            .foregroundStyle(Ink.terminalText)
                            .lineSpacing(5)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Ink.terminalBg))
                }
                // 安装失败驻留证据（v2.16：曾只有 6 秒 toast，消失后计划页零线索）
                if let err = model.installError {
                    Text(err)
                        .font(.ui(11.5)).foregroundStyle(Ink.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
        }
        .frame(maxHeight: 480)
    }

    private func terminalPreview(_ plan: StoreFS.ResolvedSource) -> String {
        let store = abbrev(model.fs.env.storeRoot.path)
        var lines = ["\(store)/skills/\(plan.entryName)/"]
        for t in model.tools where targets[t.id] == true {
            lines.append("ln -s \(store)/skills/\(plan.entryName) \(t.rootDisplay)skills/\(plan.entryName)")
        }
        return lines.joined(separator: "\n")
    }

    private var foot: some View {
        HStack(spacing: 8) {
            if plan != nil {
                SheetButton(label: L("← 返回"), disabled: model.installing) { discardPlan(plan); plan = nil; error = nil; model.installError = nil }
            }
            Spacer()
            SheetButton(label: L("取消"), disabled: model.installing) { model.dismissShortTask() }
            if let plan {
                let n = model.tools.filter { targets[$0.id] == true }.count
                SheetButton(label: model.installing ? L("安装中…") : (n > 0 ? L("安装并链接 (\(n))") : L("仅保存到 store")),
                            primary: true, disabled: model.installing) {
                    model.install(plan, targets: targets)
                }
            } else {
                SheetButton(label: resolving ? L("解析中…") : L("解析 →"), primary: true,
                            disabled: url.trimmingCharacters(in: .whitespaces).isEmpty || resolving) {
                    resolve()
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
        .background(Ink.chrome)
        .overlay(alignment: .top) { Ink.hairline.frame(height: 1) }
    }

    private func resolve() {
        let u = url.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty, !resolving else { return }
        resolving = true
        error = nil
        resolveTask = Task {
            defer { resolving = false }
            do {
                let p = try await model.resolveSource(u)
                // 解析中弹层被关（Esc/遮罩）：clone 白跑也不能把整仓副本泄漏在临时目录（v2.16）
                if Task.isCancelled { discardPlan(p) } else { plan = p }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    /// 只清 Popskill 明确拥有的 staging；普通 local 源原地目录没有 cleanupRoot，绝不动。
    private func discardPlan(_ p: StoreFS.ResolvedSource?) {
        guard let p, p.cleanupRoot != nil, !model.fake else { return }
        let fsCopy = model.fs
        Task.detached { fsCopy.discardStaging(p) }
    }
}
