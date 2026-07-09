import Foundation

// 数据模型 — 与 SPEC.md §2 对应。entries 是唯一顶层集合，其余全部派生。

enum LinkStatus: String, Codable, Equatable {
    case on, off, stub, broken
}

enum CapType: String, Codable, CaseIterable, Identifiable {
    case skill = "Skill"
    case agent = "Agent"
    case mcp = "MCP"
    case cli = "CLI"
    case bundle = "Bundle"
    var id: String { rawValue }

    /// store / 工具根下对应的子目录名
    var dirName: String {
        switch self {
        case .skill, .bundle: "skills"
        case .agent: "agents"
        case .mcp: "mcp"
        case .cli: "bin"
        }
    }
}

struct Tool: Identifiable, Equatable {
    let id: String            // "claude" / "codex"
    let name: String          // "Claude Code"
    let root: URL             // ~/.claude/
    var connected: Bool       // root 目录存在
    var defaultTarget: Bool   // 新安装默认挂载

    var rootDisplay: String { abbrev(root.path) + "/" }
}

/// 单项能力（独立条目本体，或套装子项）
struct Capability: Identifiable, Equatable {
    let id: String
    let name: String
    var type: CapType          // 展示/过滤用类型（可由 frontmatter / 名称特征推断）
    var linkKind: CapType?     // 链接布局用：store 里实际所在的 kind 目录（nil = 同 type）
    var desc: String
    var version: String?      // 来自 frontmatter，可能没有
    var author: String?
    var tokens: Int           // 提示词体量估算（CLI 为 0）
    var dirURL: URL           // store 内真实目录
    var readme: String?       // SKILL.md / README 开头摘要（详情 peek 用，扫描时提取）
    var repoSubdir: String?   // 上游仓库内的子路径（lock 文件 skillPath，monorepo 用）
    var links: [String: LinkStatus] = [:]   // toolId → status
    var brokenCause: [String: String] = [:] // toolId → 成因

    func status(_ toolId: String) -> LinkStatus { links[toolId] ?? .off }
    /// symlink 路径计算永远用这个，不用展示类型（guancli 显示为 CLI 但链接仍在 skills/）
    var layoutKind: CapType { linkKind ?? type }

    /// 任一工具侧断链 ⇒ 整卡/整行红（卡片与表格共用一份，别再各写一份）
    func isBroken(_ tools: [Tool]) -> Bool { tools.contains { status($0.id) == .broken } }
    /// 断链徽标取首个断链工具的成因（两侧都断且成因不同时，明细在详情 peek 里逐工具可见）
    func firstBrokenCause(_ tools: [Tool]) -> String {
        guard let t = tools.first(where: { status($0.id) == .broken }) else { return L("断链") }
        return brokenCause[t.id] ?? L("断链")
    }
}

/// 套装的两种形态（v2.1）：
/// directory = store 里的真实嵌套目录（如 anthropic-skills），工具侧整链/物化；
/// source    = 平铺成员按同一上游仓库归拢的视图（如 baoyu 系），工具侧逐成员 symlink。
enum BundleKind: String, Codable, Equatable {
    case directory, source
    /// Claude Code Marketplace 插件（v2.6）：只读可见层——进矩阵/可搜索/可 peek/计入统计，
    /// 但生命周期归 Claude Code（/plugin），开关/移除/更新一律不碰
    case marketplace
}

/// 已添加的源 — 唯一顶层概念。套装带 children，独立条目自身即能力。
struct Entry: Identifiable, Equatable {
    let id: String
    var cap: Capability                 // 套装时承载名称/描述等展示字段
    var children: [Capability]?         // 仅 Bundle 有
    var bundleKind: BundleKind?         // 仅 Bundle 有
    var sourceUrl: String?
    var latest: String?                 // 上游最新版；存在且 ≠ version ⇒ 可更新
    var changedMembers: [String]? = nil // 套装里具体哪些成员有新版（提醒到行）
    var upstreamNew: [String]? = nil    // 上游有、本地没装的成员名（v2.17：可一键安装）
    var autoUpdate: Bool = false
    var skippedUpdate: Bool = false     // 用户跳过了当前上游版本（v2.15，右键可恢复提醒）

