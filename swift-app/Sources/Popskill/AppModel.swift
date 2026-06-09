import AppKit
import Observation
import SwiftUI

let popskillVersion = "2.0.0"

/// 修复弹层的目标：哪个能力 × 哪个工具 × 锚点在哪
struct FixTarget: Equatable {
    let issueKind: LinkStatus        // .broken / .stub
    let cap: Capability
    let entry: Entry
    let tool: Tool
    let anchor: CGPoint              // 窗口坐标系（左上原点）：单元格底边中心
    let flip: Bool                   // 下半屏向上翻
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

enum SheetKind { case add, settings }

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
    var flashId: String?
    var query = ""
    var typeFilter: CapType?         // nil = 全部
    var expanded: Set<String> = []
    var fixTarget: FixTarget?
    var searchFocused = false

    @ObservationIgnored private var toastTask: Task<Void, Never>?

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
            syncInfo = SyncInfo(isGitRepo: true, clean: true, lastSync: Date().addingTimeInterval(-120), storeSizeMB: 482)
        } else {
            refresh()
        }
        if pe["POPSKILL_EMPTY"] == "1" { entries = [] }
        switch pe["POPSKILL_SHEET"] {
        case "add": sheet = .add
        case "settings": sheet = .settings
        default: break
        }
        if let first = entries.first(where: \.isBundle) { expanded.insert(first.id) }
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
        let fsCopy = fs
        Task.detached { @Sendable [weak self] in
            let info = fsCopy.syncInfo()
            await MainActor.run { [weak self] in self?.syncInfo = info }
        }
    }

    // ── toast / flash ────────────────────────────────────

    func say(_ msg: String) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { toast = nil }
        }
    }

    func flash(_ id: String) {
        flashId = id
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if flashId == id { flashId = nil }
        }
    }

    // ── 开关 ─────────────────────────────────────────────

    func toggle(cap: Capability, entry: Entry, tool: Tool) {
        let from = cap.status(tool.id)
        guard from == .on || from == .off else { return }   // stub/broken 走修复弹层
        let to: LinkStatus = from == .on ? .off : .on
        if fake {
            mutateFake(capId: cap.id, toolId: tool.id, to: to)
        } else {
            do {
                if entry.isBundle && cap.id != entry.cap.id {
                    try fs.setBundleChildLink(
                        tool: tool, bundleName: entry.name, bundleDir: entry.cap.dirURL,
                        childName: cap.name, allChildren: (entry.children ?? []).map(\.name), on: to == .on)
                } else {
                    try fs.setLink(tool: tool, kind: cap.type, name: cap.name, storeDir: cap.dirURL, on: to == .on)
                }
                refresh()
            } catch {
                say(error.localizedDescription)
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
            if storeExists {
                opts.append(FixOption(kind: .relink, label: "重链到 store 中本地版本", desc: "指回 store 中现存的目录", rec: true,
                                      toast: "已重链 \(t.cap.name) · \(t.tool.name)"))
            }
            if let url = t.entry.sourceUrl, SourceKind.of(url) == .github {
                opts.append(FixOption(kind: .repull, label: "从源重新拉取", desc: "从 \(url) 重新获取该项", rec: !storeExists,
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
                let resolved = try fs.resolve(url)
                try fs.removeEntry(t.entry, tools: tools)
                let relinkTools = tools.filter { tool in
                    tool.id == t.tool.id || t.entry.allCaps.contains { $0.status(tool.id) != .off }
                }
                try fs.install(resolved, linkTools: relinkTools)
            case .update:
                break   // v2.1：真实更新检查接入后启用
            }
            refresh()
            if !opt.toast.isEmpty { say(opt.toast) }
        } catch {
            say(error.localizedDescription)
        }
    }

    private func linkPath(cap: Capability, entry: Entry, tool: Tool) -> URL {
        if entry.isBundle && cap.id != entry.cap.id {
            return fs.toolLinkPath(tool, kind: .bundle, name: entry.name).appendingPathComponent(cap.name)
        }
        return fs.toolLinkPath(tool, kind: cap.type, name: cap.name)
    }

    private func relink(cap: Capability, entry: Entry, tool: Tool) throws {
        if entry.isBundle && cap.id != entry.cap.id {
            try fs.setBundleChildLink(tool: tool, bundleName: entry.name, bundleDir: entry.cap.dirURL,
                                      childName: cap.name, allChildren: (entry.children ?? []).map(\.name), on: true)
        } else {
            try fs.setLink(tool: tool, kind: cap.type, name: cap.name, storeDir: cap.dirURL, on: true)
        }
    }

    /// 全部修复：对每个问题执行其推荐方案
    func fixAll() {
        let list = issues
        for issue in list {
            guard let entry = entries.first(where: { $0.id == issue.entryId }),
                  let cap = entry.allCaps.first(where: { $0.id == issue.capId }),
                  let tool = tools.first(where: { $0.id == issue.toolId }) else { continue }
            if fake {
                mutateFake(capId: cap.id, toolId: tool.id, to: .on)
            } else {
                let storeExists = FileManager.default.fileExists(atPath: cap.dirURL.path)
                do {
                    if storeExists {
                        try relink(cap: cap, entry: entry, tool: tool)
                    } else {
                        try fs.removeLink(at: linkPath(cap: cap, entry: entry, tool: tool))
                    }
                } catch { say(error.localizedDescription) }
            }
        }
        if !fake { refresh() }
        say("已修复 \(list.count) 个链接问题")
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
                refresh()
            } catch {
                say(error.localizedDescription)
                return
            }
        }
        sheet = nil
        flash(src.entryName)
        say(linkTools.isEmpty ? "已保存 \(src.entryName) 到 store" : "已安装 \(src.entryName) 并链接到 \(linkTools.count) 个工具")
    }

    func removeEntry(_ entry: Entry) {
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
                refresh()
            } catch {
                say(error.localizedDescription)
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
        var meta = fs.loadMeta()
        var m = meta.entries[entryId] ?? StoreMeta.EntryMeta()
        m.autoUpdate = entries[i].autoUpdate
        meta.entries[entryId] = m
        fs.saveMeta(meta)
    }

    func toggleDefaultTarget(_ toolId: String) {
        guard let i = tools.firstIndex(where: { $0.id == toolId }) else { return }
        tools[i].defaultTarget.toggle()
        guard !fake else { return }
        var meta = fs.loadMeta()
        var m = meta.tools[toolId] ?? StoreMeta.ToolMeta()
        m.defaultTarget = tools[i].defaultTarget
        meta.tools[toolId] = m
        fs.saveMeta(meta)
    }

    // ── 打开 ─────────────────────────────────────────────

    func openInEditor(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openStore() {
        NSWorkspace.shared.activateFileViewerSelecting([fs.env.storeRoot])
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
