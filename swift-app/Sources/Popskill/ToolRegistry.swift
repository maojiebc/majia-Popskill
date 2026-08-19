import Foundation

/// 工具适配器注册表（v2.20）。
/// 矩阵列、默认挂载、沙盘路径全部从这里长出来——再加 Grok / Gemini 不再写 if。
///
/// 显示规则：
/// - `alwaysShow`（Claude / Codex）始终占一列，没装也显示「未安装」
/// - 其余工具只有技能目录真实存在才露出来，避免矩阵无限膨胀
struct ToolDef: Equatable {
    var id: String
    var name: String
    /// 相对工具根（`~` 或 `POPSKILL_TOOLS_ROOT`）的目录，如 `.claude`、`.pi/agent`
    var rootRelative: String
    var alwaysShow: Bool
}

extension ToolDef {
    static let builtins: [ToolDef] = [
        ToolDef(id: "claude", name: "Claude Code", rootRelative: ".claude", alwaysShow: true),
        ToolDef(id: "codex", name: "Codex CLI", rootRelative: ".codex", alwaysShow: true),
        ToolDef(id: "grok", name: "Grok", rootRelative: ".grok", alwaysShow: false),
        ToolDef(id: "gemini", name: "Gemini CLI", rootRelative: ".gemini", alwaysShow: false),
        ToolDef(id: "opencode", name: "OpenCode", rootRelative: ".config/opencode", alwaysShow: false),
        ToolDef(id: "pi", name: "Pi", rootRelative: ".pi/agent", alwaysShow: false),
    ]
}

extension StoreEnv {
    /// 把注册表展开成 toolId → 根目录。测试可只塞子集，scanTools 会跳过缺根的定义。
    static func toolRoots(at base: URL) -> [String: URL] {
        Dictionary(uniqueKeysWithValues: ToolDef.builtins.map {
            ($0.id, base.appendingPathComponent($0.rootRelative))
        })
    }
}
