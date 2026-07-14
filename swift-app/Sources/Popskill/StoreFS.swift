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
        var upstreamNew: [String]? // 上游有、本地没装（v2.17：进 Entry + 可一键装）
        var lastHead: String?    // 上次完整比对时的上游 HEAD sha（ls-remote 短路用，v2.8）
        var localDigest: String? // 上次完整比对时本地成员的组合哈希——短路必须同时验证本地未漂移
        // 「跳过此版本」（v2.15，吸收 cc-switch dismissedVersion）：
        var latestFingerprint: String? // latest 对应的上游状态指纹（github=HEAD sha / npm=版本号 / wk=内容组合哈希）
        var skipped: String?           // 用户跳过的上游状态指纹；checkUpdate 命中它就不亮徽标，新状态自动清
    }
    struct ToolMeta: Codable {
        var defaultTarget: Bool?
    }
    var entries: [String: EntryMeta] = [:]
    var tools: [String: ToolMeta] = [:]
    // 定时任务人话备注（label → 备注，v2.10）。Optional：旧 meta JSON 没有此 key，
    // 非 Optional 默认值不参与 Codable 合成解码，会让整个 loadMeta 抛错
    var schedNotes: [String: String]?
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
        case .alreadyExists(let n): L("store 中已存在 \(n)")
        case .notASymlink(let p): L("\(abbrev(p)) 不是 popskill 管理的 symlink，已跳过")
        case .sourceUnsupported(let m): m
        case .resolveFailed(let m): m
        case .unsafeName(let n): L("不安全的目录名：\(n)")
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

// @unchecked 只为 fm：FileManager.default 按 Apple 文档是线程安全的共享单例，
// 其余存储属性（env）全是值类型。StoreFS 本身无可变状态——meta 互斥走 metaLock。
struct StoreFS: @unchecked Sendable {
    let env: StoreEnv
    let fm = FileManager.default

    var metaURL: URL { env.storeRoot.appendingPathComponent(".popskill.json") }
    var trashURL: URL { env.storeRoot.appendingPathComponent(".trash") }

    // ── 元数据 ────────────────────────────────────────────

    func loadMeta() -> StoreMeta {
        guard let data = try? Data(contentsOf: metaURL) else { return StoreMeta() }   // 不存在 = 正常新库
        guard let meta = try? JSONDecoder().decode(StoreMeta.self, from: data) else {
            // 损坏（store 走 git 同步撞出冲突标记等）绝不能静默归零——下一次 mutateMeta
            // 就会拿空表覆写落盘，全部来源/自动更新/跳过记录无提示蒸发（v2.16 审计 #2）。
            // 先备份第一现场（已有备份不覆盖），UI 侧 refresh 发现备份会告警一次
            let backup = metaURL.appendingPathExtension("corrupt")
            if !fm.fileExists(atPath: backup.path) {
                try? fm.copyItem(at: metaURL, to: backup)
                plog.error("meta 损坏无法解码，已备份到 .popskill.json.corrupt")
            }
            return StoreMeta()
        }
        return meta
    }

    /// meta 曾损坏的现场证据是否存在（refresh 借此告警一次）
    var metaCorruptBackupExists: Bool {
        fm.fileExists(atPath: metaURL.appendingPathExtension("corrupt").path)
    }

    /// meta 孤儿清理（v2.16 审计 #1）：终端删掉的条目、历史写错键（如 "src:*"）的残留。
    /// 孤儿最坏能让重装的同名技能继承前世 sourceUrl+autoUpdate，被旧仓库内容静默覆写。
    /// 只在真有孤儿时写盘——refresh 高频跑，不空转 IO。
    func gcMeta(keep: Set<String>) {
        let stale = loadMeta().entries.keys.filter { !keep.contains($0) }
        guard !stale.isEmpty else { return }
        mutateMeta { meta in
            for k in stale { meta.entries.removeValue(forKey: k) }
        }
        plog.info("meta GC：清理 \(stale.count) 个孤儿键")
    }

    /// v2.18 一次性迁移：meta.entries 键从裸名迁到类型化 id。
    /// 旧键按磁盘 kind 目录定位（skills/agents/mcp/bin 顶层同名即归它）；
    /// 磁盘不在的按形态猜套装头键（含 "/" = github 源式套装 repoName，
    /// 含 "." = well-known 域名头键）；都不中的孤儿留给 gcMeta 照常清理。
    /// 幂等：新格式键（含 ":"）永不再动；无旧键时零写盘。
    func migrateMetaKeys() {
        guard loadMeta().entries.keys.contains(where: { !$0.contains(":") }) else { return }
        var migrated = 0
        mutateMeta { meta in
            for key in meta.entries.keys.filter({ !$0.contains(":") }) {
                guard let val = meta.entries[key] else { continue }
                var newKey: String?
                for kind in [CapType.skill, .agent, .mcp, .cli]
                where fm.fileExists(atPath: env.storeRoot.appendingPathComponent(kind.dirName)
                    .appendingPathComponent(key).path) {
                    newKey = typedId(kind, key)   // 目录套装也居 skills/，同样命中 skill: 前缀
                    break
                }
                if newKey == nil, key.contains("/") { newKey = "src:github.com/\(key)" }
                else if newKey == nil, key.contains(".") { newKey = "src:wk:\(key)" }
                guard let nk = newKey else { continue }
                if meta.entries[nk] == nil { meta.entries[nk] = val }
                meta.entries.removeValue(forKey: key)
                migrated += 1
            }
        }
        if migrated > 0 { plog.info("meta 键迁移到类型化 id：\(migrated) 个") }
    }

