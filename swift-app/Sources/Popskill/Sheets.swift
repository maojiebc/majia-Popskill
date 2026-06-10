import SwiftUI

// 两个覆盖层：添加（粘贴 URL → 安装计划）与设置 — popskill-sheets.jsx 翻译。

// ── 共享件 ──────────────────────────────────────────────

struct PsSwitch: View {
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Ink.blue : Ink.control2)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .frame(width: 13, height: 13)
                    .padding(2)
            }
            .frame(width: 30, height: 17)
            .animation(.easeOut(duration: 0.15), value: on)
        }
        .buttonStyle(.plain)
    }
}

struct SheetButton: View {
    let label: String
    var primary = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.ui(12.5, .semibold))
                .foregroundStyle(primary ? .white : Color(hex: 0x444444))
                .padding(.horizontal, 14)
                .frame(height: 30)
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

/// 弹层外壳：遮罩 + 居中模卡
struct SheetShell<Content: View>: View {
    let width: CGFloat
    let onDismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color(hex: 0x18140C, alpha: 0.34)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            content
                .frame(width: width)
                .background(RoundedRectangle(cornerRadius: 12).fill(Ink.window))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.control, lineWidth: 1))
                .compositingGroup()   // 先压成一层再投影——否则每个子行各自投影，把暖纸底糊成灰
                .shadow(color: .black.opacity(0.30), radius: 32, y: 24)
        }
    }
}

// ── 添加弹层 ─────────────────────────────────────────────

