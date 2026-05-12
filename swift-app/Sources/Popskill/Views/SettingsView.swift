import SwiftUI

struct SettingsView: View {
    private let cliPath = SkillCLIClient.resolvedExecutablePath
    private let overridePath = SkillCLIClient.executableOverridePath
    private let skillStorePath = NSHomeDirectory() + "/.cc-switch/skills"
    private let backupPath = NSHomeDirectory() + "/.cc-switch/skill-backups"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(.largeTitle, weight: .bold))
                    Text("Local diagnostics")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DetailSection(title: "Sidecar") {
                        DetailField(title: "Executable", value: cliPath)
                        DetailField(title: "POPSKILL_CLI", value: overridePath ?? "Not set")
                    }

                    DetailSection(title: "CC Switch") {
                        DetailField(title: "Skill Store", value: skillStorePath)
                        DetailField(title: "Skill Backups", value: backupPath)
                    }

                    DetailSection(title: "Secrets") {
                        DetailField(title: "Storage", value: "macOS Keychain")
                        DetailField(title: "Plaintext Policy", value: "Secrets are not stored in SQLite or app settings.")
                    }

                    if let docsURL = ipcDocsURL {
                        Link(destination: docsURL) {
                            Label("Open IPC Docs", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(28)
            }
        }
        .background(Color.popMainBackground)
    }

    private var ipcDocsURL: URL? {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFile
            .deletingLastPathComponent() // Views
            .deletingLastPathComponent() // Popskill
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // swift-app
            .deletingLastPathComponent() // repo root
        let docsURL = repoRoot
            .appendingPathComponent("docs")
            .appendingPathComponent("ipc.md")
        return FileManager.default.fileExists(atPath: docsURL.path) ? docsURL : nil
    }
}