    /// 写盘结果如实返回（v2.18）：磁盘满/权限变化时 UI 曾照样提示「已保存」，
    /// 设置实际没落盘。false = 写失败（已留 plog 证据），调用方对用户可见的
    /// 设置动作必须回滚内存态并报错。
    @discardableResult
    func saveMeta(_ meta: StoreMeta) -> Bool {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(meta).write(to: metaURL, options: .atomic)
            return true
        } catch {
            plog.error("meta 写盘失败：\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// meta 的读-改-写必须走这里：checkUpdate 在 4 路并发的后台任务里写 meta，
    /// 与主线程设置页的写互相覆盖会静默丢更新（.atomic 只保证不撕裂，不保证不丢）。
    private static let metaLock = NSLock()
    @discardableResult
    func mutateMeta(_ body: (inout StoreMeta) -> Void) -> Bool {
        StoreFS.metaLock.lock()
        defer { StoreFS.metaLock.unlock() }
        var meta = loadMeta()
        body(&meta)
        return saveMeta(meta)
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
                desc: L("Marketplace 插件（\(marketplace)）· 由 Claude Code 管理，操作用 /plugin"),
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
        // well-known 源（v2.14）：归拢键 = 域名——skills.sh 从 open.feishu.cn 装的 24 个
        // lark 技能同键归一张卡。曾被下面的 prefix(3) 截成 ".well-known/skills" 当 github 源
        if let host = wellKnownHost(s) { return "wk:\(host)" }
        if s.lowercased().hasPrefix("wk:") { return s.lowercased() }
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
        // meta 键 = 类型化 id（v2.18）；lock/curated 是外部生态文件，键保持裸名
        if let s = meta.entries[typedId(type, name)]?.sourceUrl { return (StoreFS.normalizeSource(s), nil) }
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
            // 套装显示名：github = owner/repo；well-known = 裸域名（"wk:open.feishu.cn" → "open.feishu.cn"）
            let repoName = src.hasPrefix("wk:")
                ? String(src.dropFirst(3))
                : src.split(separator: "/").dropFirst().joined(separator: "/")
            var head = Capability(
                id: "src:\(src)", name: repoName, type: .bundle,
                desc: L("同源套装 · \(members.count) 项"), version: nil, author: nil,
                tokens: members.reduce(0) { $0 + $1.tokens },
                dirURL: members[0].dirURL.deletingLastPathComponent()
            )
            head.links = [:]
            // 源式套装 meta 键 = entry.id（"src:<归拢键>"）。v2.16 曾因写 id 读 repoName
            // 键歧义让自动更新从未生效——v2.18 起读写统一走 id，歧义根除
            let m = meta.entries["src:\(src)"]
            bundleAt[idxs[0]] = Entry(id: "src:\(src)", cap: head, children: members,
                                      bundleKind: .source, sourceUrl: src,
                                      latest: m?.latest, changedMembers: m?.changed,
                                      upstreamNew: m?.upstreamNew,
                                      autoUpdate: m?.autoUpdate ?? false,
                                      skippedUpdate: m?.skipped != nil)
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
        let id = typedId(type, name)   // type 此处 = 磁盘扫描 kind，skills/x 与 agents/x 各有身份
        var cap = makeCap(name: name, type: type, dir: dir, id: id)
        let (source, subdir) = provenance(name: name, dir: dir, type: type, meta: meta, lock: lock)
        cap.repoSubdir = subdir
        for t in tools {
            let (st, cause) = linkStatus(linkPath: toolLinkPath(t, kind: type, name: name), expectedTarget: dir)
            cap.links[t.id] = st
            if let cause { cap.brokenCause[t.id] = cause }
        }
        let m = meta.entries[id]
        return Entry(id: id, cap: cap, children: nil,
                     sourceUrl: source, latest: m?.latest, changedMembers: m?.changed,
                     upstreamNew: m?.upstreamNew,
                     autoUpdate: m?.autoUpdate ?? false, skippedUpdate: m?.skipped != nil)
    }

    private func makeBundle(name: String, dir: URL, tools: [Tool], meta: StoreMeta) -> Entry {
        let id = typedId(.bundle, name)   // 目录套装居 skills/，与同名 skill 目录互斥，共用 skill: 前缀
        var head = makeCap(name: name, type: .bundle, dir: dir, id: id)
        var children: [Capability] = []
        let subNames = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            .filter { !$0.hasPrefix(".") && hasManifest(dir.appendingPathComponent($0)) }
        for sub in subNames {
            var c = makeCap(name: sub, type: .skill, dir: dir.appendingPathComponent(sub), id: "\(id)/\(sub)")
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
            head.desc = L("\(children.count) 项 skill 套装")
        }
        let m = meta.entries[id]
        let source = m?.sourceUrl.map(StoreFS.normalizeSource) ?? gitRemote(dir).map(StoreFS.normalizeSource)
        return Entry(id: id, cap: head, children: children, bundleKind: .directory,
                     sourceUrl: source, latest: m?.latest, changedMembers: m?.changed,
                     upstreamNew: m?.upstreamNew,
                     autoUpdate: m?.autoUpdate ?? false, skippedUpdate: m?.skipped != nil)
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
            desc: curated?.localizedDesc ?? front["description"] ?? "",
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
            return L("二进制 CLI，无 SKILL.md。") + (para ?? "")
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

    /// 两个路径是否指同一处（双方解析 symlink 链后比较；macOS 默认卷大小写不敏感）。
    /// store 成员本身是软链（私有开发场景）时两侧都会解析到最终真身，仍判相等。
    private func samePath(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.resolvingSymlinksInPath().path
            .compare(b.standardizedFileURL.resolvingSymlinksInPath().path, options: .caseInsensitive) == .orderedSame
    }

    /// 单一路径的链接状态：symlink→**约定的 store 目标**且目标存在 = on；目标丢失或
    /// 指到别处 = broken（v2.16：目标「存在」不等于「指对」——指向别处旧副本的链接
    /// 曾被谎报为健康 on）；真实目录/文件（非 symlink）= stub；不存在 = off。
    func linkStatus(linkPath: URL, expectedTarget: URL) -> (LinkStatus, String?) {
        let p = linkPath.path
        guard let attrs = try? fm.attributesOfItem(atPath: p) else { return (.off, nil) }
        if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            guard let dest = try? fm.destinationOfSymbolicLink(atPath: p) else { return (.broken, L("断链")) }
            let resolved = URL(fileURLWithPath: dest, relativeTo: linkPath.deletingLastPathComponent()).standardizedFileURL
            guard fm.fileExists(atPath: resolved.path) else { return (.broken, L("断链")) }
            guard samePath(resolved, expectedTarget) else { return (.broken, L("指向别处：\(abbrev(resolved.path))")) }
            return (.on, nil)
        }
        return (.stub, L("本地副本"))
    }

    /// 套装子项状态：整套 symlink ⇒ 全部跟随；物化目录 ⇒ 逐子项判定。
    func bundleChildStatus(bundleLink: URL, bundleDir: URL, childName: String) -> (LinkStatus, String?) {
        let p = bundleLink.path
        guard let attrs = try? fm.attributesOfItem(atPath: p) else { return (.off, nil) }
        if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            guard let dest = try? fm.destinationOfSymbolicLink(atPath: p) else { return (.broken, L("断链")) }
            let resolved = URL(fileURLWithPath: dest, relativeTo: bundleLink.deletingLastPathComponent()).standardizedFileURL
            guard fm.fileExists(atPath: resolved.appendingPathComponent(childName).path) else { return (.broken, L("断链")) }
            guard samePath(resolved, bundleDir) else { return (.broken, L("指向别处：\(abbrev(resolved.path))")) }
            return (.on, nil)
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
    /// metaSnapshot（v2.17）：移除时把 EntryMeta 写进目录内 `.popskill-meta.json`，
    /// 恢复时回填 sourceUrl/autoUpdate——更新链不会因进回收站而断。
    @discardableResult
    func moveToTrash(_ url: URL, metaSnapshot: StoreMeta.EntryMeta? = nil) throws -> URL {
        let parent = url.deletingLastPathComponent().lastPathComponent
        let bucket = StoreFS.trashBuckets.contains(parent) ? parent : CapType.skill.dirName
        let bucketURL = trashURL.appendingPathComponent(bucket)
        try fm.createDirectory(at: bucketURL, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        // 时间戳只到秒：同名条目同一秒内二次入站会撞名抛错（移除套装多成员、快速连点）。
        // 撞了就在名字段补短后缀（`~xxxx`）——时间戳必须保持在末尾，
        // listTrash/pruneTrash 都按「结尾 20 字符戳」解析（v2.16 修正：旧版把
        // 后缀追加在戳后面，导致该条目名字不去戳、时间沉底、恢复出脏名目录）
        var dest = bucketURL.appendingPathComponent("\(url.lastPathComponent)-\(stamp)")
        if fm.fileExists(atPath: dest.path) {
            dest = bucketURL.appendingPathComponent("\(url.lastPathComponent)~\(UUID().uuidString.prefix(4))-\(stamp)")
        }
        try fm.moveItem(at: url, to: dest)
        if let snap = metaSnapshot {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            let sidecar = dest.appendingPathComponent(".popskill-meta.json")
            try? enc.encode(snap).write(to: sidecar, options: .atomic)
        }
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
            var name = n
            var date: Date?
            // 去后缀只看形状，不依赖 date 解析成功（解析失败顶多没时间，名字必须干净）。
            // 三种历史形状都认：name-stamp / name~xxxx-stamp（同秒撞名，v2.16 起）/
            // name-stamp-xxxx（v2.8–v2.15 的撞名旧形状，戳在中段）
            let suffix = String(n.suffix(20))
            if suffix.count == 20, suffix.hasSuffix("Z"), suffix.dropFirst(4).first == "-" {
                name = String(n.dropLast(21))
                date = f.date(from: suffix)
                if let tilde = name.range(of: "~", options: .backwards),
                   name.distance(from: tilde.upperBound, to: name.endIndex) == 4 {
                    name = String(name[..<tilde.lowerBound])   // 去掉撞名 ~xxxx
                }
            } else if n.count > 26, n.dropLast(4).hasSuffix("-") {
                let mid = String(n.dropLast(5).suffix(20))     // 旧撞名形状：戳在倒数第 6-25 位
                if mid.hasSuffix("Z"), mid.dropFirst(4).first == "-" {
                    name = String(n.dropLast(26))
                    date = f.date(from: mid)
                }
            }
            return TrashItem(id: "\(bucket)/\(n)", name: name, kindDir: bucket, date: date, url: url)
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// 清空回收站（v2.16：设置页此前只能去 Finder 手删）。不可逆，调用方必须先确认
    func emptyTrash() throws {
        for e in trashEntryURLs() { try fm.removeItem(at: e.url) }
    }

    /// 恢复到 store 的原 kind 目录；同名已存在则拒绝（先移走现有的再恢复）。
    /// v2.17：若回收站目录内有 `.popskill-meta.json` 快照，回填 meta（不覆盖已有键）。
    func restoreFromTrash(_ item: TrashItem) throws {
        let name = try sanitizeName(item.name)
        let kind = StoreFS.trashBuckets.contains(item.kindDir) ? item.kindDir : CapType.skill.dirName
        let dest = env.storeRoot.appendingPathComponent(kind).appendingPathComponent(name)
        guard !fm.fileExists(atPath: dest.path) else { throw StoreError.alreadyExists(name) }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: item.url, to: dest)
        let sidecar = dest.appendingPathComponent(".popskill-meta.json")
        if let data = try? Data(contentsOf: sidecar),
           let snap = try? JSONDecoder().decode(StoreMeta.EntryMeta.self, from: data) {
            // 恢复目的地的 kind 目录决定身份前缀（bucket 名 → CapType）
            let restoredKind = CapType.allCases.first { $0.dirName == kind } ?? .skill
            let metaKey = typedId(restoredKind, name)
            mutateMeta { meta in
                // 同名已有 meta（例如先装了新版）不覆盖——恢复的是「被删那一版」的来源记忆
                if meta.entries[metaKey] == nil {
                    var m = snap
                    // 恢复后本地已是当前内容，旧 latest/检查点会误亮徽标——清掉让下次检查重算
                    m.latest = nil
                    m.changed = nil
                    m.latestFingerprint = nil
                    m.skipped = nil
                    m.lastHead = nil
                    m.localDigest = nil
                    m.upstreamNew = nil
                    meta.entries[metaKey] = m
                }
            }
            try? fm.removeItem(at: sidecar)
        }
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
            // 收敛（v2.16 审计 #3）：全部子项都回到 on 就换回「整套一条 symlink」——
            // 永久物化的套装，上游新增子项默认漏挂（整链形态才会自动跟随新子项）。
            // 只有目录内容可证明「全是我们自建的子项 symlink（至多混个 .DS_Store）」才收敛，
            // 有任何真实文件/未知条目一律保持物化，绝不删用户数据
            if !isSymlink(bundleLink) {
                let contents = (try? fm.contentsOfDirectory(atPath: bundleLink.path)) ?? []
                let convergeable = contents.allSatisfy { name in
                    name == ".DS_Store" || (allChildren.contains(name) && isSymlink(bundleLink.appendingPathComponent(name)))
                }
                let allOn = allChildren.allSatisfy { isSymlink(bundleLink.appendingPathComponent($0)) }
                if convergeable && allOn {
                    try fm.removeItem(at: bundleLink)
                    try createLink(at: bundleLink, to: bundleDir)
                }
            }
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

    /// 解析来源：local 直接扫描；github 浅 clone 到临时目录再扫描。
    /// npm 源不走 resolve：npm 包发布的是 CLI 二进制（技能目录是 CLI 运行时生成的），
    /// 更新走 checkNpmUpdate/applyNpmUpdate，「添加」流程装不出技能所以仍然拒绝。
    func resolve(_ rawUrl: String) throws -> ResolvedSource {
        let url = rawUrl.trimmingCharacters(in: .whitespaces)
        let kind = SourceKind.of(url)
        switch kind {
        case .npm:
            throw StoreError.sourceUnsupported(L("npm 包装的是 CLI 本体，装技能请用 GitHub 仓库或本地路径；已装的 npm 源 CLI 会自动纳入更新检查"))
        case .local:
            let dir = URL(fileURLWithPath: NSString(string: url).expandingTildeInPath).standardizedFileURL
            guard fm.fileExists(atPath: dir.path) else { throw StoreError.resolveFailed(L("路径不存在：\(url)")) }
            return try resolveDir(dir, url: url, kind: .local)
        case .wellKnown:
            // 单文件协议直装（v2.14）：GET SKILL.md → staging 目录 → 常规安装计划。
            // 归拢键形态（wk:host，无技能名）只出现在 checkUpdate/applyUpdate，
            // 它们已在上游分流，这里只会收到「添加」流程粘的完整地址
            guard let host = wellKnownHost(url), let name = try? sanitizeName(wellKnownSkillName(url) ?? ""),
                  let dl = wellKnownSkillURL(host: host, name: name) else {
                throw StoreError.resolveFailed(L("well-known 地址需要形如 https://域名/.well-known/skills/名称/SKILL.md"))
            }
            let data: Data
            do { data = try httpGet(dl) }
            catch { throw StoreError.resolveFailed(L("拉取 SKILL.md 失败（\(host)）——检查网络后重试。")) }
            let stageRoot = fm.temporaryDirectory.appendingPathComponent("popskill-stage-\(UUID().uuidString.prefix(8))")
            let dir = stageRoot.appendingPathComponent(name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("SKILL.md"))
            return try resolveDir(dir, url: "wk:\(host)", kind: .wellKnown)
        case .github:
            try StoreFS.ensureGit()   // 新 Mac 没装 CLT 时,给人话引导而不是裸 git 系统弹窗
            let (cloneURL, repoName, norm) = try StoreFS.githubTarget(url)
            let stageRoot = fm.temporaryDirectory.appendingPathComponent("popskill-stage-\(UUID().uuidString.prefix(8))")
            // clone 目标目录名 = 仓库名——它会一路成为 store 目录名和 symlink 名
            //（曾直接用随机临时目录名，装出来的条目叫 popskill-stage-xxxx）
            let tmp = stageRoot.appendingPathComponent(repoName)
            let r = run("/usr/bin/git", ["clone", "--depth", "1", cloneURL, tmp.path], timeout: 300)
            guard r.status == 0 else {
                discardStagingDir(tmp)
                throw StoreError.resolveFailed(StoreFS.humanGitError(cloneURL: cloneURL, stderr: r.err))
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

    /// 安装 GitHub 源依赖系统 git。没装命令行工具(CLT)的新 Mac 上，`/usr/bin/git` 是
    /// xcode-select 垫片，直接调用会弹系统「需要安装开发者工具」框 + 一句英文报错——
    /// 普通用户看不懂。这里先静默探测，给一句能照做的人话。
    static func ensureGit() throws {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        probe.arguments = ["-p"]   // 已装 CLT/Xcode 才返回 0，不会触发安装弹窗
        probe.standardOutput = Pipe(); probe.standardError = Pipe()
        do { try probe.run(); probe.waitUntilExit() } catch {
            throw StoreError.sourceUnsupported(L("未检测到 git（macOS 命令行工具）。请在「终端」运行 xcode-select --install 装好后重试。"))
        }
        if probe.terminationStatus != 0 {
            throw StoreError.sourceUnsupported(L("未检测到 git（macOS 命令行工具）。请在「终端」运行 xcode-select --install 装好后重试。"))
        }
    }

    /// 把 git 的英文 stderr 翻成普通用户能懂的话；认不出再退回原文（绝不出现冒号后空白）。
    static func humanGitError(cloneURL: String, stderr: String) -> String {
        let e = stderr.lowercased()
        if e.contains("could not resolve host") || e.contains("could not resolve") || e.contains("timed out") || e.contains("network is unreachable") {
            return L("连不上网络，没法获取这个仓库——检查网络后重试。")
        }
        if e.contains("authentication") || e.contains("could not read username") || e.contains("terminal prompts disabled") || e.contains("permission denied") {
            return L("这个仓库需要登录（可能是私有仓库）——Popskill 暂时只支持公开仓库。")
        }
        if e.contains("repository not found") || e.contains("not found") || e.contains("does not exist") {
            return L("找不到这个仓库——检查地址是否写对、是否为公开仓库。")
        }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? L("获取仓库失败——请检查地址与网络后重试。")
            : L("获取仓库失败：\(String(trimmed.prefix(200)))")
    }

    /// 来源 → 可在浏览器打开的网址（github 页 / npm 包页）。本地源返回 nil（调用方走访达）。
    /// 别把 `npm:@x/y` 拼成 `https://npm:@x/y` 这种点了跳不动的畸形 URL。
    static func sourceWebURL(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        switch SourceKind.of(s) {
        case .github:
            return URL(string: "https://\(normalizeSource(s))")   // → github.com/owner/repo
        case .npm:
            let pkg = String(s.dropFirst(4)).trimmingCharacters(in: .whitespaces)  // 去掉 "npm:"
            guard !pkg.isEmpty else { return nil }
            return URL(string: "https://www.npmjs.com/package/\(pkg)")
        case .wellKnown:
            // "wk:open.feishu.cn" / 完整 well-known 地址 → 域名首页
            let host = s.hasPrefix("wk:") ? String(s.dropFirst(3)) : (wellKnownHost(s) ?? "")
            guard !host.isEmpty else { return nil }
            return URL(string: "https://\(host)")
        case .local:
            return nil
        }
    }

    /// github 源 → (clone URL, 仓库名, 规范化源)。深路径/简写/大小写都收敛到 owner/repo。
    static func githubTarget(_ url: String) throws -> (cloneURL: String, repoName: String, norm: String) {
        let norm = normalizeSource(url)
        let parts = norm.split(separator: "/")
        guard parts.count == 3, parts[0] == "github.com" else {
            throw StoreError.resolveFailed(L("无法识别 GitHub 仓库：\(url)"))
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
        // github/wellKnown 的 staging 都是我们自建的临时目录；local 是用户原地目录绝不能删
        guard src.kind == .github || src.kind == .wellKnown else { return }
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
            throw StoreError.resolveFailed(L("未找到 SKILL.md — 该源不是 skill 也不是套装"))
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

    /// 安装事务（v2.18 重做）：预检 → 隐藏临时名 → 原子 rename → 记账建链 → meta。
    /// 任一步失败磁盘回到操作前——曾经「链接失败留 store 半成品，重试撞已存在」。
    /// 链接目标位的真实目录冲突在**动盘之前**就报错（不再让 createLink 半途拦）。
    func install(_ src: ResolvedSource, linkTools: [Tool]) throws {
        let name = try sanitizeName(src.entryName)
        let kindDir = env.storeRoot.appendingPathComponent(CapType.skill.dirName)
        let dest = kindDir.appendingPathComponent(name)
        guard !fm.fileExists(atPath: dest.path) else { throw StoreError.alreadyExists(src.entryName) }
        let linkKind: CapType = src.isBundle ? .bundle : .skill
        // ① 预检全部链接位：真实目录占位 = 计划错误，此时一个字节都没写
        for t in linkTools {
            let link = toolLinkPath(t, kind: linkKind, name: name)
            if fm.fileExists(atPath: link.path) && !isSymlink(link) {
                throw StoreError.notASymlink(link.path)
            }
        }
        // ② 新内容先落同卷隐藏临时名——copy 中途失败（磁盘满等）只清自己的临时目录
        try fm.createDirectory(at: kindDir, withIntermediateDirectories: true)
        let incoming = kindDir.appendingPathComponent(".popskill-incoming-\(name)")
        try? fm.removeItem(at: incoming)
        do { try fm.copyItem(at: src.stagingDir, to: incoming) }
        catch { try? fm.removeItem(at: incoming); throw error }
        // ③ 原子 rename 竞争正式名：并发装同名时输家在这一步得 alreadyExists，
        //    绝不会删掉赢家刚落好的目录（旧 check-then-copy 有 TOCTOU 窗）
        do { try fm.moveItem(at: incoming, to: dest) }
        catch {
            try? fm.removeItem(at: incoming)
            if fm.fileExists(atPath: dest.path) { throw StoreError.alreadyExists(src.entryName) }
            throw error
        }
        // ④ 建链记账；失败只撤本次建的链接 + 本次落的 store 副本
        var created: [URL] = []
        do {
            for t in linkTools {
                let link = toolLinkPath(t, kind: linkKind, name: name)
                try createLink(at: link, to: dest)
                created.append(link)
            }
        } catch {
            for link in created { try? removeLink(at: link) }
            try? fm.removeItem(at: dest)   // 本次安装写入的新内容，撤销 ≠ 删用户数据
            throw error
        }
        discardStaging(src)
        mutateMeta { meta in
            meta.entries[typedId(linkKind, name)]
                = StoreMeta.EntryMeta(sourceUrl: src.url, autoUpdate: false, latest: nil)
        }
    }

    /// 重拉事务（v2.18，取代「先 removeEntry 再 install」的裸序）：
    /// 旧版保留到新版与链接全部就位才让位；任一步失败按账本回滚，
    /// 磁盘回到操作前——曾经「旧版已进回收站、新版只装了一半」。
    /// 行为对齐旧 repull：旧 meta 键清除、新键记 sourceUrl（autoUpdate 归零）。
    func repullSwap(_ entry: Entry, resolved: ResolvedSource, relinkTools: [Tool], tools: [Tool]) throws {
        let name = try sanitizeName(resolved.entryName)
        let kindDir = env.storeRoot.appendingPathComponent(CapType.skill.dirName)
        let dest = kindDir.appendingPathComponent(name)
        let linkKind: CapType = resolved.isBundle ? .bundle : .skill
        // ① 预检要建的链接位：真实目录冲突动盘前报错（stub 走修复弹层，不该静默覆盖）
        for t in relinkTools {
            let link = toolLinkPath(t, kind: linkKind, name: name)
            if fm.fileExists(atPath: link.path) && !isSymlink(link) {
                throw StoreError.notASymlink(link.path)
            }
        }
        // ② 新内容落隐藏临时名（此刻旧版分毫未动）
        try fm.createDirectory(at: kindDir, withIntermediateDirectories: true)
        let incoming = kindDir.appendingPathComponent(".popskill-incoming-\(name)")
        try? fm.removeItem(at: incoming)
        do { try fm.copyItem(at: resolved.stagingDir, to: incoming) }
        catch { try? fm.removeItem(at: incoming); throw error }
        // ③ 撤旧链接（记账可回滚）：全部工具 × 全部成员，与 removeEntry 同覆盖面
        var removedLinks: [(link: URL, target: URL)] = []
        // ④ 旧 store 目录让位进回收站（记账可回滚；多成员=源式套装逐成员）
        var movedDirs: [(from: URL, backup: URL)] = []
        func rollback() {
            for m in movedDirs.reversed() { try? fm.moveItem(at: m.backup, to: m.from) }
            for r in removedLinks.reversed() { try? fm.createSymbolicLink(at: r.link, withDestinationURL: r.target) }
            try? fm.removeItem(at: incoming)
        }
        let metaNow = loadMeta()
        do {
            for cap in entry.allCaps {
                for t in tools {
                    let link = toolLinkPath(t, kind: cap.layoutKind, name: cap.name)
                    if isSymlink(link) {
                        let target = (try? fm.destinationOfSymbolicLink(atPath: link.path))
                            .map { URL(fileURLWithPath: $0, relativeTo: link.deletingLastPathComponent()).standardizedFileURL }
                            ?? cap.dirURL
                        try removeLink(at: link)
                        removedLinks.append((link, target))
                    }
                }
            }
            for cap in (entry.bundleKind == .source ? (entry.children ?? []) : [entry.cap])
            where fm.fileExists(atPath: cap.dirURL.path) && !isSymlink(cap.dirURL) {
                let snap = metaNow.entries[cap.id]
                let backup = try moveToTrash(cap.dirURL, metaSnapshot: snap)
                movedDirs.append((cap.dirURL, backup))
            }
        } catch { rollback(); throw error }
        // ⑤ 原子 rename 进正式位
        do { try fm.moveItem(at: incoming, to: dest) }
        catch { rollback(); throw error }
        // ⑥ 建新链记账；失败撤新链/新目录并整体回滚
        var created: [URL] = []
        do {
            for t in relinkTools {
                let link = toolLinkPath(t, kind: linkKind, name: name)
                try createLink(at: link, to: dest)
                created.append(link)
            }
        } catch {
            for l in created { try? removeLink(at: l) }
            try? fm.removeItem(at: dest)
            rollback()
            throw error
        }
        discardStaging(resolved)
        mutateMeta { meta in
            for cap in entry.children ?? [] { meta.entries.removeValue(forKey: cap.id) }
            meta.entries.removeValue(forKey: entry.id)
            meta.entries[typedId(linkKind, name)]
                = StoreMeta.EntryMeta(sourceUrl: resolved.url, autoUpdate: false, latest: nil)
        }
    }

    /// 移除条目：撤全部 symlink（含物化目录）→ store 副本移入回收站
    func removeEntry(_ entry: Entry, tools: [Tool]) throws {
        guard entry.bundleKind != .marketplace else {
            throw StoreError.sourceUnsupported(L("Marketplace 插件由 Claude Code 管理——在 Claude Code 里用 /plugin 卸载"))
        }
        // 源式套装 = 平铺成员的集合，逐成员按独立条目移除
        if entry.bundleKind == .source {
            let metaNow = loadMeta()
            let headMeta = metaNow.entries[entry.id]
            for cap in entry.children ?? [] {
                for t in tools {
                    let link = toolLinkPath(t, kind: cap.layoutKind, name: cap.name)
                    if isSymlink(link) { try removeLink(at: link) }
                }
                // 快照成员 meta；缺 sourceUrl 时用套装源补上——恢复后仍能归拢/更新
                var snap = metaNow.entries[cap.id] ?? StoreMeta.EntryMeta()
                if snap.sourceUrl == nil {
                    snap.sourceUrl = headMeta?.sourceUrl ?? entry.sourceUrl
                }
                try moveToTrash(cap.dirURL, metaSnapshot: snap)
            }
            mutateMeta { meta in
                for cap in entry.children ?? [] { meta.entries.removeValue(forKey: cap.id) }
                meta.entries.removeValue(forKey: entry.id)
            }
            return
        }
        for t in tools {
            let link = toolLinkPath(t, kind: entry.cap.layoutKind, name: entry.name)
            if isSymlink(link) {
                try removeLink(at: link)
            } else if entry.isBundle, fm.fileExists(atPath: link.path) {
                // 物化目录：先撤子项 symlink，空了再删目录。
                // Finder 逛过一次就会留 .DS_Store（v2.16 审计 #4）——只剩它也算空，
                // 否则整个目录变成 UI 里看不见的幽灵；有其它真实文件仍保守留下
                for c in entry.children ?? [] {
                    let cl = link.appendingPathComponent(c.name)
                    if isSymlink(cl) { try removeLink(at: cl) }
                }
                let leftovers = (try? fm.contentsOfDirectory(atPath: link.path)) ?? []
                if leftovers.allSatisfy({ $0 == ".DS_Store" }) {
                    try fm.removeItem(at: link)
                }
            }
        }
        let snap = loadMeta().entries[entry.id]
        try moveToTrash(entry.cap.dirURL, metaSnapshot: snap)
        mutateMeta { meta in meta.entries.removeValue(forKey: entry.id) }
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
        let latest: String          // 单成员 = 上游版本号/"新版"；源式套装 = "N 项"；contentUnchanged 时为空
        let changedMembers: [String]
        let upstreamNew: [String]   // 上游有、本地没装的技能（monorepo 月度痛点）
        let fingerprint: String     // 这次结论对应的上游状态指纹（「跳过此版本」的钉子，v2.15）
        var partialFailures = 0     // 有变化但另有 N 个成员没查成（well-known 网络抖动，v2.16 如实透出）
        var contentUnchanged = false // 仅有上游新增、无内容差异——不亮更新徽标（v2.17）
    }

    /// 组合指纹：没有 git HEAD 的源（本地路径/well-known）用「变化成员名:内容哈希」拼合。
    /// 上游内容再变，指纹必变——跳过只钉得住那一个状态。
    func combinedFingerprint(_ pairs: [(name: String, hash: String)]) -> String {
        var hasher = SHA256()
        for p in pairs.sorted(by: { $0.name < $1.name }) {
            hasher.update(data: Data("\(p.name):\(p.hash)|".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 跳过抑制（v2.15）：true = 该上游状态已被用户跳过，本次按「无更新」处理。
    /// 指纹变了（上游又出了新东西）自动清掉旧跳过——「跳过此版本」不是「永不提醒」。
    func skipSuppressed(_ entryId: String, fingerprint: String) -> Bool {
        guard let skip = loadMeta().entries[entryId]?.skipped, !skip.isEmpty else { return false }
        if skip == fingerprint { return true }
        mutateMeta { meta in
            var m = meta.entries[entryId] ?? StoreMeta.EntryMeta()
            m.skipped = nil
            meta.entries[entryId] = m
        }
        return false
    }

    /// 「跳过此版本」：把当前亮着的更新按上游状态指纹记入 meta，徽标熄灭。
    /// 旧 meta（2.15 前检查出的徽标）没存指纹时退回 lastHead（github=sha / npm=版本号）；
    /// 都没有才存 latest 标签——那种源下次完整比对会重亮一次，再跳过就钉住了。
    @discardableResult
    func skipLatest(_ entryId: String) -> Bool {
        mutateMeta { meta in
            guard var m = meta.entries[entryId], m.latest != nil else { return }
            m.skipped = m.latestFingerprint ?? m.lastHead ?? m.latest
            m.latest = nil
            m.changed = nil
            m.latestFingerprint = nil
            meta.entries[entryId] = m
        }
    }

    /// 恢复更新提醒：清跳过标记。检查点必须一起清——跳过期间被抑制的检查照常
    /// 落盘了 lastHead，不清的话 HEAD 短路会拿它直接判「最新」，徽标永远回不来。
    /// 调用方随后应对该源定向重查（强制完整比对），让徽标从真相重新推导。
    @discardableResult
    func unskipLatest(_ entryId: String) -> Bool {
        mutateMeta { meta in
            guard var m = meta.entries[entryId] else { return }
            m.skipped = nil
            m.lastHead = nil
            m.localDigest = nil
            meta.entries[entryId] = m
        }
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
    func saveCheckpoint(_ entryId: String, head: String, localDigest: String) {
        mutateMeta { meta in
            var m = meta.entries[entryId] ?? StoreMeta.EntryMeta()
            m.lastHead = head
            m.localDigest = localDigest
            meta.entries[entryId] = m
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
        guard let url = entry.sourceUrl else { return nil }
        // npm 源（v2.14）：语义完全不同——比对/升级的是全局 CLI，不 clone 不碰 store 目录
        if SourceKind.of(url) == .npm { return try checkNpmUpdate(entry) }
        // well-known 源（v2.14）：逐成员 GET SKILL.md 比内容，不走 git
        if SourceKind.of(url) == .wellKnown, url.hasPrefix("wk:") {
            return try checkWellKnownUpdate(entry, host: String(url.dropFirst(3)))
        }
        // HEAD 短路（v2.8 性能）：上游 commit 没动 且 本地未漂移 才跳过整仓 clone——
        // 一次 ls-remote 替代几十 MB 下载，13 个源的启动检查从分钟级降到秒级。
        // 本地不变性必须一起验（localDigest，纯磁盘 IO）：目标用户天天在终端动
        // ~/.agents，只比 HEAD 会让本地改坏的技能永远检不出来。
        // 亮着更新徽标（latest 非 nil）的也不短路：短路会把上次的「新版」结论钉死，
        // 走完整比对才能重新解析出上游版本号、或在上游回退后熄灭徽标。
        // ls-remote 失败（断网等）不吞：落到下面的完整 resolve，让错误如实抛出
        if SourceKind.of(url) == .github,
           let m = loadMeta().entries[entry.id],
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
        var changedPairs: [(name: String, hash: String)] = []
        var changedVersion: String?
        for cap in members where !isSymlink(cap.dirURL) {
            guard let staged = stagedMemberDir(staging: resolved.stagingDir, cap: cap) else { continue }
            let stagedHash = computeDirHash(staged)
            if computeDirHash(cap.dirURL) != stagedHash {
                changed.append(cap.name)
                changedPairs.append((cap.name, stagedHash))
                changedVersion = frontmatter(staged.appendingPathComponent("SKILL.md"))["version"]
            }
        }
        // known = 本条目成员 ∪ store 顶层 skills 名——同仓已装的兄弟（本地路径不归拢时）不算「新增」
        let knownNames = Set(members.map(\.name)).union(topLevelSkillNames())
        let upstreamNew = upstreamOnlySkills(staging: resolved.stagingDir, knownNames: knownNames)
        // 无论有没有内容更新，上游新增名单都落 meta——toast 曾只报个数，用户装不了（v2.17）
        saveUpstreamNew(entry.id, upstreamNew.isEmpty ? nil : upstreamNew)
        if let sha = resolved.headSha { saveCheckpoint(entry.id, head: sha, localDigest: localDigest(entry)) }
        guard !changed.isEmpty else {
            // 完整比对确认与上游一致（如用户在终端手动同步过）：熄灭残留的更新徽标。
            // 只有这条路径能清——HEAD 短路的 nil 是「没变化」不是「已一致」
            if loadMeta().entries[entry.id]?.latest != nil { saveLatest(entry.id, latest: nil) }
            // 仅有上游新增、无内容变更：仍返回检查结果，让 UI 亮「+N」而不亮更新徽标
            if !upstreamNew.isEmpty {
                return UpdateCheck(entryId: entry.id, latest: "", changedMembers: [],
                                   upstreamNew: upstreamNew, fingerprint: "upstream-new|\(upstreamNew.joined(separator: ","))",
                                   contentUnchanged: true)
            }
            return nil
        }
        // 上游状态指纹：git 源 = HEAD sha + 变化成员名集合——sha 钉上游、名单钉本地漂移面：
        // 跳过后在终端又改坏别的成员，changed 集扩大即指纹变化，重新亮徽标
        // （v2.16 修正：纯 sha 会把跳过期间的本地漂移一并静音，违背 v2.8 立的漂移必检约束）。
        // 本地路径源退回变化内容组合哈希
        let fingerprint = resolved.headSha.map { "\($0)|\(changed.sorted().joined(separator: ","))" }
            ?? combinedFingerprint(changedPairs)
        if skipSuppressed(entry.id, fingerprint: fingerprint) {
            // 跳过内容更新时仍暴露上游新增
            if !upstreamNew.isEmpty {
                return UpdateCheck(entryId: entry.id, latest: "", changedMembers: [],
                                   upstreamNew: upstreamNew, fingerprint: fingerprint, contentUnchanged: true)
            }
            return nil
        }
        let latest: String
        if changed.count == 1 && members.count == 1 {
            latest = (changedVersion != nil && changedVersion != members[0].version) ? changedVersion! : L("新版")
        } else {
            latest = L("\(changed.count) 项")
        }
        return UpdateCheck(entryId: entry.id, latest: latest, changedMembers: changed,
                           upstreamNew: upstreamNew, fingerprint: fingerprint)
    }

    /// 把上游新增名单写入 meta（空/nil = 清除）
    func saveUpstreamNew(_ entryId: String, _ names: [String]?) {
        mutateMeta { meta in
            var m = meta.entries[entryId] ?? StoreMeta.EntryMeta()
            m.upstreamNew = (names?.isEmpty == false) ? names : nil
            meta.entries[entryId] = m
        }
    }

    /// 上游 skills/ 下有 SKILL.md、但本地没装的目录名
    private func upstreamOnlySkills(staging: URL, knownNames: Set<String>) -> [String] {
        let skillsDir = staging.appendingPathComponent("skills")
        let base = fm.fileExists(atPath: skillsDir.path) ? skillsDir : staging
        return ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []).sorted()
            .filter { !$0.hasPrefix(".") && !knownNames.contains($0) && hasManifest(base.appendingPathComponent($0)) }
    }

    /// store/skills 顶层目录名（平铺安装的技能 + 目录形套装名）
    private func topLevelSkillNames() -> Set<String> {
        let dir = env.storeRoot.appendingPathComponent(CapType.skill.dirName)
        return Set(((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") })
    }

    /// 执行更新：clone 一次，只换有变化的成员；每个被换的成员先备份进回收站。
    /// symlink 路径不变自动延续。返回 (更新了哪些, 上游新增未装)。
    @discardableResult
    func applyUpdate(_ entry: Entry) throws -> (updated: [String], upstreamNew: [String]) {
        guard let url = entry.sourceUrl else { throw StoreError.resolveFailed(L("该源没有记录 URL，无法更新")) }
        if SourceKind.of(url) == .npm { return try applyNpmUpdate(entry) }   // 升级全局 CLI（v2.14）
        if SourceKind.of(url) == .wellKnown, url.hasPrefix("wk:") {          // 换 SKILL.md 单文件（v2.14）
            return try applyWellKnownUpdate(entry, host: String(url.dropFirst(3)))
        }
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
            catch { try? fm.removeItem(at: incoming); throw partialFailure(error, done: updated) }
            let backup = try moveToTrash(cap.dirURL)
            do { try fm.moveItem(at: incoming, to: cap.dirURL) }
            catch {
                try? fm.moveItem(at: backup, to: cap.dirURL)   // 换名失败回滚
                throw partialFailure(error, done: updated)
            }
            updated.append(cap.name)
        }
        let knownNames = Set(members.map(\.name)).union(topLevelSkillNames())
        let upstreamNew = upstreamOnlySkills(staging: resolved.stagingDir, knownNames: knownNames)
        // 落盘后再算 digest——此刻本地已是新版内容
        if let sha = resolved.headSha { saveCheckpoint(entry.id, head: sha, localDigest: localDigest(entry)) }
        saveLatest(entry.id, latest: nil)
        saveUpstreamNew(entry.id, upstreamNew.isEmpty ? nil : upstreamNew)
        return (updated, upstreamNew)
    }

    /// 安装上游 monorepo 里本地还没有的技能（v2.17）。
    /// 从源 clone/读一次，把 names 拷进 store/skills/ 并可选挂载；meta 继承套装 sourceUrl。
    @discardableResult
    func installUpstreamMembers(_ entry: Entry, names: [String], linkTools: [Tool]) throws -> [String] {
        guard let url = entry.sourceUrl, !url.isEmpty else {
            throw StoreError.resolveFailed(L("该源没有记录 URL，无法安装上游新增技能"))
        }
        let sk = SourceKind.of(url)
        guard sk == .github || sk == .local else {
            throw StoreError.sourceUnsupported(L("只有 GitHub / 本地路径来源支持安装上游新增技能"))
        }
        let resolved = try resolve(url)
        defer { discardStaging(resolved) }
        var installed: [String] = []
        let srcNorm = StoreFS.normalizeSource(url)
        for raw in names {
            let name = try sanitizeName(raw)
            let dest = env.storeRoot.appendingPathComponent(CapType.skill.dirName).appendingPathComponent(name)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            var staged: URL?
            for candidate in ["skills/\(name)", name] {
                let d = resolved.stagingDir.appendingPathComponent(candidate)
                if hasManifest(d) { staged = d; break }
            }
            if staged == nil {
                let d = resolved.stagingDir.appendingPathComponent("skills").appendingPathComponent(name)
                if hasManifest(d) { staged = d }
            }
            guard let srcDir = staged else { continue }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            // 唯一临时名 + 原子 rename 竞争正式名（v2.18）：批量装多源并发时同名新增
            // 只会一家胜出，输家清理自己的临时目录——旧 check-then-copy 失败时
            // 无条件删正式目标，会把赢家刚装好的目录连根拔掉留一地断链
            let incoming = dest.deletingLastPathComponent()
                .appendingPathComponent(".popskill-incoming-\(name)-\(UUID().uuidString.prefix(8))")
            do { try fm.copyItem(at: srcDir, to: incoming) }
            catch { try? fm.removeItem(at: incoming); throw error }
            do { try fm.moveItem(at: incoming, to: dest) }
            catch {
                try? fm.removeItem(at: incoming)
                if fm.fileExists(atPath: dest.path) { continue }   // 另一个源先装好：跳过，不算失败
                throw error
            }
            mutateMeta { meta in
                let key = typedId(.skill, name)   // 上游新增永远装进 skills/
                var m = meta.entries[key] ?? StoreMeta.EntryMeta()
                m.sourceUrl = srcNorm
                meta.entries[key] = m
            }
            for t in linkTools {
                try createLink(at: toolLinkPath(t, kind: .skill, name: name), to: dest)
            }
            installed.append(name)
        }
        // 从套装 upstreamNew 名单里扣掉已装；未找到的下次 check 会重算
        let prev = loadMeta().entries[entry.id]?.upstreamNew ?? entry.upstreamNew ?? []
        let remaining = prev.filter { !installed.contains($0) }
        saveUpstreamNew(entry.id, remaining.isEmpty ? nil : remaining)
        return installed
    }

    /// 多成员更新中途失败时，把「已换掉几项」写进错误——旧文案只说「更新 X 失败」，
    /// 前面已成功落盘的成员从叙事里消失，用户以为整批没动（v2.16 审计 #10）
    func partialFailure(_ error: Error, done: [String]) -> Error {
        guard !done.isEmpty else { return error }
        return StoreError.resolveFailed(L("已更新 \(done.count) 项（\(done.joined(separator: L("、")))）后失败：\(error.localizedDescription)"))
    }

    func saveLatest(_ entryId: String, latest: String?, changed: [String]? = nil, fingerprint: String? = nil) {
        mutateMeta { meta in
            var m = meta.entries[entryId] ?? StoreMeta.EntryMeta()
            m.latest = latest
            m.changed = latest == nil ? nil : changed
            m.latestFingerprint = latest == nil ? nil : fingerprint
            meta.entries[entryId] = m
        }
    }

    /// 定时任务人话备注（v2.10）。note 传 nil/空串 = 清除
    @discardableResult
    func saveSchedNote(_ label: String, note: String?) -> Bool {
        mutateMeta { meta in
            var notes = meta.schedNotes ?? [:]
            let trimmed = note?.trimmingCharacters(in: .whitespaces)
            notes[label] = (trimmed?.isEmpty ?? true) ? nil : trimmed
            meta.schedNotes = notes
        }
    }

    // ── 未托管目录导入（v2.1，吸收 cc-switch 的 scan_unmanaged）──
    // 工具目录里的真实目录（非 symlink）且 store 没有同名 ⇒ 未托管。
    // 导入 = 复制进 store → 原目录进回收站 → 原位换 symlink。

    struct UnmanagedDir {
        let name: String
        let toolId: String
        let url: URL
        var kind: CapType = .skill   // v2.17：扩到 agents/mcp/bin
    }

    /// 扫描工具侧未托管的真实目录/文件（非 symlink 且 store 无同名）。
    /// v2.17 起覆盖 skills / agents / mcp / bin 四 kind（此前只扫 skills，agent 漏收）。
    /// v2.18：已知集合按类型化 id 匹配——skills/shared 已托管不该让同名 agents/shared
    /// 永远躲过扫描（裸名去重曾把四个 kind 摁进一个命名空间）。
    func scanUnmanaged(tools: [Tool], knownIds: Set<String>) -> [UnmanagedDir] {
        var out: [UnmanagedDir] = []
        let kinds: [CapType] = [.skill, .agent, .mcp, .cli]
        for t in tools {
            for kind in kinds {
                let dir = t.root.appendingPathComponent(kind.dirName)
                for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where !name.hasPrefix(".") {
                    guard !knownIds.contains(typedId(kind, name)) else { continue }
                    let url = dir.appendingPathComponent(name)
                    guard !isSymlink(url) else { continue }
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
                    switch kind {
                    case .skill:
                        guard isDir.boolValue, hasManifest(url) || isBundleDir(url) else { continue }
                    case .agent, .mcp:
                        // agent/mcp 多为目录；Claude agents 也有单文件 .md
                        if isDir.boolValue { /* ok */ }
                        else if kind == .agent, name.hasSuffix(".md") { /* ok */ }
                        else { continue }
                    case .cli:
                        break   // bin 下文件或目录都算
                    case .bundle:
                        continue
                    }
                    out.append(UnmanagedDir(name: name, toolId: t.id, url: url, kind: kind))
                }
            }
        }
        return out
    }

    /// 导入结果如实分账（v2.16：曾只返回成功名单——「发现 6 个、导入 4 个」差的 2 个无解释）
    struct ImportResult {
        var imported: [String] = []
        var skippedSameName: [String] = []
    }

    func importUnmanaged(_ items: [UnmanagedDir]) throws -> ImportResult {
        var result = ImportResult()
        for item in items {
            let name = try sanitizeName(item.name)
            let kindDir = item.kind.dirName
            let dest = env.storeRoot.appendingPathComponent(kindDir).appendingPathComponent(name)
            guard !fm.fileExists(atPath: dest.path) else { result.skippedSameName.append(name); continue }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            do { try fm.copyItem(at: item.url, to: dest) }
            catch {
                // 半拷贝必须清掉（与 install 同款防呆，v2.16 审计 #6）：残骸留在 store 会被
                // 扫成正常条目，重试还会因「同名已存在」被静默跳过——永远修不好
                try? fm.removeItem(at: dest)
                throw error
            }
            try replaceCopyWithLink(at: item.url, target: dest)
            result.imported.append(name)
        }
        return result
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
        runProcess(bin, args, timeout: timeout)
    }
}

/// 线程安全的一次性结果盒（同步桥专用，v2.18 严格并发整改）：
/// 回调/后台线程写、调用线程读，NSLock 保护——semaphore 超时后迟到的回调
/// 只会写进无人再读的盒子，不再直接改捕获的局部 var（Swift 6 里是数据竞态错误）。
/// 首写生效，后续写被忽略。
final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func set(_ v: T) { lock.lock(); if value == nil { value = v }; lock.unlock() }
    func get() -> T? { lock.lock(); defer { lock.unlock() }; return value }
}

/// 子进程封装（StoreFS / SchedEngine 共用）：并发排空双管道 + 超时 watchdog + 组 KILL
@discardableResult
func runProcess(_ bin: String, _ args: [String], timeout: TimeInterval = 120) -> (status: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: bin)
    p.arguments = args
    let outPipe = Pipe(), errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    do { try p.run() } catch { return (-1, "", "\(error)") }
    // 两路管道必须并发排空——顺序 readDataToEndOfFile 会在 stderr 写满 64KB 缓冲时与子进程互相卡死
    let outBox = ResultBox<Data>(), errBox = ResultBox<Data>()
    let drained = DispatchGroup()
    DispatchQueue.global().async(group: drained) { outBox.set(outPipe.fileHandleForReading.readDataToEndOfFile()) }
    DispatchQueue.global().async(group: drained) { errBox.set(errPipe.fileHandleForReading.readDataToEndOfFile()) }
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
                // 后台读线程之后写进的是带锁盒子，不再有内存危险
                return (-1, "", L("命令超时且输出管道无法排空，已放弃：\(cmd)"))
            }
        }
    }
    p.waitUntilExit()
    let out = String(data: outBox.get() ?? Data(), encoding: .utf8) ?? ""
    let err = String(data: errBox.get() ?? Data(), encoding: .utf8) ?? ""
    if timedOut {
        return (-1, out, L("命令超时（\(Int(timeout)) s）已终止：\(cmd) \(args.first ?? "")"))
    }
    return (p.terminationStatus, out, err)
}