struct AddSheet: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var plan: StoreFS.ResolvedSource?
    @State private var targets: [String: Bool] = [:]
    @State private var resolving = false
    @State private var error: String?
    @FocusState private var urlFocus: Bool

    private let examples = ["github.com/dotey/prompt-engineering", "npm:@upstash/context7-mcp", "~/work/my-skills/ppt-generator"]

    var body: some View {
        SheetShell(width: 520, onDismiss: { model.sheet = nil }) {
            VStack(spacing: 0) {
                head
                if let plan { planBody(plan) } else { urlBody }
                foot
            }
        }
        .onAppear {
            // 未安装的工具默认不挂载（避免给新用户凭空创建 ~/.codex）
            targets = Dictionary(uniqueKeysWithValues: model.tools.map { ($0.id, $0.defaultTarget && $0.connected) })
            urlFocus = true
            // 调试钩子：POPSKILL_ADD_URL 预填并自动解析（截图验证用）
            if let preset = ProcessInfo.processInfo.environment["POPSKILL_ADD_URL"], plan == nil {
                url = preset
                resolve()
            }
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("添加能力").font(.ui(15.5, .bold)).foregroundStyle(Ink.ink)
            Text("粘贴 GitHub 仓库 / npm 包 / 本地路径 — 安装一次进 store，再选择挂载到哪些工具。")
                .font(.ui(11.5)).foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 13, trailing: 20))
        .background(Ink.chrome)
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }

    private var urlBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "来源 URL")
            TextField("github.com/owner/repo · npm:pkg · ~/path", text: $url)
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
                    SectionLabel(text: "来源")
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
                    SectionLabel(text: "提供 \(plan.items.count) 项")
                    VStack(spacing: 6) {
                        ForEach(plan.items) { item in
                            SheetRow {
                                Text(item.name).font(.ui(12.5, .semibold)).foregroundStyle(Ink.ink)
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
                    SectionLabel(text: "挂载到")
                    VStack(spacing: 6) {
                        ForEach(model.tools) { t in
                            SheetRow {
                                Text(t.name).font(.ui(12.5, .semibold)).foregroundStyle(Ink.ink)
                                Text("\(t.rootDisplay)\(CapType.skill.dirName)/")
                                    .font(.mono(10.5)).foregroundStyle(Ink.tertiary)
                                Spacer()
                                PsSwitch(on: targets[t.id] ?? false) {
                                    targets[t.id] = !(targets[t.id] ?? false)
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "将写入")
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
                SheetButton(label: "← 返回") { plan = nil; error = nil }
            }
            Spacer()
            SheetButton(label: "取消") { model.sheet = nil }
            if let plan {
                let n = model.tools.filter { targets[$0.id] == true }.count
                SheetButton(label: n > 0 ? "安装并链接 (\(n))" : "仅保存到 store", primary: true) {
                    model.install(plan, targets: targets)
                }
            } else {
                SheetButton(label: resolving ? "解析中…" : "解析 →", primary: true,
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
        Task {
            defer { resolving = false }
            do {
                plan = try await model.resolveSource(u)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// ── 设置弹层 ─────────────────────────────────────────────

struct SettingsSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SheetShell(width: 560, onDismiss: { model.sheet = nil }) {
            VStack(spacing: 0) {
                head
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        sourcesSection
                        toolsSection
                        storeSection
                        aboutSection
                    }
                    .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                }
                .frame(maxHeight: 560)
            }
        }
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("设置").font(.ui(15.5, .bold)).foregroundStyle(Ink.ink)
                Text("源、工具与 store — 全部配置都在这一页。")
                    .font(.ui(11.5)).foregroundStyle(Ink.secondary)
            }
            Spacer()
            Button { model.sheet = nil } label: {
                Text("esc")
                    .font(.mono(11))
                    .foregroundStyle(Color(hex: 0x666666))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.control2, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 13, trailing: 20))
        .background(Ink.chrome)
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "已添加的源（\(model.entries.count)）")
            VStack(spacing: 6) {
                ForEach(model.entries) { e in
                    SheetRow {
                        KindTag(kind: SourceKind.of(e.sourceUrl))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.sourceUrl ?? abbrev(e.cap.dirURL.path))
                                .font(.mono(11.5)).foregroundStyle(Ink.ink)
                                .lineLimit(1).truncationMode(.tail)
                            Text(sourceSub(e)).font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                        }
                        Spacer(minLength: 8)
                        if e.isManagedExternally {
                            Text("/plugin 管理").font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                        } else {
                            if e.hasUpdate, let latest = e.latest {
                                UpdateBadge(latest: latest) { model.runUpdate(e.id) }
                            }
                            PsSwitch(on: e.autoUpdate) { model.toggleAutoUpdate(e.id) }
                            HoverAction(symbol: "✕", danger: true, help: "移除该源（含其能力）") { model.removeEntry(e) }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button { model.sheet = .add } label: {
                    Text("+ 粘贴 URL 添加")
                        .font(.ui(11.5, .semibold)).foregroundStyle(Color(hex: 0x444444))
                        .padding(.horizontal, 10).frame(height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.control2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { model.checkUpdates() } label: {
                    Text(model.checkingUpdates ? "检查中…" : "检查更新")
                        .font(.ui(11.5, .semibold)).foregroundStyle(Color(hex: 0x444444))
                        .padding(.horizontal, 10).frame(height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.control2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(model.checkingUpdates)
                Text("开关 = 自动更新。移除源会同时卸载它提供的能力与 symlink。")
                    .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
            }
            .padding(.top, 6)
        }
    }

    private func sourceSub(_ e: Entry) -> String {
        let n = e.allCaps.count
        var s = "提供 \(e.name)\(n > 1 ? " 等 \(n) 项" : "")"
        if let v = e.cap.version { s += " · v\(v)" }
        return s
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "工具（挂载目标）")
            VStack(spacing: 6) {
                ForEach(model.tools) { t in
                    SheetRow {
                        Circle().fill(t.connected ? Ink.green : Ink.offDot).frame(width: 7, height: 7)
                        Text(t.name).font(.ui(12.5, .semibold)).foregroundStyle(Ink.ink)
                        Text(t.rootDisplay).font(.mono(10.5)).foregroundStyle(Ink.tertiary)
                        Spacer()
                        Text("新安装默认挂载").font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                        PsSwitch(on: t.defaultTarget) { model.toggleDefaultTarget(t.id) }
                    }
                }
            }
            Button { model.say("自定义工具将在 v2.1 支持") } label: {
                Text("+ 添加工具…")
                    .font(.ui(11.5, .semibold)).foregroundStyle(Color(hex: 0x444444))
                    .padding(.horizontal, 10).frame(height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.control2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private var storeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Store 与同步")
            VStack(spacing: 6) {
                SheetRow {
                    Text(abbrev(model.fs.env.storeRoot.path)).font(.mono(11.5)).foregroundStyle(Ink.ink)
                    Spacer()
                    Button { model.importUnmanaged() } label: {
                        Text("导入未托管目录")
                            .font(.ui(11)).foregroundStyle(Color(hex: 0x444444))
                            .padding(.horizontal, 8).frame(height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.control2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("把 ~/.claude / ~/.codex 里的真实技能目录收编进 store 并换成 symlink")
                    Button { model.openStore() } label: {
                        Text("↗ 在编辑器中打开")
                            .font(.ui(11)).foregroundStyle(Color(hex: 0x444444))
                            .padding(.horizontal, 8).frame(height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.control2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                SheetRow {
                    Text("同步后端").font(.ui(12.5)).foregroundStyle(Ink.ink)
                    Spacer()
                    Text(syncBackendLabel)
                        .font(.ui(11.5, .semibold))
                        .foregroundStyle(model.syncInfo.isGitRepo ? Color(hex: 0x5A7A5F) : Ink.tertiary)
                }
            }
            Text("store 在设备间同步；symlink 是各机本地状态，不参与同步。")
                .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                .padding(.top, 4)
        }
    }

    private var syncBackendLabel: String {
        guard model.syncInfo.isGitRepo else { return "未配置" }
        return model.syncInfo.clean ? "Git · 已同步" : "Git · 有未提交改动"
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "关于")
            HStack(spacing: 10) {
                Text(aboutLine).font(.ui(11.5)).foregroundStyle(Ink.secondary)
                Spacer()
                if model.checkAppUpdate != nil {
                    Button { model.checkAppUpdate?() } label: {
                        Text("检查 App 更新…")
                            .font(.ui(11)).foregroundStyle(Color(hex: 0x444444))
                            .padding(.horizontal, 8).frame(height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.control2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("立即向更新源询问新版本（自动检查每小时一次）")
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var aboutLine: String {
        var parts = ["popskill v\(popskillVersion)"]
        if let mb = model.syncInfo.storeSizeMB { parts.append("store \(mb) MB") }
        parts.append("MIT")
        return parts.joined(separator: " · ")
    }
}
