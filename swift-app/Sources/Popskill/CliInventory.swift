import Foundation

// 本机 CLI 清单（v2.20）：npm 多前缀 + Homebrew / pipx / uv。
//
// 现实问题：`npm i -g` 只打默认前缀，但本机常同时有 ~/.local 与 /opt/homebrew
// 两份全局包；PATH 命中的那份和被升级的那份不是同一个，看起来「升级成功了、
// 命令还是旧的」。每日 Codex 任务就是为了绕开这件事。
//
// 启动 / 「检查更新」默认只查常用白名单（包名才离开本机）。打开 CLI 面板
// 或打开「巡检全部」才扫所有全局 npm 包。基础工具（node/npm/typescript…）
// 永远出现在名单里但不给升级按钮。

enum CliChannel: String, Codable, Sendable {
    case npm, brew, pipx, uv
    var label: String {
        switch self {
        case .npm: "npm"
        case .brew: "Homebrew"
        case .pipx: "pipx"
        case .uv: "uv"
        }
    }
}

struct GlobalCli: Identifiable, Equatable, Sendable {
    let name: String
    var displayName: String
    let installed: String
    var latest: String?
    var channel: CliChannel = .npm
    var prefix: String?
    var pathHit: String?
    var pathMatchesPrefix: Bool = true
    var excluded: Bool = false
    var allowlisted: Bool = false
    /// pipx 从 GitHub zip / 本地路径装的，不跟 PyPI 同名包比版本。
    var tracksIndex: Bool = true

    var id: String { "\(channel.rawValue)|\(name)|\(prefix ?? "")" }
    var hasUpdate: Bool {
        guard !excluded, tracksIndex, let latest else { return false }
        return cliVersionIsNewer(latest, than: installed)
    }

    init(name: String, installed: String, latest: String? = nil,
         displayName: String? = nil, channel: CliChannel = .npm, prefix: String? = nil,
         pathHit: String? = nil, pathMatchesPrefix: Bool = true,
         excluded: Bool = false, allowlisted: Bool = false,
         tracksIndex: Bool = true) {
        self.name = name
        self.displayName = displayName ?? name
        self.installed = installed
        self.latest = latest
        self.channel = channel
        self.prefix = prefix
        self.pathHit = pathHit
        self.pathMatchesPrefix = pathMatchesPrefix
        self.excluded = excluded
        self.allowlisted = allowlisted
        self.tracksIndex = tracksIndex
    }
}

/// 自动巡检 / 横幅「全部更新」会带走的常用 CLI。包名才离开本机。
///
/// v2.21 扩到主流终端 Agent：打开维护中心时仍会扫描全部 npm 全局包；这里的
/// 精确名单决定「启动时低泄露巡检」与「允许批量升级」的边界。
let maintainedNpmPackages: [String: String] = [
    "@anthropic-ai/claude-code": "claude",
    "@openai/codex": "codex",
    "@google/gemini-cli": "gemini",
    "@qwen-code/qwen-code": "qwen",
    "opencode": "opencode",
    "@larksuite/cli": "lark-cli",
    "@getnote/cli": "getnote",
    "@guandata/guanskill": "guanskill",
    "@earendil-works/pi-coding-agent": "pi",
    "clawhub": "clawhub",
    "mcporter": "mcporter",
]

let maintainedBrewFormulae: [String] = ["gemini-cli", "opencode", "aliyun-cli"]
let maintainedPipxPackages: [String] = ["agent-reach", "aider-chat", "open-interpreter", "yt-dlp"]
let maintainedUvTools: [String] = ["aider-chat", "open-interpreter", "specify-cli"]

/// 基础工具：能看见，但不能一键升级（误升 node 会拆掉整机工具链）
let excludedFoundationTools: Set<String> = [
    "node", "node@24", "npm", "pnpm", "typescript", "tsx",
    "@larksuiteoapi/node-sdk",
]

func isFoundationTool(_ name: String) -> Bool {
    excludedFoundationTools.contains(name)
}

func cliBinName(_ package: String) -> String {
    if let bin = maintainedNpmPackages[package] { return bin }
    if package.contains("/") { return String(package.split(separator: "/").last ?? Substring(package)) }
    return package
}