    var isBundle: Bool { children != nil }
    var isManagedExternally: Bool { bundleKind == .marketplace }
    var name: String { cap.name }
    var allCaps: [Capability] { children ?? [cap] }
    /// latest 只在 checkUpdate 确认内容有差异时写入、applyUpdate 后清除，
    /// 所以有值即有更新（源式套装的 latest 是 "N 项" 这类标签，不是 semver）。
    var hasUpdate: Bool { guard let latest, !latest.isEmpty else { return false }; return true }
    /// 上游 monorepo 新增、本地还没装的技能数（横幅汇总用）
    var upstreamNewCount: Int { upstreamNew?.count ?? 0 }
    var hasUpstreamNew: Bool { upstreamNewCount > 0 }
    /// 用户视角的「几个技能待更新」：套装按 changedMembers 逐成员计，独立项计 1。
    /// 套装里 5 个成员有新版就是 5，不是 1——横幅/按钮计数一律用它，别再数源。
    /// changedMembers 缺失（旧 meta 没存明细）时保守计 1。
    var updateCount: Int {
        guard hasUpdate else { return 0 }
        if let c = changedMembers, !c.isEmpty { return c.count }
        return 1
    }
    /// 套装更新徽标的悬停说明：点名具体哪些成员有新版（卡片/表格两视图共用一份）
    var updateHelp: String {
        guard let changed = changedMembers, !changed.isEmpty else { return L("更新此套装") }
        return L("有新版：\(changed.sorted().joined(separator: L("、")))——点击全部更新")
    }
    /// 上游新增徽标悬停：点名可装技能
    var upstreamNewHelp: String {
        guard let names = upstreamNew, !names.isEmpty else { return L("安装上游新增技能") }
        let list = names.count <= 4 ? names.sorted().joined(separator: L("、"))
            : L("\(names.sorted().prefix(3).joined(separator: L("、"))) 等 \(names.count) 个")
        return L("上游新增未装：\(list)——点击安装")
    }
}

enum SourceKind: String {
    case github, npm, local
    case wellKnown = "well-known"   // rawValue 进 KindTag 直接大写展示，别拼成 WELLKNOWN

    static func of(_ url: String?) -> SourceKind {
        guard let url, !url.isEmpty else { return .local }
        // npmjs.com 包页 URL 也算 npm（v2.16）：现实中用户粘的是浏览器地址栏，
        // 曾被当 github 源报「无法识别 GitHub 仓库」，npm 引导语永远没机会出场
        if url.hasPrefix("npm:") || url.lowercased().contains("npmjs.com/package/") { return .npm }
        if url.hasPrefix("wk:") || url.contains("/.well-known/skills/") { return .wellKnown }
        if url.hasPrefix("~") || url.hasPrefix("/") { return .local }
        return .github
    }
}

// ── 派生 ────────────────────────────────────────────────

struct Stats: Equatable {
    var bundles = 0, standalone = 0, total = 0
    var activeByTool: [String: Int] = [:]
    var inactiveByTool: [String: Int] = [:]   // total - active（off/stub/broken 都算「未挂载」）
    var byType: [CapType: Int] = [:]          // 顶部统计条：摊平后各类型计数；.bundle = 套装数
    var stubs = 0, broken = 0, symlinks = 0
}

struct Issue: Identifiable, Equatable {
    var id: String { "\(capId)-\(toolId)" }
    let capId: String
    let capName: String
    let toolId: String
    let toolName: String
    let kind: LinkStatus      // .broken 或 .stub
    let cause: String
    let entryId: String
    let entryName: String
    let sourceUrl: String?
    let latest: String?
}

struct ToolAgg: Equatable {
    var total = 0, on = 0, off = 0, stub = 0, broken = 0
}

func deriveStats(_ entries: [Entry], tools: [Tool]) -> Stats {
    var s = Stats()
    let caps = entries.flatMap(\.allCaps)
    s.bundles = entries.filter(\.isBundle).count
    s.standalone = entries.count - s.bundles
    s.total = caps.count
    for t in tools {
        let on = caps.filter { $0.status(t.id) == .on }.count
        s.activeByTool[t.id] = on
        s.inactiveByTool[t.id] = caps.count - on
    }
    // 类型计数：摊平后的 cap 按展示类型分桶（Skill/Agent/MCP/CLI）；Bundle 单计套装数
    for c in caps where c.type != .bundle {
        s.byType[c.type, default: 0] += 1
    }
    s.byType[.bundle] = s.bundles
    for c in caps {
        for (_, st) in c.links {
            switch st {
            case .on: s.symlinks += 1
            case .stub: s.stubs += 1
            case .broken: s.broken += 1
            case .off: break
            }
        }
    }
    return s
}

func deriveIssues(_ entries: [Entry], tools: [Tool]) -> [Issue] {
    var out: [Issue] = []
    for e in entries {
        for c in e.allCaps {
            for t in tools where c.status(t.id) == .broken {
                out.append(Issue(
                    capId: c.id, capName: c.name, toolId: t.id, toolName: t.name,
                    kind: .broken, cause: c.brokenCause[t.id] ?? L("断链"),
                    entryId: e.id, entryName: e.name,
                    sourceUrl: e.sourceUrl, latest: e.hasUpdate ? e.latest : nil
                ))
            }
        }
    }
    return out
}

func deriveUpdates(_ entries: [Entry]) -> [Entry] {
    entries.filter(\.hasUpdate)
}

func aggregate(_ children: [Capability], toolId: String) -> ToolAgg {
    var a = ToolAgg(total: children.count)
    for c in children {
        switch c.status(toolId) {
        case .on: a.on += 1
        case .off: a.off += 1
        case .stub: a.stub += 1
        case .broken: a.broken += 1
        }
    }
    return a
}

// ── 小工具 ──────────────────────────────────────────────

func abbrev(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

func formatTokens(_ n: Int) -> String {
    String(format: "%.1fk tokens", Double(n) / 1000)
}
