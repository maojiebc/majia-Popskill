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
        let pe = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let store = pe["POPSKILL_STORE_ROOT"]
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
            ?? home.appendingPathComponent(".agents")
        // 沙盘钩子：POPSKILL_TOOLS_ROOT=<base> → <base>/.claude、<base>/.codex（新用户旅程测试用）
        let toolBase = pe["POPSKILL_TOOLS_ROOT"]
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? home
        return StoreEnv(storeRoot: store, toolRoots: [
            "claude": toolBase.appendingPathComponent(".claude"),
            "codex": toolBase.appendingPathComponent(".codex"),
        ])
    }
}

/// ~/.agents/.popskill.json — 随 store 同步的应用元数据（源 URL / 自动更新 / 工具默认挂载）
struct StoreMeta: Codable {
    struct EntryMeta: Codable {
        var sourceUrl: String?
        var autoUpdate: Bool?
        var latest: String?
        var changed: [String]?   // 上次检查发现有变化的成员名（套装提醒到具体哪个）
        var lastHead: String?    // 上次完整比对时的上游 HEAD sha（ls-remote 短路用，v2.8）
        var localDigest: String? // 上次完整比对时本地成员的组合哈希——短路必须同时验证本地未漂移
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

    /// meta 的读-改-写必须走这里：checkUpdate 在 4 路并发的后台任务里写 meta，
    /// 与主线程设置页的写互相覆盖会静默丢更新（.atomic 只保证不撕裂，不保证不丢）。
    private static let metaLock = NSLock()
    func mutateMeta(_ body: (inout StoreMeta) -> Void) {
        StoreFS.metaLock.lock()
        defer { StoreFS.metaLock.unlock() }
        var meta = loadMeta()
        body(&meta)
        saveMeta(meta)
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
        entries = groupBySource(entries, meta: meta)
        entries += scanMarketplacePlugins(tools: tools)
        return sortEntries(entries)
    }

    // ── Marketplace 插件只读层（v2.6）─────────────────────
    // dbs 这类二十件套活在 ~/.claude/plugins/cache（Claude Code 自管），
    // 不在任何 skills 目录——必须单独扫，但只看不动。

