import CryptoKit
import Foundation

// 文件系统引擎 — 文件系统就是数据库（SPEC.md §8）。
// store（~/.agents）按类型分 skills/ agents/ mcp/ bin/，工具侧同名子目录放 symlink。
//
// 套装的现实语义：工具侧既可能是「整套一条 symlink」（全量挂载），也可能是
// 「物化目录 + 逐子项 symlink」（部分挂载）。单独开关某个子项时自动物化。

struct StoreEnv {
    var storeRoot: URL
    var toolRoots: [String: URL]   // toolId → ~/.claude 等

    static func real() -> StoreEnv {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let store = ProcessInfo.processInfo.environment["POPSKILL_STORE_ROOT"]
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
            ?? home.appendingPathComponent(".agents")
        return StoreEnv(storeRoot: store, toolRoots: [
            "claude": home.appendingPathComponent(".claude"),
            "codex": home.appendingPathComponent(".codex"),
        ])
    }
}

/// ~/.agents/.popskill.json — 随 store 同步的应用元数据（源 URL / 自动更新 / 工具默认挂载）
struct StoreMeta: Codable {
    struct EntryMeta: Codable {
        var sourceUrl: String?
        var autoUpdate: Bool?
        var latest: String?
    }
    struct ToolMeta: Codable {
        var defaultTarget: Bool?
    }
    var entries: [String: EntryMeta] = [:]
    var tools: [String: ToolMeta] = [:]
}

struct SyncInfo: Equatable {
    var isGitRepo = false
    var clean = false
    var lastSync: Date?
    var storeSizeMB: Int?
}

enum StoreError: LocalizedError {
    case alreadyExists(String)
    case notASymlink(String)
    case sourceUnsupported(String)
    case resolveFailed(String)
    case unsafeName(String)

    var errorDescription: String? {
        switch self {
        case .alreadyExists(let n): "store 中已存在 \(n)"
        case .notASymlink(let p): "\(abbrev(p)) 不是 popskill 管理的 symlink，已跳过"
        case .sourceUnsupported(let m): m
        case .resolveFailed(let m): m
        case .unsafeName(let n): "不安全的目录名：\(n)"
        }
    }
}

/// 目录名安全校验（吸收 cc-switch 的防目录遍历，v2.1）：
/// 拒绝空名、路径分隔、.. 上跳、隐藏目录名。
func sanitizeName(_ name: String) throws -> String {
    guard !name.isEmpty, !name.hasPrefix("."),
          !name.contains("/"), !name.contains(".."), !name.contains("\0") else {
        throw StoreError.unsafeName(name)
    }
    return name
}

struct StoreFS {
    let env: StoreEnv
    let fm = FileManager.default

    var metaURL: URL { env.storeRoot.appendingPathComponent(".popskill.json") }
    var trashURL: URL { env.storeRoot.appendingPathComponent(".trash") }

    // ── 元数据 ────────────────────────────────────────────

    func loadMeta() -> StoreMeta {
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(StoreMeta.self, from: data) else { return StoreMeta() }
        return meta
    }

