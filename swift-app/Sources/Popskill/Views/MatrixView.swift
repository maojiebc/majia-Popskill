import SwiftUI

/// Skills × Tools matrix — the main view (S3 implements). Each row is a
/// capability (Skill / CLI / MCP / Agent), each column is an AI tool (Claude
/// Code / Codex). Inspector pane on the right shows position + symlink shape.
struct MatrixView: View {
    let store: PopskillStore

    var body: some View {
        PlaceholderView(
            symbol: "square.grid.3x3.fill",
            titleKey: "sidebar.matrix",
            sprintLabel: "S3 实现 · Skills × Tools 矩阵 + Inspector"
        )
    }
}
