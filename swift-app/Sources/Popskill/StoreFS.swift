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
        let lock = loadLock()
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
                    entries.append(makeStandalone(name: name, type: .cli, dir: dir, tools: tools, meta: meta, lock: lock))
                    continue
                }
                guard isDir.boolValue else { continue }
                if kind == .skill && !hasManifest(dir) && isBundleDir(dir) {
                    entries.append(makeBundle(name: name, dir: dir, tools: tools, meta: meta))
                } else {
                    entries.append(makeStandalone(name: name, type: kind, dir: dir, tools: tools, meta: meta, lock: lock))
                }
            }
        }
        return sortEntries(groupBySource(entries, meta: meta))
    }

    /// 排序：套装置顶（按名称），独立项按 类型（Skill→Agent→MCP→CLI）→ 名称
    func sortEntries(_ entries: [Entry]) -> [Entry] {
        let rank: [CapType: Int] = [.skill: 1, .agent: 2, .mcp: 3, .cli: 4]
        return entries.sorted { a, b in
            let ra = a.isBundle ? 0 : (rank[a.cap.type] ?? 9)
            let rb = b.isBundle ? 0 : (rank[b.cap.type] ?? 9)
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // ── 来源回填链（v2.1，对应真实环境的多种安装机制）──────
    // .popskill.json（app 自装）→ .skill-lock.json（npx skills 生态）
    // → 目录自带 .git 的 remote（独立 clone）→ frontmatter homepage（兜底）

    struct LockEntry {
        let source: String        // "jimliu/baoyu-skills"
        let sourceUrl: String?    // "https://github.com/jimliu/baoyu-skills.git"
        let skillPath: String?    // "skills/baoyu-article-illustrator/SKILL.md"
    }

    /// 解析 ~/.agents/.skill-lock.json（npx skills 安装器写入，v3 schema）
    func loadLock() -> [String: LockEntry] {
        let url = env.storeRoot.appendingPathComponent(".skill-lock.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let skills = root["skills"] as? [String: [String: Any]] else { return [:] }
        var out: [String: LockEntry] = [:]
        for (name, v) in skills {
            guard let source = v["source"] as? String else { continue }
            out[name] = LockEntry(source: source,
                                  sourceUrl: v["sourceUrl"] as? String,
                                  skillPath: v["skillPath"] as? String)
        }
        return out
    }

    /// 目录自带 .git（独立 clone 的 skill）→ origin remote
    func gitRemote(_ dir: URL) -> String? {
        guard fm.fileExists(atPath: dir.appendingPathComponent(".git").path) else { return nil }
        let r = run("/usr/bin/git", ["-C", dir.path, "remote", "get-url", "origin"])
        let url = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 && !url.isEmpty ? url : nil
    }

    /// frontmatter 里的 homepage（含嵌套的 metadata.openclaw.homepage），正则兜底
    func frontmatterHomepage(_ dir: URL) -> String? {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("SKILL.md"), encoding: .utf8),
              text.hasPrefix("---"),
              let endRange = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else { return nil }
        let front = text[..<endRange.lowerBound]
        guard let match = front.range(of: #"homepage:\s*(\S+)"#, options: .regularExpression) else { return nil }
        let line = String(front[match])
        return line.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// 统一成 "github.com/owner/repo" 形态（小写，去协议/.git/锚点），本地路径原样返回
    static func normalizeSource(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("~") || s.hasPrefix("/") { return s }
        for p in ["https://", "http://", "git@"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        s = s.replacingOccurrences(of: "github.com:", with: "github.com/")
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        if s.hasSuffix(".git") { s.removeLast(4) }
        if !s.contains(".") && s.split(separator: "/").count == 2 { s = "github.com/" + s }   // "owner/repo" 简写
        return s.lowercased()
    }

    private func provenance(name: String, dir: URL, type: CapType, meta: StoreMeta,
                            lock: [String: LockEntry]) -> (source: String?, subdir: String?) {
        if let s = meta.entries[name]?.sourceUrl { return (StoreFS.normalizeSource(s), nil) }
        if let l = lock[name] {
            let src = StoreFS.normalizeSource(l.sourceUrl ?? l.source)
            let subdir = l.skillPath.map { ($0 as NSString).deletingLastPathComponent }
            return (src, (subdir?.isEmpty ?? true) ? nil : subdir)
        }
        if let remote = gitRemote(dir) { return (StoreFS.normalizeSource(remote), nil) }
        if type != .cli, let home = frontmatterHomepage(dir), home.contains("/") {
            return (StoreFS.normalizeSource(home), nil)
        }
        return (nil, nil)
    }

    /// 源式套装（v2.1）：同一上游仓库的 ≥2 个平铺成员归拢成一张套装卡。
    /// 磁盘不动、symlink 逐成员——套装只是源的视图。
    private func groupBySource(_ entries: [Entry], meta: StoreMeta) -> [Entry] {
        var bySource: [String: [Int]] = [:]
        for (i, e) in entries.enumerated() {
            guard !e.isBundle, let src = e.sourceUrl,
                  SourceKind.of(src) == .github,
                  !isSymlink(e.cap.dirURL) else { continue }   // 本地开发软链不归拢
            bySource[src, default: []].append(i)
        }
        var groups = bySource.filter { $0.value.count >= 2 }
        guard !groups.isEmpty else { return entries }

        // 前缀族收编：无来源的散件（如 baoyu-diagram 既不在 lock、frontmatter 又没 homepage），
        // 若名称前缀与某个大套装的成员族一致（≥5 个成员共享 "<prefix>-"），并入该套装。
        // repoSubdir 按 monorepo 约定猜 skills/<name>，更新检查时 stagedMemberDir 会再核实。
        for (src, idxs) in groups {
            let memberNames = idxs.map { entries[$0].name }
            guard memberNames.count >= 5,
                  let prefix = memberNames.first?.split(separator: "-").first.map(String.init),
                  prefix.count >= 3,
                  memberNames.filter({ $0.hasPrefix("\(prefix)-") }).count * 10 >= memberNames.count * 8
            else { continue }
            for (i, e) in entries.enumerated()
            where !e.isBundle && e.sourceUrl == nil && e.name.hasPrefix("\(prefix)-")
                && !isSymlink(e.cap.dirURL) && !idxs.contains(i) {
                groups[src]?.append(i)
            }
        }

        var grouped: Set<Int> = []
        var bundleAt: [Int: Entry] = [:]
        for (src, idxs) in groups {
            let members = idxs.sorted().map { i -> Capability in
                var c = entries[i].cap
                if c.repoSubdir == nil && entries[i].sourceUrl == nil {
                    c.repoSubdir = "skills/\(c.name)"   // 收编成员：按 monorepo 约定猜
                }
                return c
            }
            let repoName = src.split(separator: "/").dropFirst().joined(separator: "/")   // owner/repo
            var head = Capability(
                id: "src:\(src)", name: repoName, type: .bundle,
                desc: "同源套装 · \(members.count) 项", version: nil, author: nil,
                tokens: members.reduce(0) { $0 + $1.tokens },
                dirURL: members[0].dirURL.deletingLastPathComponent()
            )
            head.links = [:]
            let m = meta.entries[repoName]
            bundleAt[idxs[0]] = Entry(id: "src:\(src)", cap: head, children: members,
                                      bundleKind: .source, sourceUrl: src,
                                      latest: m?.latest, autoUpdate: m?.autoUpdate ?? false)
            idxs.forEach { grouped.insert($0) }
        }
        var out: [Entry] = []
        for (i, e) in entries.enumerated() {
            if let bundle = bundleAt[i] { out.append(bundle) }
            else if !grouped.contains(i) { out.append(e) }
        }
        return out
    }

    private func hasManifest(_ dir: URL) -> Bool {
        fm.fileExists(atPath: dir.appendingPathComponent("SKILL.md").path)
    }

    /// 无 SKILL.md 但存在带 SKILL.md 的子目录 ⇒ 套装
    private func isBundleDir(_ dir: URL) -> Bool {
        guard let subs = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
        return subs.contains { hasManifest(dir.appendingPathComponent($0)) }
    }

    private func makeStandalone(name: String, type: CapType, dir: URL, tools: [Tool],
                                meta: StoreMeta, lock: [String: LockEntry]) -> Entry {
        var cap = makeCap(name: name, type: type, dir: dir)
        let (source, subdir) = provenance(name: name, dir: dir, type: type, meta: meta, lock: lock)
        cap.repoSubdir = subdir
        for t in tools {
            let (st, cause) = linkStatus(linkPath: toolLinkPath(t, kind: type, name: name), expectedTarget: dir)
            cap.links[t.id] = st
            if let cause { cap.brokenCause[t.id] = cause }
        }
        let m = meta.entries[name]
        return Entry(id: name, cap: cap, children: nil,
                     sourceUrl: source, latest: m?.latest, autoUpdate: m?.autoUpdate ?? false)
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
        let source = m?.sourceUrl.map(StoreFS.normalizeSource) ?? gitRemote(dir).map(StoreFS.normalizeSource)
        return Entry(id: name, cap: head, children: children, bundleKind: .directory,
                     sourceUrl: source, latest: m?.latest, autoUpdate: m?.autoUpdate ?? false)
    }

    private func makeCap(name: String, type: CapType, dir: URL, id: String? = nil) -> Capability {
        let front = frontmatter(dir.appendingPathComponent("SKILL.md"))
        let curated = Catalog.entry(name)
        let display = inferType(name: name, front: front, scanned: type, curated: curated)
        return Capability(
            id: id ?? name,
            name: name,
            type: display,
            linkKind: type,
            desc: curated?.desc ?? front["description"] ?? "",
            version: front["version"],
            author: front["author"],
            tokens: type == .cli ? 0 : estimateTokens(dir),
            dirURL: dir,
            readme: extractReadme(dir, type: type)
        )
    }

    /// 展示类型推断：frontmatter 显式 `type:` > 内置目录提示 > 名称特征。
    /// 只影响 tag/过滤；链接布局永远走 layoutKind（实际 kind 目录）。
    func inferType(name: String, front: [String: String], scanned: CapType, curated: CatalogEntry? = nil) -> CapType {
        guard scanned == .skill else { return scanned }   // agents/mcp/bin 目录已是强信号
        if let t = front["type"]?.lowercased() {
            switch t {
            case "cli": return .cli
            case "mcp": return .mcp
            case "agent": return .agent
            default: break
            }
        }
        if let t = curated?.type { return t }
        let n = name.lowercased()
        if n.hasSuffix("-cli") || n.hasSuffix("cli") { return .cli }
        if n.hasSuffix("-mcp") || n.hasPrefix("mcp-") { return .mcp }
        return .skill
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
        // 套装：找带 SKILL.md 的子目录；直接子目录没有就按 monorepo 约定看 skills/
        var base = dir
        var subs = ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []).sorted()
            .filter { !$0.hasPrefix(".") && hasManifest(base.appendingPathComponent($0)) }
        if subs.isEmpty {
            let skillsDir = dir.appendingPathComponent("skills")
            if fm.fileExists(atPath: skillsDir.path) {
                base = skillsDir
                subs = ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []).sorted()
                    .filter { !$0.hasPrefix(".") && hasManifest(base.appendingPathComponent($0)) }
            }
        }
        guard !subs.isEmpty else {
            throw StoreError.resolveFailed("未找到 SKILL.md — 该源不是 skill 也不是套装")
        }
        let items = subs.map { sub -> PlanItem in
            let d = base.appendingPathComponent(sub)
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
        // 源式套装 = 平铺成员的集合，逐成员按独立条目移除
        if entry.bundleKind == .source {
            var meta = loadMeta()
            for cap in entry.children ?? [] {
                for t in tools {
                    let link = toolLinkPath(t, kind: cap.layoutKind, name: cap.name)
                    if isSymlink(link) { try removeLink(at: link) }
                }
                try moveToTrash(cap.dirURL)
                meta.entries.removeValue(forKey: cap.name)
            }
            meta.entries.removeValue(forKey: entry.name)
            saveMeta(meta)
            return
        }
        for t in tools {
            let link = toolLinkPath(t, kind: entry.cap.layoutKind, name: entry.name)
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
        let latest: String          // 单成员 = 上游版本号/"新版"；源式套装 = "N 项"
        let changedMembers: [String]
        let upstreamNew: [String]   // 上游有、本地没装的技能（monorepo 月度痛点）
    }

    /// 上游仓库内定位某个成员的目录：lock 的 skillPath 优先，
    /// 其次仓库根（单 skill 仓）、skills/<name>（monorepo 约定）、<name>。
    private func stagedMemberDir(staging: URL, cap: Capability) -> URL? {
        if cap.type == .bundle { return staging }   // 目录形套装 = 整仓比对
        if let sub = cap.repoSubdir {
            let d = staging.appendingPathComponent(sub)
            if fm.fileExists(atPath: d.path) { return d }
        }
        if hasManifest(staging) { return staging }
        for candidate in ["skills/\(cap.name)", cap.name] {
            let d = staging.appendingPathComponent(candidate)
            if fm.fileExists(atPath: d.path) { return d }
        }
        return nil
    }

    /// 比对一个源：clone/读取一次上游，逐成员比内容哈希。
    /// 返回 nil = 全部最新。本地开发软链成员自动跳过。
    func checkUpdate(_ entry: Entry) throws -> UpdateCheck? {
        guard let url = entry.sourceUrl, SourceKind.of(url) != .npm else { return nil }
        let resolved = try resolve(url)
        defer { if resolved.kind == .github { try? fm.removeItem(at: resolved.stagingDir) } }

        let members = entry.isBundle && entry.bundleKind == .source ? (entry.children ?? []) : [entry.cap]
        var changed: [String] = []
        var changedVersion: String?
        for cap in members where !isSymlink(cap.dirURL) {
            guard let staged = stagedMemberDir(staging: resolved.stagingDir, cap: cap) else { continue }
            if computeDirHash(cap.dirURL) != computeDirHash(staged) {
                changed.append(cap.name)
                changedVersion = frontmatter(staged.appendingPathComponent("SKILL.md"))["version"]
            }
        }
        let upstreamNew = upstreamOnlySkills(staging: resolved.stagingDir, knownNames: Set(members.map(\.name)))
        guard !changed.isEmpty else { return nil }
        let latest: String
        if changed.count == 1 && members.count == 1 {
            latest = (changedVersion != nil && changedVersion != members[0].version) ? changedVersion! : "新版"
        } else {
            latest = "\(changed.count) 项"
        }
        return UpdateCheck(entryId: entry.id, latest: latest, changedMembers: changed, upstreamNew: upstreamNew)
    }

    /// 上游 skills/ 下有 SKILL.md、但本地没装的目录名
    private func upstreamOnlySkills(staging: URL, knownNames: Set<String>) -> [String] {
        let skillsDir = staging.appendingPathComponent("skills")
        let base = fm.fileExists(atPath: skillsDir.path) ? skillsDir : staging
        return ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []).sorted()
            .filter { !$0.hasPrefix(".") && !knownNames.contains($0) && hasManifest(base.appendingPathComponent($0)) }
    }

    /// 执行更新：clone 一次，只换有变化的成员；每个被换的成员先备份进回收站。
    /// symlink 路径不变自动延续。返回 (更新了哪些, 上游新增未装)。
    @discardableResult
    func applyUpdate(_ entry: Entry) throws -> (updated: [String], upstreamNew: [String]) {
        guard let url = entry.sourceUrl else { throw StoreError.resolveFailed("该源没有记录 URL，无法更新") }
        let resolved = try resolve(url)
        defer { if resolved.kind == .github { try? fm.removeItem(at: resolved.stagingDir) } }

        let members = entry.isBundle && entry.bundleKind == .source ? (entry.children ?? []) : [entry.cap]
        var updated: [String] = []
        for cap in members where !isSymlink(cap.dirURL) {
            guard let staged = stagedMemberDir(staging: resolved.stagingDir, cap: cap),
                  computeDirHash(cap.dirURL) != computeDirHash(staged) else { continue }
            try moveToTrash(cap.dirURL)
            try fm.copyItem(at: staged, to: cap.dirURL)
            updated.append(cap.name)
        }
        let upstreamNew = upstreamOnlySkills(staging: resolved.stagingDir, knownNames: Set(members.map(\.name)))
        saveLatest(entry.name, latest: nil)
        return (updated, upstreamNew)
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
