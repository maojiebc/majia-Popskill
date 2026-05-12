import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    var health: SidecarHealth?
    var isLoading = false
    var errorMessage: String?

    private let client = SkillCLIClient()

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            health = try await client.health()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

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

                Button {
                    Task { await viewModel.load() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .help("Refresh")
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await viewModel.load() }
                }
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DetailSection(title: "Sidecar") {
                        DetailField(title: "Executable", value: cliPath)
                        DetailField(title: "POPSKILL_CLI", value: overridePath ?? "Not set")
                        DetailField(title: "Version", value: viewModel.health?.sidecarVersion ?? "Unknown")
                    }

                    DetailSection(title: "CC Switch") {
                        DetailField(title: "Installed", value: countText(viewModel.health?.installedCount))
                        DetailField(title: "Unmanaged", value: countText(viewModel.health?.unmanagedCount))
                        DetailField(title: "Backups", value: countText(viewModel.health?.backupCount))
                        DetailField(title: "Skill Store", value: viewModel.health?.skillStorePath ?? skillStorePath)
                        DetailField(title: "Skill Backups", value: viewModel.health?.skillBackupPath ?? backupPath)
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
        .task {
            if viewModel.health == nil {
                await viewModel.load()
            }
        }
    }

    private func countText(_ value: Int?) -> String {
        value.map(String.init) ?? "Unknown"
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
