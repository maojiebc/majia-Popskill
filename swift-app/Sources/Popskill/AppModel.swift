import AppKit
import Observation
import SwiftUI
import os

/// 关键写路径留痕（Console.app 按 subsystem 过滤可见）——
/// toast 2.6 秒即逝，出问题后这是唯一能回看的证据链。
let plog = Logger(subsystem: "com.majia.popskill", category: "store")

// 打包后以 Info.plist 为准（发版脚本写入），裸二进制显示 dev（常量版本号必腐，不再写死）
let popskillVersion: String =
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"

/// 修复弹层的目标：哪个能力 × 哪个工具 × 锚点在哪
struct FixTarget: Equatable {
    let issueKind: LinkStatus        // .broken / .stub
    let cap: Capability
    let entry: Entry
    let tool: Tool
    let anchor: CGPoint              // 窗口坐标系（左上原点）：单元格底边中心
    let flip: Bool                   // 下半屏向上翻
}

/// 详情 peek 的目标（PATCH-01）
struct PeekTarget: Equatable {
    let cap: Capability
    let entry: Entry
    let anchor: CGPoint
    let flip: Bool
}

struct FixOption: Identifiable {
    enum Kind { case relink, repull, adopt, unlink, trashCopy, keep, update }
    let id = UUID()
    let kind: Kind
    let label: String
    let desc: String
    let rec: Bool
    let toast: String
}

enum SheetKind { case add, settings, sched }

/// 键盘导航焦点项（PATCH-02）：与可见顺序一致的扁平序列
struct KbItem: Equatable, Identifiable {
    let id: String          // 行 id（套装=entry.id，能力=cap.id）
    let isBundle: Bool
    let entryId: String
    let capId: String?      // 套装行为 nil
}

@MainActor
@Observable
final class AppModel {
    var fs: StoreFS
    var fake = false

    var tools: [Tool] = []
    var entries: [Entry] = []
    var syncInfo = SyncInfo()

    // UI 态
    var sheet: SheetKind?
    var toast: String?
    var toastIsError = false
    var flashId: String?
    var query = ""
    var typeFilter: CapType?         // nil = 全部
    var expanded: Set<String> = []
    var fixTarget: FixTarget?
    var peekTarget: PeekTarget?
    var searchFocused = false
    var checkingUpdates = false
    var updatingIds: Set<String> = []

    // 定时任务面板（v2.9）
    var schedTasks: [SchedTask] = []
    var schedShowVendor = false
    var schedLoading = false
    var schedBusy: Set<String> = []

    // 键盘导航（PATCH-02）
    var kbFocusId: String?
    var kbToolIdx = 0
    var kbFocusList: [KbItem] = []           // MainView 按可见顺序回填
    var kbFocusFrame: CGRect = .zero         // 聚焦行的窗口坐标（修复弹层锚点用）
    var winSize: CGSize = .zero

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// Sparkle 手动检查入口（PopskillApp 注入；裸二进制为 nil）
    @ObservationIgnored var checkAppUpdate: (() -> Void)?
    /// Sparkle 自动检查读/写（PopskillApp 注入）——设置页开关用，AppModel 不直接依赖 Sparkle
    @ObservationIgnored var sparkleAutoCheckGet: (() -> Bool)?
    @ObservationIgnored var sparkleAutoCheckSet: ((Bool) -> Void)?

    // 派生
    var stats: Stats { deriveStats(entries, tools: tools) }
    var issues: [Issue] { deriveIssues(entries, tools: tools) }
    var updates: [Entry] { deriveUpdates(entries) }
    var isEmpty: Bool { entries.isEmpty }

