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
    let type: CapType
    var desc: String
    var version: String?      // 来自 frontmatter，可能没有
    var author: String?
    var tokens: Int           // 提示词体量估算（CLI 为 0）
    var dirURL: URL           // store 内真实目录
    var links: [String: LinkStatus] = [:]   // toolId → status
    var brokenCause: [String: String] = [:] // toolId → 成因

    func status(_ toolId: String) -> LinkStatus { links[toolId] ?? .off }
}

/// 已添加的源 — 唯一顶层概念。套装带 children，独立条目自身即能力。
struct Entry: Identifiable, Equatable {
    let id: String
    var cap: Capability                 // 套装时承载名称/描述等展示字段
    var children: [Capability]?         // 仅 Bundle 有
    var sourceUrl: String?
    var latest: String?                 // 上游最新版；存在且 ≠ version ⇒ 可更新
    var autoUpdate: Bool = false

    var isBundle: Bool { children != nil }
    var name: String { cap.name }
    var allCaps: [Capability] { children ?? [cap] }
    var hasUpdate: Bool {
        guard let latest, let v = cap.version else { return false }
        return latest != v
    }
}

enum SourceKind: String {
    case github, npm, local

    static func of(_ url: String?) -> SourceKind {
        guard let url, !url.isEmpty else { return .local }
        if url.hasPrefix("npm:") { return .npm }
        if url.hasPrefix("~") || url.hasPrefix("/") { return .local }
        return .github
    }
}

// ── 派生 ────────────────────────────────────────────────

struct Stats: Equatable {
    var bundles = 0, standalone = 0, total = 0
    var activeByTool: [String: Int] = [:]
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
        s.activeByTool[t.id] = caps.filter { $0.status(t.id) == .on }.count
    }
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
                    kind: .broken, cause: c.brokenCause[t.id] ?? "断链",
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