    func scanMarketplacePlugins(tools: [Tool]) -> [Entry] {
        guard let claudeRoot = env.toolRoots["claude"] else { return [] }
        let pluginsDir = claudeRoot.appendingPathComponent("plugins")
        guard let data = try? Data(contentsOf: pluginsDir.appendingPathComponent("installed_plugins.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = root["plugins"] as? [String: [[String: Any]]] else { return [] }

        // marketplace 名 → github repo（known_marketplaces.json）
        var repos: [String: String] = [:]
        if let kd = try? Data(contentsOf: pluginsDir.appendingPathComponent("known_marketplaces.json")),
           let known = try? JSONSerialization.jsonObject(with: kd) as? [String: [String: Any]] {
            for (mk, v) in known {
                if let src = v["source"] as? [String: Any], let repo = src["repo"] as? String {
                    repos[mk] = StoreFS.normalizeSource(repo)
                }
            }
        }

        var out: [Entry] = []
        for (key, installs) in plugins.sorted(by: { $0.key < $1.key }) {
            guard let install = installs.first,
                  let pathStr = install["installPath"] as? String else { continue }
            let parts = key.split(separator: "@", maxSplits: 1).map(String.init)
            let pluginName = parts.first ?? key
            let marketplace = parts.count > 1 ? parts[1] : ""
            let installPath = URL(fileURLWithPath: pathStr)
            let skillsBase = fm.fileExists(atPath: installPath.appendingPathComponent("skills").path)
                ? installPath.appendingPathComponent("skills") : installPath

            var children: [Capability] = []
            for sub in ((try? fm.contentsOfDirectory(atPath: skillsBase.path)) ?? []).sorted()
            where !sub.hasPrefix(".") && hasManifest(skillsBase.appendingPathComponent(sub)) {
                var c = makeCap(name: sub, type: .skill,
                                dir: skillsBase.appendingPathComponent(sub),
                                id: "plugin:\(key)/\(sub)")
                for t in tools {
                    // 展示性状态：插件由 Claude Code 加载（claude=on），Codex 不消费（off）
                    c.links[t.id] = t.id == "claude" ? .on : .off
                }
                children.append(c)
            }
            guard !children.isEmpty else { continue }

            var head = Capability(
                id: "plugin:\(key)", name: pluginName, type: .bundle,
                desc: "Marketplace 插件（\(marketplace)）· 由 Claude Code 管理，操作用 /plugin",
                version: install["version"] as? String, author: nil,
                tokens: children.reduce(0) { $0 + $1.tokens },
                dirURL: installPath
            )
            head.links = [:]
            out.append(Entry(id: "plugin:\(key)", cap: head, children: children,
                             bundleKind: .marketplace, sourceUrl: repos[marketplace]))
        }
        return out
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

    /// 统一成 "github.com/owner/repo" 形态（小写，去协议/.git/锚点/查询串，
    /// **仓库内深路径截到 owner/repo**——/tree/main/skills/x 这类逐 skill 不同的
    /// homepage 必须收敛到同一个分组键，否则同仓技能归拢不了（v2.4.2 异机实测教训）。
    /// npm:/本地路径原样返回。
    static func normalizeSource(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("~") || s.hasPrefix("/") { return s }
        if s.lowercased().hasPrefix("npm:") { return s.lowercased() }
        for p in ["https://", "http://", "git@", "ssh://git@"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        s = s.replacingOccurrences(of: "github.com:", with: "github.com/")
        for cut in ["#", "?"] {
            if let i = s.firstIndex(of: Character(cut)) { s = String(s[..<i]) }
        }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        s = s.lowercased()
        var parts = s.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return s }
        if parts[0] == "raw.githubusercontent.com" { parts[0] = "github.com" }
        if !parts[0].contains(".") {
            parts.insert("github.com", at: 0)   // "owner/repo" 简写
        }
        // host + owner + repo，深路径截断
        parts = Array(parts.prefix(3))
        if parts.count == 3, parts[2].hasSuffix(".git") { parts[2].removeLast(4) }
        return parts.joined(separator: "/")
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
        // 第五级（v2.4）：精选目录的来源提示——救复制安装类的来源孤儿（如 guanskill 五件套）
        if let curated = Catalog.entry(name)?.source {
            return (StoreFS.normalizeSource(curated), nil)
        }
        return (nil, nil)
    }

    /// 源式套装（v2.1）：同一上游仓库的 ≥2 个平铺成员归拢成一张套装卡。
    /// 磁盘不动、symlink 逐成员——套装只是源的视图。
    private func groupBySource(_ entries: [Entry], meta: StoreMeta) -> [Entry] {
        var bySource: [String: [Int]] = [:]
        // 归拢只看来源是否同一远程仓——store 条目本身是 symlink 也照样归
        // （dotfiles 同步类布局整 store 都是软链；更新读写仍在 checkUpdate/applyUpdate
        //  里逐成员跳过软链，安全性不变）
        for (i, e) in entries.enumerated() {
            guard !e.isBundle, let src = e.sourceUrl,
                  SourceKind.of(src) != .local else { continue }   // 本地路径来源（私有开发）不归拢
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
                                      latest: m?.latest, changedMembers: m?.changed,
                                      autoUpdate: m?.autoUpdate ?? false)
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
                     sourceUrl: source, latest: m?.latest, changedMembers: m?.changed,
                     autoUpdate: m?.autoUpdate ?? false)
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
                     sourceUrl: source, latest: m?.latest, changedMembers: m?.changed,
                     autoUpdate: m?.autoUpdate ?? false)
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

    static let trashBuckets = ["skills", "agents", "mcp", "bin"]

    /// 真实目录移入 store 回收站（可逆），返回回收位置。
    /// 最多留 trashRetainCount（200）份，按入站时间 FIFO 轮换。
    /// 按来源的 kind 目录分桶存放（.trash/skills/ 等）——恢复时必须回到原 kind，
    /// 否则 MCP/Agent 被恢复进 skills/ 会让 layoutKind 和 symlink 路径静默错位。
    @discardableResult
    func moveToTrash(_ url: URL) throws -> URL {
        let parent = url.deletingLastPathComponent().lastPathComponent
        let bucket = StoreFS.trashBuckets.contains(parent) ? parent : CapType.skill.dirName
        let bucketURL = trashURL.appendingPathComponent(bucket)
        try fm.createDirectory(at: bucketURL, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = bucketURL.appendingPathComponent("\(url.lastPathComponent)-\(stamp)")
        try fm.moveItem(at: url, to: dest)
        pruneTrash()
        return dest
    }

    /// 全部回收站条目（分桶 + 兼容 v2.8 前的平铺历史条目，视作 skills）
    private func trashEntryURLs() -> [(url: URL, bucket: String)] {
        var out: [(URL, String)] = []
        for name in ((try? fm.contentsOfDirectory(atPath: trashURL.path)) ?? []).sorted() where !name.hasPrefix(".") {
            let url = trashURL.appendingPathComponent(name)
            if StoreFS.trashBuckets.contains(name) {
                for sub in ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() where !sub.hasPrefix(".") {
                    out.append((url.appendingPathComponent(sub), name))
                }
            } else {
                out.append((url, CapType.skill.dirName))   // 旧版平铺条目
            }
        }
        return out
    }

    static let trashRetainCount = 200

    /// 按入站时间 FIFO 轮换。排序键 = moveToTrash 写进名字的时间戳后缀——
    /// 不能用 contentModificationDate：mv/rename 不更新目录自身 mtime，
    /// 半年没改过的技能刚备份进来就会被当「最旧」误删。
    /// 上限 200：一次大套装更新会同时入站几十份，全局 20 一冲就把别人的备份清光。
    func pruneTrash(keep: Int = StoreFS.trashRetainCount) {
        let items = trashEntryURLs().map(\.url)
        guard items.count > keep else { return }
        func stampKey(_ url: URL) -> String {
            // 形如 2026-06-11T08-30-00Z（20 字符，字典序即时间序）；
            // 非本程序写入的条目退回「加入目录时间」
            let suffix = String(url.lastPathComponent.suffix(20))
            if suffix.count == 20, suffix.hasSuffix("Z"), suffix.dropFirst(4).first == "-" {
                return suffix
            }
            let date = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) ?? .distantPast
            return ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        }
        let sorted = items.sorted { stampKey($0) > stampKey($1) }
        for old in sorted.dropFirst(keep) { try? fm.removeItem(at: old) }
    }

    // ── 回收站清单 / 恢复（v2.8：UI 文案到处承诺「可恢复」，这里兑现）──

    struct TrashItem: Identifiable, Equatable {
        let id: String      // 桶/目录名（含时间戳后缀）
        let name: String    // 原能力名
        let kindDir: String // 入站时的 kind 目录（skills/agents/mcp/bin），恢复回原处
        let date: Date?     // 入站时间（解析自名称后缀）
        let url: URL
    }

    /// 回收站清单，新入站在前
    func listTrash() -> [TrashItem] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")   // 锁死：跟随系统会在佛历/12小时制下解析成 1483 年
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return trashEntryURLs().map { url, bucket in
            let n = url.lastPathComponent
            let suffix = String(n.suffix(20))
            var name = n
            var date: Date?
            // 去后缀只看形状，不依赖 date 解析成功（解析失败顶多没时间，名字必须干净）
            if suffix.count == 20, suffix.hasSuffix("Z"), suffix.dropFirst(4).first == "-" {
                name = String(n.dropLast(21))   // 去掉 "-<stamp>"
                date = f.date(from: suffix)
            }
            return TrashItem(id: "\(bucket)/\(n)", name: name, kindDir: bucket, date: date, url: url)
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// 恢复到 store 的原 kind 目录；同名已存在则拒绝（先移走现有的再恢复）
    func restoreFromTrash(_ item: TrashItem) throws {
        let name = try sanitizeName(item.name)
        let kind = StoreFS.trashBuckets.contains(item.kindDir) ? item.kindDir : CapType.skill.dirName
        let dest = env.storeRoot.appendingPathComponent(kind).appendingPathComponent(name)
        guard !fm.fileExists(atPath: dest.path) else { throw StoreError.alreadyExists(name) }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: item.url, to: dest)
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
        var headSha: String? = nil   // github 源 clone 时的 HEAD（ls-remote 短路用）
    }

    /// 解析来源：local 直接扫描；github 浅 clone 到临时目录再扫描；npm 暂不支持。
    func resolve(_ rawUrl: String) throws -> ResolvedSource {
        let url = rawUrl.trimmingCharacters(in: .whitespaces)
        let kind = SourceKind.of(url)
        switch kind {
        case .npm:
            throw StoreError.sourceUnsupported("npm 源暂不支持——请用 GitHub 仓库或本地路径")
        case .local:
            let dir = URL(fileURLWithPath: NSString(string: url).expandingTildeInPath).standardizedFileURL
            guard fm.fileExists(atPath: dir.path) else { throw StoreError.resolveFailed("路径不存在：\(url)") }
            return try resolveDir(dir, url: url, kind: .local)
        case .github:
            let (cloneURL, repoName, norm) = try StoreFS.githubTarget(url)
            let stageRoot = fm.temporaryDirectory.appendingPathComponent("popskill-stage-\(UUID().uuidString.prefix(8))")
            // clone 目标目录名 = 仓库名——它会一路成为 store 目录名和 symlink 名
            //（曾直接用随机临时目录名，装出来的条目叫 popskill-stage-xxxx）
            let tmp = stageRoot.appendingPathComponent(repoName)
            let r = run("/usr/bin/git", ["clone", "--depth", "1", cloneURL, tmp.path], timeout: 300)
            guard r.status == 0 else {
                discardStagingDir(tmp)
                throw StoreError.resolveFailed("git clone 失败：\(r.err.prefix(200))")
            }
            let sha = run("/usr/bin/git", ["-C", tmp.path, "rev-parse", "HEAD"], timeout: 30)
                .out.trimmingCharacters(in: .whitespacesAndNewlines)
            try? fm.removeItem(at: tmp.appendingPathComponent(".git"))
            do {
                var src = try resolveDir(tmp, url: norm, kind: .github)
                src.headSha = sha.isEmpty ? nil : sha
                return src
            } catch {
                discardStagingDir(tmp)   // 解析失败不能把整仓副本留在临时目录
                throw error
            }
        }
    }

    /// github 源 → (clone URL, 仓库名, 规范化源)。深路径/简写/大小写都收敛到 owner/repo。
    static func githubTarget(_ url: String) throws -> (cloneURL: String, repoName: String, norm: String) {
        let norm = normalizeSource(url)
        let parts = norm.split(separator: "/")
        guard parts.count == 3, parts[0] == "github.com" else {
            throw StoreError.resolveFailed("无法识别 GitHub 仓库：\(url)")
        }
        return ("https://\(norm).git", String(parts[2]), norm)
    }

    /// 丢弃 github 临时 staging（连同它的 popskill-stage-* 父目录）。
    /// local 源的 stagingDir 是用户原地目录，绝不能删——调用方自己 guard。
    func discardStagingDir(_ dir: URL) {
        var root = dir
        if root.deletingLastPathComponent().lastPathComponent.hasPrefix("popskill-stage-") {
            root = root.deletingLastPathComponent()
        }
        try? fm.removeItem(at: root)
    }

    func discardStaging(_ src: ResolvedSource) {
        guard src.kind == .github else { return }
        discardStagingDir(src.stagingDir)
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
        discardStaging(src)
        for t in linkTools {
            try createLink(at: toolLinkPath(t, kind: src.isBundle ? .bundle : .skill, name: src.entryName), to: dest)
        }
        mutateMeta { meta in
            meta.entries[src.entryName] = StoreMeta.EntryMeta(sourceUrl: src.url, autoUpdate: false, latest: nil)
        }
    }

    /// 移除条目：撤全部 symlink（含物化目录）→ store 副本移入回收站
    func removeEntry(_ entry: Entry, tools: [Tool]) throws {
        guard entry.bundleKind != .marketplace else {
            throw StoreError.sourceUnsupported("Marketplace 插件由 Claude Code 管理——在 Claude Code 里用 /plugin 卸载")
        }
        // 源式套装 = 平铺成员的集合，逐成员按独立条目移除
        if entry.bundleKind == .source {
            for cap in entry.children ?? [] {
                for t in tools {
                    let link = toolLinkPath(t, kind: cap.layoutKind, name: cap.name)
                    if isSymlink(link) { try removeLink(at: link) }
                }
                try moveToTrash(cap.dirURL)
            }
            mutateMeta { meta in
                for cap in entry.children ?? [] { meta.entries.removeValue(forKey: cap.name) }
                meta.entries.removeValue(forKey: entry.name)
            }
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
        mutateMeta { meta in meta.entries.removeValue(forKey: entry.name) }
    }

    // ── 更新机制（v2.1，吸收 cc-switch 的内容哈希方案）─────
    // 不依赖 semver（多数 skill 没有规范版本号）：对目录算 SHA-256
    // 内容哈希（相对路径字典序，"path\0content\0" 级联，跳过隐藏文件），
    // 拉上游后比对哈希判断「有更新」。

    /// symlink 不跟随——软链只把「指向的路径字符串」纳入哈希：
    /// 恶意/异常仓库里的软链不能把遍历带出目录（读到 store 外文件）或带进环；
    /// 深度硬上限 32 防御构造的深嵌套。
    func computeDirHash(_ dir: URL) -> String {
        enum Leaf { case file(URL), link(String) }
        var leaves: [(String, Leaf)] = []
        func walk(_ d: URL, rel: String, depth: Int) {
            guard depth < 32 else { return }
            let items = ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).sorted()
            for name in items where !name.hasPrefix(".") {
                let url = d.appendingPathComponent(name)
                let relPath = rel.isEmpty ? name : "\(rel)/\(name)"
                if let dest = try? fm.destinationOfSymbolicLink(atPath: url.path) {
                    leaves.append((relPath, .link(dest)))
                    continue
                }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue { walk(url, rel: relPath, depth: depth + 1) } else { leaves.append((relPath, .file(url))) }
            }
        }
        walk(dir, rel: "", depth: 0)
        var hasher = SHA256()
        for (rel, leaf) in leaves {
            hasher.update(data: Data(rel.utf8))
            hasher.update(data: Data([0]))
            switch leaf {
            case .file(let url): hasher.update(data: (try? Data(contentsOf: url)) ?? Data())
            case .link(let dest): hasher.update(data: Data(dest.utf8))
            }
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

    /// 上游 HEAD 一次网络往返（github 源专用，失败返回 nil 走完整比对）
    func remoteHead(_ url: String) -> String? {
        guard let target = try? StoreFS.githubTarget(url) else { return nil }
        let r = run("/usr/bin/git", ["ls-remote", target.cloneURL, "HEAD"], timeout: 30)
        guard r.status == 0,
              let sha = r.out.split(separator: "\t").first?.trimmingCharacters(in: .whitespacesAndNewlines),
              sha.count >= 7 else { return nil }
        return sha
    }

    /// 完整比对后的检查点：上游 HEAD + 本地组合哈希一起落盘
    func saveCheckpoint(_ entryName: String, head: String, localDigest: String) {
        mutateMeta { meta in
            var m = meta.entries[entryName] ?? StoreMeta.EntryMeta()
            m.lastHead = head
            m.localDigest = localDigest
            meta.entries[entryName] = m
        }
    }

    /// 本地成员目录的组合哈希——纯磁盘 IO，毫秒级。
    /// HEAD 短路必须同时验证它：否则用户在终端改坏 store 里的技能后，
    /// 上游 commit 没动就永远检不出本地漂移（审查发现，v2.8 短路的配套约束）。
    func localDigest(_ entry: Entry) -> String {
        let members = entry.isBundle && entry.bundleKind == .source ? (entry.children ?? []) : [entry.cap]
        var hasher = SHA256()
        for cap in members.sorted(by: { $0.name < $1.name }) where !isSymlink(cap.dirURL) {
            hasher.update(data: Data(cap.name.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(computeDirHash(cap.dirURL).utf8))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 比对一个源：clone/读取一次上游，逐成员比内容哈希。
    /// 返回 nil = 全部最新。本地开发软链成员自动跳过。
    func checkUpdate(_ entry: Entry) throws -> UpdateCheck? {
        guard entry.bundleKind != .marketplace else { return nil }   // 插件更新归 /plugin
        guard let url = entry.sourceUrl, SourceKind.of(url) != .npm else { return nil }
        // HEAD 短路（v2.8 性能）：上游 commit 没动 且 本地未漂移 才跳过整仓 clone——
        // 一次 ls-remote 替代几十 MB 下载，13 个源的启动检查从分钟级降到秒级。
        // 本地不变性必须一起验（localDigest，纯磁盘 IO）：目标用户天天在终端动
        // ~/.agents，只比 HEAD 会让本地改坏的技能永远检不出来。
        // 亮着更新徽标（latest 非 nil）的也不短路：短路会把上次的「新版」结论钉死，
        // 走完整比对才能重新解析出上游版本号、或在上游回退后熄灭徽标。
        // ls-remote 失败（断网等）不吞：落到下面的完整 resolve，让错误如实抛出
        if SourceKind.of(url) == .github,
           let m = loadMeta().entries[entry.name],
           m.latest == nil,
           let last = m.lastHead, !last.isEmpty,
           m.localDigest == localDigest(entry),
           let head = remoteHead(url), head == last {
            return nil
        }
        let resolved = try resolve(url)
        defer { discardStaging(resolved) }

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
        if let sha = resolved.headSha { saveCheckpoint(entry.name, head: sha, localDigest: localDigest(entry)) }
        guard !changed.isEmpty else {
            // 完整比对确认与上游一致（如用户在终端手动同步过）：熄灭残留的更新徽标。
            // 只有这条路径能清——HEAD 短路的 nil 是「没变化」不是「已一致」
            if loadMeta().entries[entry.name]?.latest != nil { saveLatest(entry.name, latest: nil) }
            return nil
        }
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
        defer { discardStaging(resolved) }

        let members = entry.isBundle && entry.bundleKind == .source ? (entry.children ?? []) : [entry.cap]
        var updated: [String] = []
        for cap in members where !isSymlink(cap.dirURL) {
            guard let staged = stagedMemberDir(staging: resolved.stagingDir, cap: cap),
                  computeDirHash(cap.dirURL) != computeDirHash(staged) else { continue }
            // 原子换版：先把新版拷到隐藏临时名——copy 失败（磁盘满/源不可读）时旧版原样无损。
            // 曾经是先弃旧版再 copy，失败即丢数据且 symlink 全断。
            let incoming = cap.dirURL.deletingLastPathComponent()
                .appendingPathComponent(".popskill-incoming-\(cap.name)")
            try? fm.removeItem(at: incoming)
            do { try fm.copyItem(at: staged, to: incoming) }
            catch { try? fm.removeItem(at: incoming); throw error }
            let backup = try moveToTrash(cap.dirURL)
            do { try fm.moveItem(at: incoming, to: cap.dirURL) }
            catch {
                try? fm.moveItem(at: backup, to: cap.dirURL)   // 换名失败回滚
                throw error
            }
            updated.append(cap.name)
        }
        let upstreamNew = upstreamOnlySkills(staging: resolved.stagingDir, knownNames: Set(members.map(\.name)))
        // 落盘后再算 digest——此刻本地已是新版内容
        if let sha = resolved.headSha { saveCheckpoint(entry.name, head: sha, localDigest: localDigest(entry)) }
        saveLatest(entry.name, latest: nil)
        return (updated, upstreamNew)
    }

    func saveLatest(_ entryName: String, latest: String?, changed: [String]? = nil) {
        mutateMeta { meta in
            var m = meta.entries[entryName] ?? StoreMeta.EntryMeta()
            m.latest = latest
            m.changed = latest == nil ? nil : changed
            meta.entries[entryName] = m
        }
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

    /// SKILL.md YAML frontmatter 的扁平 key: value（支持 | / > 多行块标量，取首段文本）。
    /// Agent Skills 标准把 version/author/homepage 嵌在 `metadata:` 下——其**直接子级**
    /// 一并收入（顶层同名优先，更深层如 openclaw: 不收），嵌套写法的版本号才不会丢。
    func frontmatter(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              text.hasPrefix("---") else { return [:] }
        var out: [String: String] = [:]
        let lines = Array(text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst())
        var i = 0
        var metaIndent: Int?   // 非 nil = 在 metadata: 块内；0 = 等首个子行定缩进宽度
        while i < lines.count {
            let line = lines[i]
            i += 1
            if line.hasPrefix("---") { break }
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                guard metaIndent != nil, !line.hasPrefix("\t"),
                      let colon = line.firstIndex(of: ":") else { continue }
                let indent = line.prefix(while: { $0 == " " }).count
                if metaIndent == 0 { metaIndent = indent }
                guard indent == metaIndent else { continue }   // 更深层（openclaw: 等）不收
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                var val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if val.hasPrefix("\"") && val.hasSuffix("\"") && val.count >= 2 { val = String(val.dropFirst().dropLast()) }
                if !key.isEmpty && !val.isEmpty && out[key] == nil { out[key] = val }
                continue
            }
            metaIndent = nil
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if key == "metadata" && val.isEmpty { metaIndent = 0; continue }
            if ["|", "|-", ">", ">-"].contains(val) {
                // 块标量：收集后续缩进行，拼成一段（够展示用即可）
                var parts: [String] = []
                while i < lines.count, lines[i].hasPrefix(" ") || lines[i].isEmpty {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { parts.append(t) } else if !parts.isEmpty { break }
                    i += 1
                }
                val = parts.joined(separator: " ")
            }
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
    func run(_ bin: String, _ args: [String], timeout: TimeInterval = 120) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return (-1, "", "\(error)") }
        // 两路管道必须并发排空——顺序 readDataToEndOfFile 会在 stderr 写满 64KB 缓冲时与子进程互相卡死
        var outData = Data(), errData = Data()
        let drained = DispatchGroup()
        DispatchQueue.global().async(group: drained) { outData = outPipe.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global().async(group: drained) { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }
        // watchdog：git 遇到网络黑洞可以永远不退出，不能让调用线程跟着无限期挂住
        let timedOut = drained.wait(timeout: .now() + timeout) == .timedOut
        let cmd = URL(fileURLWithPath: bin).lastPathComponent
        if timedOut {
            p.terminate()   // Foundation 按进程组发 TERM
            if drained.wait(timeout: .now() + 5) == .timedOut {
                // 组 KILL（不看 p.isRunning：TERM 可能已杀掉 git 本体，
                // 但孙进程——hook/credential helper——还握着管道写端）
                kill(-p.processIdentifier, SIGKILL)
                if drained.wait(timeout: .now() + 5) == .timedOut {
                    // 病理场景（D 态进程钉死管道）：放弃读取立即返回——
                    // outData/errData 可能仍被后台读线程写入，此后不许再碰
                    return (-1, "", "命令超时且输出管道无法排空，已放弃：\(cmd)")
                }
            }
        }
        p.waitUntilExit()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        if timedOut {
            return (-1, out, "命令超时（\(Int(timeout))s）已终止：\(cmd) \(args.first ?? "")")
        }
        return (p.terminationStatus, out, err)
    }
}