    init(env: StoreEnv = .real()) {
        fs = StoreFS(env: env)
        let pe = ProcessInfo.processInfo.environment
        if pe["POPSKILL_FAKE_DATA"] == "1" {
            fake = true
            (tools, entries) = Fixtures.make()
            entries = fs.sortEntries(entries)
            syncInfo = SyncInfo(isGitRepo: true, clean: true, lastSync: Date().addingTimeInterval(-120), storeSizeMB: 482)
        } else {
            refresh()
        }
        if pe["POPSKILL_EMPTY"] == "1" { entries = [] }
        switch pe["POPSKILL_SHEET"] {
        case "add": sheet = .add
        case "settings": sheet = .settings
        case "sched": sheet = .sched; reloadSched()
        default: break
        }
        // PATCH-02：套装默认全折叠（首屏密度），不再自动展开第一个
        // 调试钩子：POPSKILL_EXPAND=id1,id2 启动即展开指定套装（截图用）
        if let ids = pe["POPSKILL_EXPAND"]?.split(separator: ",") {
            ids.forEach { expanded.insert(String($0)) }
        }
        // 启动后台检查更新；开了自动更新的源直接更（v2.1）
        if !fake && pe["POPSKILL_NO_AUTOCHECK"] != "1" {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))   // 不抢首屏
                await MainActor.run { self?.checkUpdates(auto: true) }
            }
        }
        // 调试钩子：POPSKILL_ONBOARD_SCAN=1 启动后自动触发空态扫描（新用户旅程 E2E）
        if pe["POPSKILL_ONBOARD_SCAN"] == "1" {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run { self?.scanLocalForOnboarding() }
            }
        }
        // 调试钩子：POPSKILL_KB_SIM=d,d,u,l,r,space 启动后模拟键盘导航（E2E 截图用）
        if let sim = pe["POPSKILL_KB_SIM"] {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run {
                    guard let self else { return }
                    for step in sim.split(separator: ",") {
                        switch step {
                        case "d": self.kbMove(1)
                        case "u": self.kbMove(-1)
                        case "l": self.kbSetTool(self.kbToolIdx - 1)
                        case "r": self.kbSetTool(self.kbToolIdx + 1)
                        case "space": self.kbActivate()
                        default: break
                        }
                    }
                }
            }
        }
        // 调试钩子：POPSKILL_PEEK=capId 启动即开详情 peek（截图验证用）
        if let capId = pe["POPSKILL_PEEK"] {
            for e in entries {
                if let c = e.allCaps.first(where: { $0.id == capId }) {
                    expanded.insert(e.id)
                    peekTarget = PeekTarget(cap: c, entry: e, anchor: CGPoint(x: 300, y: 420), flip: false)
                }
            }
        }
        // 调试钩子：POPSKILL_FIXPOP=capId:toolId 启动即开修复弹层（截图验证用）
        if let spec = pe["POPSKILL_FIXPOP"]?.split(separator: ":"), spec.count == 2 {
            let capId = String(spec[0]), toolId = String(spec[1])
            for e in entries {
                if let c = e.allCaps.first(where: { $0.id == capId }), let t = tools.first(where: { $0.id == toolId }) {
                    expanded.insert(e.id)
                    fixTarget = FixTarget(issueKind: c.status(toolId), cap: c, entry: e, tool: t,
                                          anchor: CGPoint(x: 1100, y: 360), flip: false)
                }
            }
        }
    }

    func refresh() {
        guard !fake else { return }
        let meta = fs.loadMeta()
        tools = fs.scanTools(meta: meta)
        entries = fs.scanEntries(tools: tools, meta: meta)
        revalidateOverlays()
        let fsCopy = fs
        Task.detached { @Sendable [weak self] in
            let info = fsCopy.syncInfo()
            await MainActor.run { [weak self] in self?.syncInfo = info }
        }
    }

    /// refresh 换掉 entries 后，开着的修复弹层 / 详情 peek 持有的是旧快照——
    /// 按 id 重新解析：还在且状态没变就原位续上，否则关掉（盘面已变，别对着幻影操作）
    private func revalidateOverlays() {
        if let t = fixTarget {
            if let entry = entries.first(where: { $0.id == t.entry.id }),
               let cap = entry.allCaps.first(where: { $0.id == t.cap.id }),
               cap.status(t.tool.id) == t.issueKind {
                fixTarget = FixTarget(issueKind: t.issueKind, cap: cap, entry: entry,
                                      tool: t.tool, anchor: t.anchor, flip: t.flip)
            } else {
                fixTarget = nil
            }
        }
        if let pk = peekTarget {
            if let entry = entries.first(where: { $0.id == pk.entry.id }),
               let cap = entry.allCaps.first(where: { $0.id == pk.cap.id }) {
                peekTarget = PeekTarget(cap: cap, entry: entry, anchor: pk.anchor, flip: pk.flip)
            } else {
                peekTarget = nil
            }
        }
    }

    // ── toast / flash ────────────────────────────────────

    func say(_ msg: String, error: Bool = false) {
        toast = msg
        toastIsError = error
        toastTask?.cancel()
        toastTask = Task {
            // 错误必须比成功提示活得久——它是用户唯一的现场证据
            try? await Task.sleep(for: .seconds(error ? 6 : 2.6))
            if !Task.isCancelled { toast = nil }
        }
    }

    func sayError(_ msg: String) {
        plog.error("\(msg, privacy: .public)")
        say(msg, error: true)
    }

    func flash(_ id: String) {
        flashId = id
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if flashId == id { flashId = nil }
        }
    }

    // ── 键盘导航（PATCH-02）───────────────────────────────

    private var kbIdx: Int? {
        guard let id = kbFocusId else { return nil }
        return kbFocusList.firstIndex { $0.id == id }
    }

    func kbMove(_ delta: Int) {
        guard !kbFocusList.isEmpty else { return }
        if let i = kbIdx {
            kbFocusId = kbFocusList[max(0, min(kbFocusList.count - 1, i + delta))].id
        } else {
            kbFocusId = (delta > 0 ? kbFocusList.first : kbFocusList.last)?.id
        }
    }

    func kbSetTool(_ idx: Int) {
        guard kbFocusId != nil else { return }
        kbToolIdx = max(0, min(tools.count - 1, idx))
    }

    /// 空格/回车：套装行折叠/展开；能力行 on/off 切换、stub/broken 开修复弹层
    func kbActivate() {
        guard let i = kbIdx else { return }
        let item = kbFocusList[i]
        if item.isBundle {
            guard query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if expanded.contains(item.entryId) { expanded.remove(item.entryId) }
            else { expanded.insert(item.entryId) }
            return
        }
        guard let entry = entries.first(where: { $0.id == item.entryId }),
              let cap = entry.allCaps.first(where: { $0.id == item.capId }),
              kbToolIdx < tools.count else { return }
        let tool = tools[kbToolIdx]
        let st = cap.status(tool.id)
        if st == .on || st == .off {
            toggle(cap: cap, entry: entry, tool: tool)
        } else {
            let anchor = CGPoint(x: kbFocusFrame.midX, y: kbFocusFrame.maxY)
            let flip = winSize.height > 0 && kbFocusFrame.maxY > winSize.height * 0.63
            openFix(FixTarget(issueKind: st, cap: cap, entry: entry, tool: tool, anchor: anchor, flip: flip))
        }
    }

    /// 焦点列表更新后校验：当前焦点已不可见则清除
    func kbValidate() {
        if let id = kbFocusId, !kbFocusList.contains(where: { $0.id == id }) {
            kbFocusId = nil
        }
    }

    // ── 浮层互斥（peek 与修复弹层只存在一个）──────────────

    func openFix(_ target: FixTarget) {
        peekTarget = nil
        fixTarget = target
    }

    func openPeek(cap: Capability, entry: Entry, anchor: CGPoint, flip: Bool) {
        fixTarget = nil
        peekTarget = PeekTarget(cap: cap, entry: entry, anchor: anchor, flip: flip)
    }

    // ── 开关 ─────────────────────────────────────────────

    func toggle(cap: Capability, entry: Entry, tool: Tool) {
        guard !entry.isManagedExternally else {
            say("Marketplace 插件由 Claude Code 管理——在 Claude Code 里用 /plugin 操作")
            return
        }
        guard !updatingIds.contains(entry.id) else {
            say("\(entry.name) 正在更新中，稍候再操作")
            return
        }
        let from = cap.status(tool.id)
        guard from == .on || from == .off else { return }   // stub/broken 走修复弹层
        let to: LinkStatus = from == .on ? .off : .on
        if fake {
            mutateFake(capId: cap.id, toolId: tool.id, to: to)
        } else {
            do {
                if entry.bundleKind == .directory && cap.id != entry.cap.id {
                    try fs.setBundleChildLink(
                        tool: tool, bundleName: entry.name, bundleDir: entry.cap.dirURL,
                        childName: cap.name, allChildren: (entry.children ?? []).map(\.name), on: to == .on)
                } else {
                    // 独立条目 / 源式套装成员：都是平铺 symlink
                    try fs.setLink(tool: tool, kind: cap.layoutKind, name: cap.name, storeDir: cap.dirURL, on: to == .on)
                }
                refresh()
            } catch {
                sayError("\(to == .on ? "链接" : "断开") \(cap.name) 失败：\(error.localizedDescription)")
                return
            }
        }
        say(to == .on ? "已链接 \(cap.name) → \(tool.name)" : "已断开 \(cap.name) → \(tool.name)")
    }

    // ── 修复 ─────────────────────────────────────────────

    func fixOptions(for t: FixTarget) -> [FixOption] {
        var opts: [FixOption] = []
        if t.issueKind == .stub {
            // 真实世界的 stub = 本地副本（真实目录占着链接位）
            opts.append(FixOption(kind: .adopt, label: "改用 store 链接", desc: "原目录移入 store 回收站，换成指向 store 的 symlink", rec: true,
                                  toast: "已把 \(t.cap.name) · \(t.tool.name) 换成 store 链接"))
            opts.append(FixOption(kind: .trashCopy, label: "移除该侧副本", desc: "目录移入 store 回收站，不建链接", rec: false,
                                  toast: "已移除 \(t.cap.name) 在 \(t.tool.name) 侧的副本"))
            opts.append(FixOption(kind: .keep, label: "保持现状", desc: "保留本地副本，popskill 不接管", rec: false, toast: ""))
        } else {
            let storeExists = FileManager.default.fileExists(atPath: t.cap.dirURL.path)
            if t.entry.hasUpdate, let latest = t.entry.latest {
                opts.append(FixOption(kind: .update, label: "更新到 \(latest) 并修复", desc: "从 \(t.entry.sourceUrl ?? "源") 拉取新版，重链 symlink", rec: true,
                                      toast: "已更新 \(t.entry.name) 并修复链接"))
            }
            if storeExists {
                opts.append(FixOption(kind: .relink, label: "重链到 store 中本地版本", desc: "指回 store 中现存的目录", rec: !t.entry.hasUpdate,
                                      toast: "已重链 \(t.cap.name) · \(t.tool.name)"))
            }
            if let url = t.entry.sourceUrl, SourceKind.of(url) == .github {
                // 推荐唯一：有更新推更新，store 健在推重链，都没有才推重拉
                opts.append(FixOption(kind: .repull, label: "从源重新拉取", desc: "从 \(url) 重新获取该项",
                                      rec: !t.entry.hasUpdate && !storeExists,
                                      toast: "已从源重新拉取 \(t.cap.name)"))
            }
            opts.append(FixOption(kind: .unlink, label: "移除该侧链接", desc: "撤掉这条 symlink，其他工具不受影响", rec: false,
                                  toast: "已移除 \(t.cap.name) 在 \(t.tool.name) 侧的链接"))
        }
        return opts
    }

    func applyFix(_ opt: FixOption, target t: FixTarget) {
        defer { fixTarget = nil }
        if fake {
            let to: LinkStatus = (opt.kind == .unlink || opt.kind == .trashCopy) ? .off : .on
            if opt.kind != .keep { mutateFake(capId: t.cap.id, toolId: t.tool.id, to: to) }
            if opt.kind == .update { runUpdate(t.entry.id, quiet: true) }
            if !opt.toast.isEmpty { say(opt.toast) }
            return
        }
        do {
            let link = linkPath(cap: t.cap, entry: t.entry, tool: t.tool)
            switch opt.kind {
            case .keep:
                return
            case .relink:
                try relink(cap: t.cap, entry: t.entry, tool: t.tool)
            case .adopt:
                try fs.replaceCopyWithLink(at: link, target: t.cap.dirURL)
            case .trashCopy:
                if fs.isSymlink(link) { try fs.removeLink(at: link) } else { try fs.moveToTrash(link) }
            case .unlink:
                try fs.removeLink(at: link)
            case .repull:
                guard let url = t.entry.sourceUrl else { return }
                repull(entry: t.entry, primaryToolId: t.tool.id, url: url, toast: opt.toast)
                return   // 网络在后台跑，toast 由 repull 收尾时发
            case .update:
                try? relink(cap: t.cap, entry: t.entry, tool: t.tool)   // 先把这格链上，更新落盘后自动生效
                runUpdate(t.entry.id)
            }
            refresh()
            if !opt.toast.isEmpty { say(opt.toast) }
        } catch {
            sayError("修复 \(t.cap.name) 失败：\(error.localizedDescription)")
        }
    }

    /// 从源重拉：曾在 @MainActor 上同步跑 git clone，网络慢时整个 UI 冻死。
    /// 现照 resolveSource/runUpdate 的模式下放后台，期间条目置 updating 态。
    /// 顺序不变：先 resolve（clone 失败时本地分毫未动）→ removeEntry → install。
    private func repull(entry: Entry, primaryToolId: String, url: String, toast toastMsg: String) {
        guard !updatingIds.contains(entry.id) else { return }
        updatingIds.insert(entry.id)
        say("正在从源重新拉取 \(entry.name)…")
        let fsCopy = fs
        let allTools = tools
        Task { [weak self] in
            let result: Result<Void, Error> = await Task.detached {
                do {
                    let resolved = try fsCopy.resolve(url)
                    do {
                        try fsCopy.removeEntry(entry, tools: allTools)
                        let relinkTools = allTools.filter { tool in
                            tool.id == primaryToolId || entry.allCaps.contains { $0.status(tool.id) != .off }
                        }
                        try fsCopy.install(resolved, linkTools: relinkTools)
                    } catch {
                        // SECURITY.md 承诺临时 clone「用完即删，失败也删」——失败路径必须兜底
                        fsCopy.discardStaging(resolved)
                        throw error
                    }
                    return .success(())
                } catch { return .failure(error) }
            }.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updatingIds.remove(entry.id)
                self.refresh()
                switch result {
                case .success:
                    plog.info("repull \(entry.name, privacy: .public) ← \(url, privacy: .public) 完成")
                    if !toastMsg.isEmpty { self.say(toastMsg) }
                case .failure(let err):
                    self.sayError("重新拉取 \(entry.name) 失败：\(err.localizedDescription)")
                }
            }
        }
    }

    private func linkPath(cap: Capability, entry: Entry, tool: Tool) -> URL {
        if entry.bundleKind == .directory && cap.id != entry.cap.id {
            return fs.toolLinkPath(tool, kind: .bundle, name: entry.name).appendingPathComponent(cap.name)
        }
        return fs.toolLinkPath(tool, kind: cap.layoutKind, name: cap.name)
    }

    private func relink(cap: Capability, entry: Entry, tool: Tool) throws {
        if entry.bundleKind == .directory && cap.id != entry.cap.id {
            try fs.setBundleChildLink(tool: tool, bundleName: entry.name, bundleDir: entry.cap.dirURL,
                                      childName: cap.name, allChildren: (entry.children ?? []).map(\.name), on: true)
        } else {
            try fs.setLink(tool: tool, kind: cap.layoutKind, name: cap.name, storeDir: cap.dirURL, on: true)
        }
    }

    /// 全部修复：对每个问题执行其推荐方案
    func fixAll() {
        let list = issues
        var fixed = 0
        var skipped = 0
        var firstError: String?
        for issue in list {
            guard let entry = entries.first(where: { $0.id == issue.entryId }),
                  let cap = entry.allCaps.first(where: { $0.id == issue.capId }),
                  let tool = tools.first(where: { $0.id == issue.toolId }),
                  !updatingIds.contains(entry.id) else {
                skipped += 1   // 条目消失或正在后台换版——是跳过，不是失败
                continue
            }
            if fake {
                mutateFake(capId: cap.id, toolId: tool.id, to: .on)
                fixed += 1
            } else {
                let storeExists = FileManager.default.fileExists(atPath: cap.dirURL.path)
                do {
                    if storeExists {
                        try relink(cap: cap, entry: entry, tool: tool)
                    } else {
                        try fs.removeLink(at: linkPath(cap: cap, entry: entry, tool: tool))
                    }
                    fixed += 1
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                    plog.error("fixAll \(cap.name, privacy: .public) · \(tool.id, privacy: .public) 失败: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        if !fake { refresh() }
        // 成功/失败/跳过三态分开——红色错误只留给真出错的
        let failedCount = list.count - fixed - skipped
        if failedCount > 0 {
            sayError("修复 \(fixed) 个，\(failedCount) 个失败\(firstError.map { "：\($0)" } ?? "")")
        } else if skipped > 0 {
            say("已修复 \(fixed) 个，跳过 \(skipped) 个（正在更新中）")
        } else {
            say("已修复 \(fixed) 个链接问题")
        }
    }

    // ── 更新（v2.1：内容哈希比对，吸收自 cc-switch）────────

    /// 检查全部可检查的源；auto=true 时对开了自动更新的源直接执行更新
    func checkUpdates(auto: Bool = false) {
        guard !fake else { say("原型数据模式不检查更新"); return }
        guard !checkingUpdates else { return }
        let candidates = entries.filter { $0.sourceUrl != nil && SourceKind.of($0.sourceUrl) != .npm && !$0.isManagedExternally }
        guard !candidates.isEmpty else { say("没有可检查的源（需要 GitHub 或本地路径来源）"); return }
        checkingUpdates = true
        let fsCopy = fs
        Task { [weak self] in
            var found: [StoreFS.UpdateCheck] = []
            var fresh: [String] = []   // 检查成功且确认无更新的 entryId（用于熄灭残留徽标）
            var failed = 0
            // 失败和「确实最新」必须是两个态——曾用 try? 把断网/源被删压成 nil，
            // 然后对用户谎报「全部源已是最新」
            await withTaskGroup(of: (String, Result<StoreFS.UpdateCheck?, Error>).self) { group in
                var pending = candidates.makeIterator()
                var running = 0
                func enqueue() {
                    while running < 4, let e = pending.next() {
                        running += 1
                        group.addTask {
                            do { return (e.id, .success(try fsCopy.checkUpdate(e))) }
                            catch {
                                plog.error("检查更新失败 \(e.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                                return (e.id, .failure(error))
                            }
                        }
                    }
                }
                enqueue()
                for await (id, result) in group {
                    running -= 1
                    switch result {
                    case .success(let check): if let check { found.append(check) } else { fresh.append(id) }
                    case .failure: failed += 1
                    }
                    enqueue()
                }
            }
            let failedCount = failed
            let freshIds = fresh
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.checkingUpdates = false
                for check in found {
                    if let i = self.entries.firstIndex(where: { $0.id == check.entryId }) {
                        self.entries[i].latest = check.latest
                        self.entries[i].changedMembers = check.changedMembers
                        self.fs.saveLatest(self.entries[i].name, latest: check.latest, changed: check.changedMembers)
                    }
                }
                // 确认一致的熄灭残留徽标（如终端手动同步后；meta 由 checkUpdate 清，这里同步内存镜像）。
                // 检查失败的不在 freshIds 里——失败 ≠ 最新
                for id in freshIds {
                    if let i = self.entries.firstIndex(where: { $0.id == id }), self.entries[i].latest != nil {
                        self.entries[i].latest = nil
                        self.entries[i].changedMembers = nil
                    }
                }
                let autoTargets = auto ? self.entries.filter { $0.hasUpdate && $0.autoUpdate } : []
                if !autoTargets.isEmpty {
                    for e in autoTargets { self.runUpdate(e.id, quiet: true) }
                    self.say("自动更新 \(autoTargets.count) 个源")
                } else if failedCount > 0 {
                    // 启动自动检查的失败不弹 toast 打扰（断网开机最常见），日志已留痕；手动检查必须如实报
                    if !auto {
                        let head = found.isEmpty ? "" : "发现 \(found.count) 个源可更新；"
                        self.sayError("\(head)\(failedCount) 个源检查失败（网络或源不可达）")
                    } else if !found.isEmpty {
                        self.say("发现 \(found.count) 个源可更新（另有 \(failedCount) 个检查失败）")
                    }
                } else if !auto || !found.isEmpty {
                    self.say(found.isEmpty ? "全部源已是最新" : "发现 \(found.count) 个源可更新")
                }
            }
        }
    }

    /// 一步更新：备份 → 拉上游 → 落盘（symlink 路径不变自动延续）
    func runUpdate(_ entryId: String, quiet: Bool = false) {
        guard let entry = entries.first(where: { $0.id == entryId }) else { return }
        if fake {
            if let i = entries.firstIndex(where: { $0.id == entryId }) {
                let latest = entries[i].latest ?? "新版"
                entries[i].cap.version = entries[i].latest
                entries[i].latest = nil
                say("已更新 \(entry.name) → \(latest)")
            }
            return
        }
        guard !updatingIds.contains(entryId) else { return }
        updatingIds.insert(entryId)
        let fsCopy = fs
        Task { [weak self] in
            let result: Result<(updated: [String], upstreamNew: [String]), Error> = await Task.detached {
                do { return .success(try fsCopy.applyUpdate(entry)) }
                catch { return .failure(error) }
            }.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updatingIds.remove(entryId)
                switch result {
                case .success(let r):
                    plog.info("更新 \(entry.name, privacy: .public) 完成：\(r.updated.joined(separator: ","), privacy: .public)")
                    self.refresh()
                    if !quiet {
                        let names = r.updated.count <= 3 ? r.updated.joined(separator: "、")
                            : r.updated.prefix(3).joined(separator: "、") + " 等"
                        var msg = r.updated.count == 1 && !entry.isBundle
                            ? "已更新 \(entry.name)（旧版已入回收站）"
                            : "已更新 \(entry.name)：\(names)（旧版已入回收站）"
                        if !r.upstreamNew.isEmpty { msg += " · 上游另有 \(r.upstreamNew.count) 个未安装技能" }
                        self.say(msg)
                    }
                case .failure(let err):
                    self.sayError("更新 \(entry.name) 失败：\(err.localizedDescription)")
                }
            }
        }
    }

    func updateAll() {
        let targets = updates
        guard !targets.isEmpty else { return }
        for e in targets { runUpdate(e.id, quiet: true) }
        say("正在更新 \(targets.count) 个源…")
    }

    // ── 未托管目录导入（v2.1）─────────────────────────────

    func importUnmanaged() {
        guard !fake else { say("原型数据模式不可导入"); return }
        let known = Set(entries.flatMap { $0.allCaps.map(\.name) + [$0.name] })
        let found = fs.scanUnmanaged(tools: tools, knownNames: known)
        guard !found.isEmpty else { say("没有发现未托管的技能目录"); return }
        do {
            let imported = try fs.importUnmanaged(found)
            plog.info("导入未托管目录 \(imported.joined(separator: ","), privacy: .public)")
            refresh()
            say("已导入 \(imported.count) 个未托管目录进 store（原目录已入回收站）")
        } catch {
            sayError("导入失败：\(error.localizedDescription)")
        }
    }

    /// 空态「扫描本地目录」= 新用户引导（v2.4.1）：
    /// ① 重扫 store；② store 仍为空则扫工具目录里的未托管技能，确认后收编建链。
    func scanLocalForOnboarding() {
        refresh()
        guard entries.isEmpty else {
            say("扫描完成：发现 \(stats.total) 项能力")
            return
        }
        let found = fs.scanUnmanaged(tools: tools, knownNames: [])
        guard !found.isEmpty else {
            say("store 为空，工具目录里也没有发现技能——点「+ 添加」装第一个")
            return
        }
        let names = Set(found.map(\.name))
        if ProcessInfo.processInfo.environment["POPSKILL_AUTOCONFIRM"] != "1" {
            let alert = NSAlert()
            alert.messageText = "发现 \(names.count) 个未托管的技能目录"
            alert.informativeText = "在 Claude / Codex 目录里发现现有技能（如 \(names.sorted().prefix(3).joined(separator: "、"))…）。导入 store 统一管理，原位替换为 symlink？原目录会进 store 回收站，可恢复。"
            alert.addButton(withTitle: "导入 \(names.count) 个")
            alert.addButton(withTitle: "暂不")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            let imported = try fs.importUnmanaged(found)
            plog.info("空态收编 \(imported.joined(separator: ","), privacy: .public)")
            refresh()
            say("已导入 \(imported.count) 个技能进 store 并建链——这就是你的能力矩阵")
        } catch {
            sayError("导入失败：\(error.localizedDescription)")
        }
    }

    // ── 安装 / 移除 ───────────────────────────────────────

    func resolveSource(_ url: String) async throws -> StoreFS.ResolvedSource {
        if fake {
            // 原型行为：任意 URL → 单项 Skill 假数据
            let name = url.split(separator: "/").last.map(String.init) ?? "new-skill"
            return StoreFS.ResolvedSource(
                url: url, kind: SourceKind.of(url), entryName: name, isBundle: false,
                items: [StoreFS.PlanItem(name: name, type: .skill, desc: "从源 manifest 读取的描述", version: "1.0.0", tokens: 9200)],
                stagingDir: URL(fileURLWithPath: "/tmp"), version: "1.0.0")
        }
        let fsCopy = fs
        return try await Task.detached { try fsCopy.resolve(url) }.value
    }

    func install(_ src: StoreFS.ResolvedSource, targets: [String: Bool]) {
        let linkTools = tools.filter { targets[$0.id] == true }
        if fake {
            var cap = Capability(id: src.entryName, name: src.entryName, type: .skill,
                                 desc: src.items.first?.desc ?? "", version: src.version, author: nil,
                                 tokens: src.items.first?.tokens ?? 0, dirURL: URL(fileURLWithPath: "/tmp"))
            for t in tools { cap.links[t.id] = targets[t.id] == true ? .on : .off }
            entries.insert(Entry(id: src.entryName, cap: cap, children: nil, sourceUrl: src.url), at: 0)
        } else {
            do {
                try fs.install(src, linkTools: linkTools)
                plog.info("安装 \(src.entryName, privacy: .public) ← \(src.url, privacy: .public)，链 \(linkTools.count) 个工具")
                refresh()
            } catch {
                sayError("安装 \(src.entryName) 失败：\(error.localizedDescription)")
                return
            }
        }
        sheet = nil
        flash(src.entryName)
        say(linkTools.isEmpty ? "已保存 \(src.entryName) 到 store" : "已安装 \(src.entryName) 并链接到 \(linkTools.count) 个工具")
    }

    func removeEntry(_ entry: Entry) {
        guard !entry.isManagedExternally else {
            say("Marketplace 插件由 Claude Code 管理——在 Claude Code 里用 /plugin 卸载")
            return
        }
        guard !updatingIds.contains(entry.id) else {
            say("\(entry.name) 正在更新中，稍候再操作")
            return
        }
        let alert = NSAlert()
        alert.messageText = "移除 \(entry.name)？"
        alert.informativeText = entry.isBundle
            ? "套装连同 \(entry.children?.count ?? 0) 个子项的 store 副本与全部 symlink 都会清理（store 副本进回收站，可恢复）。"
            : "store 副本与全部 symlink 都会清理（store 副本进回收站，可恢复）。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if fake {
            entries.removeAll { $0.id == entry.id }
        } else {
            do {
                try fs.removeEntry(entry, tools: tools)
                plog.info("移除 \(entry.name, privacy: .public)（store 副本入回收站）")
                refresh()
            } catch {
                sayError("移除 \(entry.name) 失败：\(error.localizedDescription)")
                return
            }
        }
        say("store 副本与全部 symlink 已清理")
    }

    // ── 设置 ─────────────────────────────────────────────

    func toggleAutoUpdate(_ entryId: String) {
        guard let i = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[i].autoUpdate.toggle()
        guard !fake else { return }
        let on = entries[i].autoUpdate
        fs.mutateMeta { meta in
            var m = meta.entries[entryId] ?? StoreMeta.EntryMeta()
            m.autoUpdate = on
            meta.entries[entryId] = m
        }
    }

    func toggleDefaultTarget(_ toolId: String) {
        guard let i = tools.firstIndex(where: { $0.id == toolId }) else { return }
        tools[i].defaultTarget.toggle()
        guard !fake else { return }
        let on = tools[i].defaultTarget
        fs.mutateMeta { meta in
            var m = meta.tools[toolId] ?? StoreMeta.ToolMeta()
            m.defaultTarget = on
            meta.tools[toolId] = m
        }
    }

    // ── 回收站（v2.8）─────────────────────────────────────

    func restoreTrashItem(_ item: StoreFS.TrashItem) {
        do {
            try fs.restoreFromTrash(item)
            plog.info("回收站恢复 \(item.name, privacy: .public)")
            refresh()
            say("已恢复 \(item.name) 到 store——按需重新链接工具")
        } catch {
            sayError("恢复 \(item.name) 失败：\(error.localizedDescription)")
        }
    }

    func openTrash() {
        let t = fs.trashURL
        if !FileManager.default.fileExists(atPath: t.path) {
            try? FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(t)
    }

    // ── 反馈渠道（v2.8：崩了/错了至少有条路找到作者）───────

    func reportIssue() {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var comps = URLComponents(string: "https://github.com/maojiebc/majia-Popskill/issues/new")!
        comps.queryItems = [URLQueryItem(name: "body", value: """
        App: Popskill v\(popskillVersion)
        macOS: \(os)

        <!-- 描述问题。若 app 崩溃过，请附上 ~/Library/Logs/DiagnosticReports 里最新的 Popskill-*.ips 文件 -->

        """)]
        if let u = comps.url { NSWorkspace.shared.open(u) }
    }

    // ── 打开 ─────────────────────────────────────────────

    func openInEditor(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openStore() {
        NSWorkspace.shared.activateFileViewerSelecting([fs.env.storeRoot])
    }

    // ── 定时任务面板（v2.9）────────────────────────────────
    // 只读解析 launchd/crontab；写操作仅 launchctl kickstart/unload/load，全部先确认。

    private let sched = SchedEngine()

    func reloadSched() {
        guard !schedLoading else { return }
        schedLoading = true
        let engine = sched
        let notes = fs.loadMeta().schedNotes ?? [:]
        Task.detached { [weak self] in
            let tasks = engine.scan(notes: notes)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.schedTasks = tasks
                self.schedLoading = false
            }
        }
    }

    /// 保存任务人话备注（空串 = 清除），立即回写内存镜像
    func schedSaveNote(_ task: SchedTask, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        fs.saveSchedNote(task.label, note: trimmed)
        if let i = schedTasks.firstIndex(where: { $0.id == task.id }) {
            schedTasks[i].note = trimmed.isEmpty ? nil : trimmed
        }
    }

    func schedOpenLog(_ task: SchedTask) {
        guard let path = task.logPath else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            // 日志可能按天滚动（update-skills-YYYYMMDD.log）：plist 写的固定名不在时开所在目录
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    func schedKickstart(_ task: SchedTask) {
        let restart = task.behavior == .daemon
        guard schedConfirm(
            title: restart ? "重启 \(task.displayName)？" : "立刻运行 \(task.displayName)？",
            info: "等价于 launchctl kickstart -k——\(restart ? "杀掉旧进程重新拉起。" : "不等下次调度时间，现在就跑一遍。")任务输出看它自己的日志。",
            button: restart ? "重启" : "跑一次"
        ) else { return }
        schedRun(task, doneToast: "已触发 \(task.displayName)") { try $0.kickstart($1) }
    }

    func schedSetLoaded(_ task: SchedTask, to on: Bool) {
        guard schedConfirm(
            title: on ? "启用 \(task.displayName)？" : "停用 \(task.displayName)？",
            info: on ? "launchctl load——按 plist 里的调度恢复运行。"
                     : "launchctl unload——不再按时执行，plist 文件原样保留，随时可重新启用。",
            button: on ? "启用" : "停用"
        ) else { return }
        schedRun(task, doneToast: on ? "已启用 \(task.displayName)" : "已停用 \(task.displayName)") { try $0.setLoaded($1, to: on) }
    }

    private func schedRun(_ task: SchedTask, doneToast: String, _ op: @escaping (SchedEngine, SchedTask) throws -> Void) {
        guard !schedBusy.contains(task.id) else { return }
        schedBusy.insert(task.id)
        let engine = sched
        let notes = fs.loadMeta().schedNotes ?? [:]
        Task.detached { [weak self] in
            let result = Result { try op(engine, task) }
            // launchctl 状态变化（尤其 kickstart 的退出码）要一拍后才稳定
            try? await Task.sleep(for: .milliseconds(600))
            let tasks = engine.scan(notes: notes)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.schedBusy.remove(task.id)
                self.schedTasks = tasks
                switch result {
                case .success: self.say(doneToast)
                case .failure(let e): self.sayError(e.localizedDescription)
                }
            }
        }
    }

    private func schedConfirm(title: String, info: String, button: String) -> Bool {
        if ProcessInfo.processInfo.environment["POPSKILL_AUTOCONFIRM"] == "1" { return true }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // ── fake 模式的内存变更（原型语义）─────────────────────

    private func mutateFake(capId: String, toolId: String, to: LinkStatus) {
        for (ei, e) in entries.enumerated() {
            if e.isBundle {
                for (ci, c) in (e.children ?? []).enumerated() where c.id == capId {
                    entries[ei].children?[ci].links[toolId] = to
                    return
                }
            } else if e.cap.id == capId {
                entries[ei].cap.links[toolId] = to
                return
            }
        }
    }
}
