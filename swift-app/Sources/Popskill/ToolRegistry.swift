import Foundation

/// 工具适配器注册表（v2.20）。
/// 矩阵列、默认挂载、沙盘路径全部从这里长出来——再加 Grok / Gemini 不再写 if。
///
/// 显示规则：
/// - `alwaysShow`（Claude / Codex / Cursor）始终占一列，没装也显示「未安装」
/// - 其余工具：本机有 App 或 CLI 才在设置里出开关，`tools.<id>.showOnHome`
///   缺省为关；打开后才进首页。技能目录存在不再当可见性门槛。
struct ToolDef: Equatable {
    var id: String
    var name: String
    /// 相对工具根（`~` 或 `POPSKILL_TOOLS_ROOT`）的目录，如 `.claude`、`.pi/agent`
    var rootRelative: String
    var alwaysShow: Bool
    /// 系统或用户 Applications 目录里的 bundle 名，如 `Cursor.app`；未知则 nil（不猜）
    var appBundle: String? = nil
    /// PATH / 常见 bin 里查找的可执行文件名
    var cliNames: [String] = []
}

/// 本机如何发现一个可选工具（设置「本机已发现」行用）。纯值，探测可注入。
enum ToolPresence: Equatable {
    case app(String)   // bundle 名，如 Cursor.app
    case cli(String)   // 可执行文件绝对路径
}

/// 设置页「本机已发现」一行。不是首页列——首页列仍是 `Tool`。
struct DetectedOptional: Identifiable, Equatable {
    let id: String
    let name: String
    var presence: ToolPresence?
    var showOnHome: Bool

    var hint: String {
        switch presence {
        case .app: L("App")
        case .cli(let path): abbrev(path)
        case nil: ""
        }
    }
}

extension ToolDef {
    static let builtins: [ToolDef] = [
        ToolDef(id: "claude", name: "Claude Code", rootRelative: ".claude", alwaysShow: true),
        ToolDef(id: "codex", name: "Codex CLI", rootRelative: ".codex", alwaysShow: true),
        ToolDef(id: "cursor", name: "Cursor", rootRelative: ".cursor", alwaysShow: true,
                appBundle: "Cursor.app", cliNames: ["cursor"]),
        ToolDef(id: "grok", name: "Grok", rootRelative: ".grok", alwaysShow: false, cliNames: ["grok"]),
        ToolDef(id: "gemini", name: "Gemini CLI", rootRelative: ".gemini", alwaysShow: false, cliNames: ["gemini"]),
        ToolDef(id: "opencode", name: "OpenCode", rootRelative: ".config/opencode", alwaysShow: false, cliNames: ["opencode"]),
        ToolDef(id: "pi", name: "Pi", rootRelative: ".pi/agent", alwaysShow: false, cliNames: ["pi"]),
    ]

    /// 系统级与当前用户级 Applications 都是 macOS 的合法安装位置。
    static func appSearchDirs(home: String) -> [String] {
        [
            "/Applications",
            URL(fileURLWithPath: home).appendingPathComponent("Applications").path,
        ]
    }

    /// 常见 bin 优先，再拼进程 PATH。不跑 `zsh -lc`（GUI PATH 瘦、login shell 会冻窗）。
    static func cliSearchDirs(home: String, pathEnv: String) -> [String] {
        var dirs: [String] = []
        var seen = Set<String>()
        func add(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let path = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            dirs.append(path)
        }
        add("/opt/homebrew/bin")
        add("/usr/local/bin")
        add(URL(fileURLWithPath: home).appendingPathComponent(".local/bin").path)
        add("/Applications/Cursor.app/Contents/Resources/app/bin")
        for part in pathEnv.split(separator: ":", omittingEmptySubsequences: true) {
            add(String(part))
        }
        return dirs
    }

    func presence(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        pathEnv: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> ToolPresence? {
        if let app = appBundle {
            for dir in Self.appSearchDirs(home: home) {
                let candidate = URL(fileURLWithPath: dir).appendingPathComponent(app).path
                if fileExists(candidate) { return .app(app) }
            }
        }
        for dir in Self.cliSearchDirs(home: home, pathEnv: pathEnv) {
            for name in cliNames {
                let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name).path
                if isExecutable(candidate) { return .cli(candidate) }
            }
        }
        return nil
    }

    func detected(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        pathEnv: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> Bool {
        presence(fileExists: fileExists, isExecutable: isExecutable, home: home, pathEnv: pathEnv) != nil
    }
}

extension StoreEnv {
    /// 把注册表展开成 toolId → 根目录。测试可只塞子集，scanTools 会跳过缺根的定义。
    static func toolRoots(at base: URL) -> [String: URL] {
        Dictionary(uniqueKeysWithValues: ToolDef.builtins.map {
            ($0.id, base.appendingPathComponent($0.rootRelative))
        })
    }
}