    func saveMeta(_ meta: StoreMeta) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(meta).write(to: metaURL, options: .atomic)
    }

    // ── 扫描 ─────────────────────────────────────────────

    func scanTools(meta: StoreMeta) -> [Tool] {
        let defs: [(String, String)] = [("claude", "Claude Code"), ("codex", "Codex CLI")]
        return defs.compactMap { id, name in
            guard let root = env.toolRoots[id] else { return nil }
            return Tool(
                id: id, name: name, root: root,
                connected: fm.fileExists(atPath: root.path),
                defaultTarget: meta.tools[id]?.defaultTarget ?? true
            )
        }
    }

    func scanEntries(tools: [Tool], meta: StoreMeta) -> [Entry] {
        var entries: [Entry] = []
        for kind in [CapType.skill, .agent, .mcp, .cli] {
            let kindDir = env.storeRoot.appendingPathComponent(kind.dirName)
            guard let names = try? fm.contentsOfDirectory(atPath: kindDir.path) else { continue }
            for name in names.sorted() where !name.hasPrefix(".") {
                let dir = kindDir.appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir.path, isDirectory: &isDir) else { continue }
                if kind == .cli {
                    // bin/ 下可执行文件或目录都算一条 CLI
                    entries.append(makeStandalone(name: name, type: .cli, dir: dir, tools: tools, meta: meta))
                    continue
                }
                guard isDir.boolValue else { continue }
                if kind == .skill && !hasManifest(dir) && isBundleDir(dir) {
                    entries.append(makeBundle(name: name, dir: dir, tools: tools, meta: meta))
                } else {
                    entries.append(makeStandalone(name: name, type: kind, dir: dir, tools: tools, meta: meta))
                }
            }
        }
        return entries
    }

    private func hasManifest(_ dir: URL) -> Bool {
        fm.fileExists(atPath: dir.appendingPathComponent("SKILL.md").path)
    }

    /// 无 SKILL.md 但存在带 SKILL.md 的子目录 ⇒ 套装
    private func isBundleDir(_ dir: URL) -> Bool {
        guard let subs = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
        return subs.contains { hasManifest(dir.appendingPathComponent($0)) }
    }

    private func makeStandalone(name: String, type: CapType, dir: URL, tools: [Tool], meta: StoreMeta) -> Entry {
        var cap = makeCap(name: name, type: type, dir: dir)
        for t in tools {
            let (st, cause) = linkStatus(linkPath: toolLinkPath(t, kind: type, name: name), expectedTarget: dir)
            cap.links[t.id] = st
            if let cause { cap.brokenCause[t.id] = cause }
        }
        let m = meta.entries[name]
        return Entry(id: name, cap: cap, children: nil,
                     sourceUrl: m?.sourceUrl, latest: m?.latest, autoUpdate: m?.autoUpdate ?? false)
    }

    private func makeBundle(name: String, dir: URL, tools: [Tool], meta: StoreMeta) -> Entry {
        var head = makeCap(name: name, type: .bundle, dir: dir)
        var children: [Capability] = []
        let subNames = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            .filter { !$0.hasPrefix(".") && hasManifest(dir.appendingPathComponent($0)) }
        for sub in subNames {
            var c = makeCap(name: sub, type: .skill, dir: dir.appendingPathComponent(sub), id: "\(name)/\(sub)")
            for t in tools {
                let bundleLink = toolLinkPath(t, kind: .bundle, name: name)
                let (st, cause) = bundleChildStatus(bundleLink: bundleLink, bundleDir: dir, childName: sub)
                c.links[t.id] = st
                if let cause { c.brokenCause[t.id] = cause }
            }
            children.append(c)
        }
        head.tokens = children.reduce(0) { $0 + $1.tokens }
        if head.desc.isEmpty {
            head.desc = "\(children.count) 项 skill 套装"
        }
        let m = meta.entries[name]
        return Entry(id: name, cap: head, children: children,
                     sourceUrl: m?.sourceUrl, latest: m?.latest, autoUpdate: m?.autoUpdate ?? false)
    }

    private func makeCap(name: String, type: CapType, dir: URL, id: String? = nil) -> Capability {
        let front = frontmatter(dir.appendingPathComponent("SKILL.md"))
        return Capability(
            id: id ?? name,
            name: name,
            type: type,
            desc: front["description"] ?? "",
            version: front["version"],
            author: front["author"],
            tokens: type == .cli ? 0 : estimateTokens(dir),
            dirURL: dir,
            readme: extractReadme(dir, type: type)
        )
    }

    /// 详情 peek 的文档摘要（PATCH-01）：SKILL.md 正文首段截 ~120 字；
    /// CLI 无 SKILL.md，用 README 首段并加前缀。扫描时提取，peek 打开不读盘。
    func extractReadme(_ dir: URL, type: CapType) -> String? {
        if type == .cli {
            let para = firstParagraph(of: dir.appendingPathComponent("README.md"), skipFrontmatter: false)
            return "二进制 CLI，无 SKILL.md。" + (para ?? "")
        }
        return firstParagraph(of: dir.appendingPathComponent("SKILL.md"), skipFrontmatter: true)
    }

    func firstParagraph(of url: URL, skipFrontmatter: Bool) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
        if skipFrontmatter, lines.first?.hasPrefix("---") == true {
            lines = lines.dropFirst()
            if let end = lines.firstIndex(where: { $0.hasPrefix("---") }) {
                lines = lines[(end + 1)...]
            }
        }
        var para: [String] = []
        var inFence = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("<!--") || line.hasPrefix(">") {
                if para.isEmpty { continue }
                break
            }
            para.append(line)
        }
        guard !para.isEmpty else { return nil }
        let joined = para.joined(separator: " ")
        return joined.count > 120 ? String(joined.prefix(120)) + "…" : joined
    }

    // ── 链接解析 ──────────────────────────────────────────

    func toolLinkPath(_ tool: Tool, kind: CapType, name: String) -> URL {
        tool.root.appendingPathComponent(kind.dirName).appendingPathComponent(name)
    }

    /// 单一路径的链接状态：symlink→store 且目标存在 = on；目标丢失 = broken；
    /// 真实目录/文件（非 symlink）= stub（本地副本，未托管）；不存在 = off。
    func linkStatus(linkPath: URL, expectedTarget: URL) -> (LinkStatus, String?) {
        let p = linkPath.path
        guard let attrs = try? fm.attributesOfItem(atPath: p) else { return (.off, nil) }
        if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            guard let dest = try? fm.destinationOfSymbolicLink(atPath: p) else { return (.broken, "断链") }
            let resolved = URL(fileURLWithPath: dest, relativeTo: linkPath.deletingLastPathComponent()).standardizedFileURL
            if fm.fileExists(atPath: resolved.path) { return (.on, nil) }
            return (.broken, "断链")
        }
        return (.stub, "本地副本")
    }

    /// 套装子项状态：整套 symlink ⇒ 全部跟随；物化目录 ⇒ 逐子项判定。
    func bundleChildStatus(bundleLink: URL, bundleDir: URL, childName: String) -> (LinkStatus, String?) {
        let p = bundleLink.path
        guard let attrs = try? fm.attributesOfItem(atPath: p) else { return (.off, nil) }
        if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            guard let dest = try? fm.destinationOfSymbolicLink(atPath: p) else { return (.broken, "断链") }
            let resolved = URL(fileURLWithPath: dest, relativeTo: bundleLink.deletingLastPathComponent()).standardizedFileURL
            if fm.fileExists(atPath: resolved.appendingPathComponent(childName).path) { return (.on, nil) }
            return (.broken, "断链")
        }
        // 物化目录：逐子项
        return linkStatus(
            linkPath: bundleLink.appendingPathComponent(childName),
            expectedTarget: bundleDir.appendingPathComponent(childName)
        )
    }

    // ── 链接写操作（防呆：只动 symlink，真目录只走回收站）──

    func createLink(at linkPath: URL, to target: URL) throws {
        try fm.createDirectory(at: linkPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: linkPath.path) || isSymlink(linkPath) {
            try removeLink(at: linkPath)
        }
        try fm.createSymbolicLink(at: linkPath, withDestinationURL: target)
    }

    /// 只删除 symlink；真实文件/目录抛错（防呆核心）
    func removeLink(at linkPath: URL) throws {
        guard isSymlink(linkPath) else {
            if fm.fileExists(atPath: linkPath.path) { throw StoreError.notASymlink(linkPath.path) }
            return
        }
        try fm.removeItem(at: linkPath)
    }

    func isSymlink(_ url: URL) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    /// 真实目录移入 store 回收站（可逆），返回回收位置。
    /// 吸收 cc-switch 的备份保留策略：回收站最多留 20 份，旧的物理删除。
    @discardableResult
    func moveToTrash(_ url: URL) throws -> URL {
        try fm.createDirectory(at: trashURL, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = trashURL.appendingPathComponent("\(url.lastPathComponent)-\(stamp)")
        try fm.moveItem(at: url, to: dest)
        pruneTrash()
        return dest
    }

    static let trashRetainCount = 20

    func pruneTrash(keep: Int = StoreFS.trashRetainCount) {
        guard let items = try? fm.contentsOfDirectory(
            at: trashURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        guard items.count > keep else { return }
        let sorted = items.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for old in sorted.dropFirst(keep) { try? fm.removeItem(at: old) }
    }

    /// 独立能力 / 套装整体 开↔关
    func setLink(tool: Tool, kind: CapType, name: String, storeDir: URL, on: Bool) throws {
        let link = toolLinkPath(tool, kind: kind, name: name)
        if on {
            try createLink(at: link, to: storeDir)
        } else {
            try removeLink(at: link)
        }
    }

    /// 套装子项开关 — 整套 symlink 时先物化为逐子项链接目录
    func setBundleChildLink(tool: Tool, bundleName: String, bundleDir: URL, childName: String, allChildren: [String], on: Bool) throws {
        let bundleLink = toolLinkPath(tool, kind: .bundle, name: bundleName)
        if isSymlink(bundleLink) {
            // 物化：删除整链，重建目录，按当前(全 on)状态铺逐子项链接
            try removeLink(at: bundleLink)
            try fm.createDirectory(at: bundleLink, withIntermediateDirectories: true)
            for c in allChildren {
                try createLink(at: bundleLink.appendingPathComponent(c), to: bundleDir.appendingPathComponent(c))
            }
        }
        let childLink = bundleLink.appendingPathComponent(childName)
        if on {
            try createLink(at: childLink, to: bundleDir.appendingPathComponent(childName))
        } else {
            try removeLink(at: childLink)
        }
    }

    /// 修复：本地副本（真实目录）→ 移入回收站后改建 symlink
    func replaceCopyWithLink(at linkPath: URL, target: URL) throws {
        if fm.fileExists(atPath: linkPath.path) && !isSymlink(linkPath) {
            try moveToTrash(linkPath)
        }
        try createLink(at: linkPath, to: target)
    }

    // ── 安装 / 移除 ───────────────────────────────────────

    struct PlanItem: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let type: CapType
        let desc: String
        let version: String?
        let tokens: Int
    }

    struct ResolvedSource {
        let url: String
        let kind: SourceKind
        let entryName: String
        let isBundle: Bool
        let items: [PlanItem]
        let stagingDir: URL    // 待入 store 的目录（local 源 = 原地，github = 临时 clone）
        let version: String?
    }

    /// 解析来源：local 直接扫描；github 浅 clone 到临时目录再扫描；npm 暂不支持。
    func resolve(_ rawUrl: String) throws -> ResolvedSource {
        let url = rawUrl.trimmingCharacters(in: .whitespaces)
        let kind = SourceKind.of(url)
        switch kind {
        case .npm:
            throw StoreError.sourceUnsupported("npm 源将在 v2.1 支持，目前请用 GitHub 仓库或本地路径")
        case .local:
            let dir = URL(fileURLWithPath: NSString(string: url).expandingTildeInPath).standardizedFileURL
            guard fm.fileExists(atPath: dir.path) else { throw StoreError.resolveFailed("路径不存在：\(url)") }
            return try resolveDir(dir, url: url, kind: .local)
        case .github:
            var clean = url
            for prefix in ["https://", "http://"] where clean.hasPrefix(prefix) { clean.removeFirst(prefix.count) }
            let cloneURL = "https://\(clean).git"
            let tmp = fm.temporaryDirectory.appendingPathComponent("popskill-stage-\(UUID().uuidString.prefix(8))")
            let r = run("/usr/bin/git", ["clone", "--depth", "1", cloneURL, tmp.path])
            guard r.status == 0 else { throw StoreError.resolveFailed("git clone 失败：\(r.err.prefix(200))") }
            try? fm.removeItem(at: tmp.appendingPathComponent(".git"))
            return try resolveDir(tmp, url: clean, kind: .github)
        }
    }

    private func resolveDir(_ dir: URL, url: String, kind: SourceKind) throws -> ResolvedSource {
        let name = dir.lastPathComponent
        let front = frontmatter(dir.appendingPathComponent("SKILL.md"))
        if hasManifest(dir) {
            let item = PlanItem(name: name, type: .skill, desc: front["description"] ?? "",
                                version: front["version"], tokens: estimateTokens(dir))
            return ResolvedSource(url: url, kind: kind, entryName: name, isBundle: false,
                                  items: [item], stagingDir: dir, version: front["version"])
        }
        // 套装：找带 SKILL.md 的子目录
        let subs = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            .filter { !$0.hasPrefix(".") && hasManifest(dir.appendingPathComponent($0)) }
        guard !subs.isEmpty else {
            throw StoreError.resolveFailed("未找到 SKILL.md — 该源不是 skill 也不是套装")
        }
        let items = subs.map { sub -> PlanItem in
            let d = dir.appendingPathComponent(sub)
            let f = frontmatter(d.appendingPathComponent("SKILL.md"))
            return PlanItem(name: sub, type: .skill, desc: f["description"] ?? "",
                            version: f["version"], tokens: estimateTokens(d))
        }
        return ResolvedSource(url: url, kind: kind, entryName: name, isBundle: true,
                              items: items, stagingDir: dir, version: nil)
    }

    /// 安装：staging → store/skills/<name>，再为选中工具建链
    func install(_ src: ResolvedSource, linkTools: [Tool]) throws {
        let name = try sanitizeName(src.entryName)
        let dest = env.storeRoot.appendingPathComponent(CapType.skill.dirName).appendingPathComponent(name)
        guard !fm.fileExists(atPath: dest.path) else { throw StoreError.alreadyExists(src.entryName) }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: src.stagingDir, to: dest)
        if src.kind == .github { try? fm.removeItem(at: src.stagingDir) }
        for t in linkTools {
            try createLink(at: toolLinkPath(t, kind: src.isBundle ? .bundle : .skill, name: src.entryName), to: dest)
        }
        var meta = loadMeta()
        meta.entries[src.entryName] = StoreMeta.EntryMeta(sourceUrl: src.url, autoUpdate: false, latest: nil)
        saveMeta(meta)
    }

    /// 移除条目：撤全部 symlink（含物化目录）→ store 副本移入回收站
    func removeEntry(_ entry: Entry, tools: [Tool]) throws {
        for t in tools {
            let link = toolLinkPath(t, kind: entry.cap.type, name: entry.name)
            if isSymlink(link) {
                try removeLink(at: link)
            } else if entry.isBundle, fm.fileExists(atPath: link.path) {
                // 物化目录：先撤子项 symlink，空了再删目录
                for c in entry.children ?? [] {
                    let cl = link.appendingPathComponent(c.name)
                    if isSymlink(cl) { try removeLink(at: cl) }
                }
                if ((try? fm.contentsOfDirectory(atPath: link.path)) ?? []).isEmpty {
                    try fm.removeItem(at: link)
                }
            }
        }
        try moveToTrash(entry.cap.dirURL)
        var meta = loadMeta()
        meta.entries.removeValue(forKey: entry.name)
        saveMeta(meta)
    }

    // ── 更新机制（v2.1，吸收 cc-switch 的内容哈希方案）─────
    // 不依赖 semver（多数 skill 没有规范版本号）：对目录算 SHA-256
    // 内容哈希（相对路径字典序，"path\0content\0" 级联，跳过隐藏文件），
    // 拉上游后比对哈希判断「有更新」。

    func computeDirHash(_ dir: URL) -> String {
        var files: [(String, URL)] = []
        func walk(_ d: URL, rel: String) {
            let items = ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).sorted()
            for name in items where !name.hasPrefix(".") {
                let url = d.appendingPathComponent(name)
                let relPath = rel.isEmpty ? name : "\(rel)/\(name)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue { walk(url, rel: relPath) } else { files.append((relPath, url)) }
            }
        }
        walk(dir, rel: "")
        var hasher = SHA256()
        for (rel, url) in files {
            hasher.update(data: Data(rel.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: (try? Data(contentsOf: url)) ?? Data())
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    struct UpdateCheck {
        let entryId: String
        let latest: String      // 上游版本号；无版本号时为 "新版"
    }

    /// 比对单个源的上游：哈希不同 ⇒ 有更新。返回 nil = 已最新或无法检查。
    /// 同时支持 github（浅 clone）与本地路径源。
    func checkUpdate(_ entry: Entry) throws -> UpdateCheck? {
        guard let url = entry.sourceUrl, SourceKind.of(url) != .npm else { return nil }
        let resolved = try resolve(url)
        defer { if resolved.kind == .github { try? fm.removeItem(at: resolved.stagingDir) } }
        let localHash = computeDirHash(entry.cap.dirURL)
        let upstreamHash = computeDirHash(resolved.stagingDir)
        guard localHash != upstreamHash else { return nil }
        let upstreamVersion = resolved.version
        let latest = (upstreamVersion != nil && upstreamVersion != entry.cap.version) ? upstreamVersion! : "新版"
        return UpdateCheck(entryId: entry.id, latest: latest)
    }

    /// 执行更新：备份现版进回收站 → 上游副本落 store → symlink 路径不变自动延续。
    func applyUpdate(_ entry: Entry) throws {
        guard let url = entry.sourceUrl else { throw StoreError.resolveFailed("该源没有记录 URL，无法更新") }
        let resolved = try resolve(url)
        let dest = entry.cap.dirURL
        try moveToTrash(dest)
        try fm.copyItem(at: resolved.stagingDir, to: dest)
        if resolved.kind == .github { try? fm.removeItem(at: resolved.stagingDir) }
        var meta = loadMeta()
        var m = meta.entries[entry.name] ?? StoreMeta.EntryMeta()
        m.latest = nil
        meta.entries[entry.name] = m
        saveMeta(meta)
    }

    func saveLatest(_ entryName: String, latest: String?) {
        var meta = loadMeta()
        var m = meta.entries[entryName] ?? StoreMeta.EntryMeta()
        m.latest = latest
        meta.entries[entryName] = m
        saveMeta(meta)
    }

    // ── 未托管目录导入（v2.1，吸收 cc-switch 的 scan_unmanaged）──
    // 工具目录里的真实目录（非 symlink）且 store 没有同名 ⇒ 未托管。
    // 导入 = 复制进 store → 原目录进回收站 → 原位换 symlink。

    struct UnmanagedDir {
        let name: String
        let toolId: String
        let url: URL
    }

    func scanUnmanaged(tools: [Tool], knownNames: Set<String>) -> [UnmanagedDir] {
        var out: [UnmanagedDir] = []
        for t in tools {
            let dir = t.root.appendingPathComponent(CapType.skill.dirName)
            for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where !name.hasPrefix(".") {
                guard !knownNames.contains(name) else { continue }
                let url = dir.appendingPathComponent(name)
                guard !isSymlink(url) else { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
                guard hasManifest(url) || isBundleDir(url) else { continue }
                out.append(UnmanagedDir(name: name, toolId: t.id, url: url))
            }
        }
        return out
    }

    /// 返回导入成功的名字
    func importUnmanaged(_ items: [UnmanagedDir]) throws -> [String] {
        var imported: [String] = []
        for item in items {
            let name = try sanitizeName(item.name)
            let dest = env.storeRoot.appendingPathComponent(CapType.skill.dirName).appendingPathComponent(name)
            guard !fm.fileExists(atPath: dest.path) else { continue }   // 后到的同名跳过
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: item.url, to: dest)
            try replaceCopyWithLink(at: item.url, target: dest)
            imported.append(name)
        }
        return imported
    }

    // ── 同步信息（store 是 git 仓时）──────────────────────

    func syncInfo() -> SyncInfo {
        var info = SyncInfo()
        let root = env.storeRoot.path
        guard fm.fileExists(atPath: env.storeRoot.appendingPathComponent(".git").path) else { return info }
        info.isGitRepo = true
        info.clean = run("/usr/bin/git", ["-C", root, "status", "--porcelain"]).out.isEmpty
        if let ts = Double(run("/usr/bin/git", ["-C", root, "log", "-1", "--format=%ct"]).out.trimmingCharacters(in: .whitespacesAndNewlines)) {
            info.lastSync = Date(timeIntervalSince1970: ts)
        }
        if let kb = Int(run("/usr/bin/du", ["-sk", root]).out.split(separator: "\t").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "") {
            info.storeSizeMB = kb / 1024
        }
        return info
    }

    // ── 解析辅助 ──────────────────────────────────────────

    /// SKILL.md YAML frontmatter 的扁平 key: value
    func frontmatter(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              text.hasPrefix("---") else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            if line.hasPrefix("---") { break }
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if val.hasPrefix("\"") && val.hasSuffix("\"") && val.count >= 2 { val = String(val.dropFirst().dropLast()) }
            if !key.isEmpty && !val.isEmpty { out[key] = val }
        }
        return out
    }

    /// 提示词体量估算：目录内（两层）全部 .md 字节数 / 4
    func estimateTokens(_ dir: URL) -> Int {
        var bytes = 0
        let level1 = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for f in level1 {
            if f.pathExtension == "md" {
                bytes += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            } else if (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let level2 = (try? fm.contentsOfDirectory(at: f, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                for g in level2 where g.pathExtension == "md" {
                    bytes += (try? g.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                }
            }
        }
        return bytes / 4
    }

    @discardableResult
    func run(_ bin: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return (-1, "", "\(error)") }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, out, err)
    }
}