func normalizePrefix(_ path: String) -> String {
    var p = (path as NSString).standardizingPath
    if p.hasSuffix("/") { p.removeLast() }
    return p
}

func candidateNpmPrefixes(home: String, defaultPrefix: String?) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    func add(_ raw: String) {
        let p = normalizePrefix(raw)
        guard !p.isEmpty, seen.insert(p).inserted else { return }
        out.append(p)
    }
    if let defaultPrefix { add(defaultPrefix) }
    add((home as NSString).appendingPathComponent(".local"))
    add("/opt/homebrew")
    add("/usr/local")
    return out
}

func prefixHasNodeModules(_ prefix: String) -> Bool {
    FileManager.default.fileExists(atPath: (prefix as NSString).appendingPathComponent("lib/node_modules"))
}

func pathHitsPrefix(_ executable: String, prefix: String) -> Bool {
    let exe = normalizePrefix(executable)
    let pre = normalizePrefix(prefix)
    return exe == pre || exe.hasPrefix(pre + "/")
}

/// `brew outdated --json=v2` → [(name, installed, latest)]
func parseBrewOutdated(_ data: Data) -> [(name: String, installed: String, latest: String)] {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    var out: [(String, String, String)] = []
    for key in ["formulae", "casks"] {
        guard let rows = obj[key] as? [[String: Any]] else { continue }
        for row in rows {
            guard let name = row["name"] as? String else { continue }
            let installed = (row["installed_versions"] as? [String])?.last
                ?? (row["installed_versions"] as? String)
                ?? ""
            let latest = (row["current_version"] as? String) ?? ""
            guard !installed.isEmpty, !latest.isEmpty else { continue }
            out.append((name, installed, latest))
        }
    }
    return out
}

struct PipxPackage: Equatable {
    var version: String
    var packageOrUrl: String
}

/// pipx 的 `package_or_url` 是 PyPI 包名才跟仓库比；GitHub zip / git+ / 本地路径不算。
func pipxTracksIndex(_ packageOrUrl: String) -> Bool {
    let s = packageOrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return true }
    let lower = s.lowercased()
    if lower.hasPrefix("git+") || lower.hasPrefix("file:") { return false }
    if lower.contains("://") { return false }
    if s.hasPrefix("/") || s.hasPrefix(".") { return false }
    return true
}

/// 只认「远端更新」：1.5.0 相对 PyPI 0.1.0 不是升级。
func cliVersionIsNewer(_ candidate: String, than installed: String) -> Bool {
    let a = cliVersionComponents(candidate)
    let b = cliVersionComponents(installed)
    guard !a.isEmpty, !b.isEmpty else { return candidate != installed }
    let n = max(a.count, b.count)
    for i in 0..<n {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}

func cliVersionComponents(_ raw: String) -> [Int] {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    var nums: [Int] = []
    var cur = ""
    for ch in trimmed {
        if ch.isNumber { cur.append(ch) }
        else if ch == "." {
            nums.append(Int(cur) ?? 0)
            cur = ""
        } else {
            break
        }
    }
    if !cur.isEmpty { nums.append(Int(cur) ?? 0) }
    return nums
}

/// `pipx list --json` → {venv 名: 已装版 + 来源}
func parsePipxList(_ data: Data) -> [String: PipxPackage] {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let venvs = obj["venvs"] as? [String: Any] else { return [:] }
    var out: [String: PipxPackage] = [:]
    for (name, raw) in venvs {
        guard let info = raw as? [String: Any],
              let meta = info["metadata"] as? [String: Any],
              let main = meta["main_package"] as? [String: Any],
              let ver = main["package_version"] as? String else { continue }
        let src = (main["package_or_url"] as? String)
            ?? (main["package"] as? String)
            ?? name
        out[name] = PipxPackage(version: ver, packageOrUrl: src)
    }
    return out
}

/// Refuse a queued write if the exact installation or its provenance changed after inspection.
func sameCliInstallation(_ observed: GlobalCli, as planned: GlobalCli) -> Bool {
    observed.id == planned.id && observed.installed == planned.installed
        && observed.pathHit == planned.pathHit && observed.pathMatchesPrefix == planned.pathMatchesPrefix
        && observed.tracksIndex == planned.tracksIndex && observed.excluded == planned.excluded
}
