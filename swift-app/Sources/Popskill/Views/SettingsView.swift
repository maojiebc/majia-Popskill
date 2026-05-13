import Observation
import Foundation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    var health: SidecarHealth?
    var webdavStatus: WebDAVStatus?
    var webdavRemoteInfo: WebDAVRemoteInfo?
    var webdavRemoteError: String?
    var isLoading = false
    var isCheckingWebDAVRemote = false
    var hasLoadedOnce = false
    var errorMessage: String?

    private let client = SkillCLIClient()

    func load() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            health = try await client.health()
            webdavStatus = try await client.webdavStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkWebDAVRemote() async {
        guard !isCheckingWebDAVRemote else {
            return
        }

        isCheckingWebDAVRemote = true
        webdavRemoteError = nil

        do {
            webdavRemoteInfo = try await client.webdavRemoteInfo()
        } catch {
            webdavRemoteInfo = nil
            webdavRemoteError = error.localizedDescription
        }

        isCheckingWebDAVRemote = false
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
                    DetailSection(title: "Sidecar", accent: PopskillSectionAccent.color(for: 0)) {
                        DetailField(title: "Executable", value: cliPath)
                        DetailField(title: "POPSKILL_CLI", value: overridePath ?? "Not set")
                        DetailField(title: "Version", value: viewModel.health?.sidecarVersion ?? "Unknown")
                    }

                    DetailSection(title: "CC Switch", accent: PopskillSectionAccent.color(for: 1)) {
                        DetailField(title: "Installed", value: countText(viewModel.health?.installedCount))
                        DetailField(title: "Unmanaged", value: countText(viewModel.health?.unmanagedCount))
                        DetailField(title: "Backups", value: countText(viewModel.health?.backupCount))
                        DetailField(title: "Repositories", value: repositoryCountText)
                        DetailField(title: "Skill Store", value: viewModel.health?.skillStorePath ?? skillStorePath)
                        DetailField(title: "Skill Backups", value: viewModel.health?.skillBackupPath ?? backupPath)
                    }

                    DetailSection(title: "Secrets", accent: PopskillSectionAccent.color(for: 2)) {
                        DetailField(title: "Local Secrets", value: "Popskill stores its own secrets in macOS Keychain.")
                        DetailField(title: "WebDAV Credentials", value: "Owned by CC Switch settings. Popskill only reads sanitized status output here.")
                    }

                    DetailSection(title: "WebDAV", accent: PopskillSectionAccent.color(for: 3)) {
                        WebDAVReadinessNote(status: viewModel.webdavStatus)
                        DetailField(title: "Configured", value: boolText(viewModel.webdavStatus?.configured))
                        DetailField(title: "Enabled", value: boolText(viewModel.webdavStatus?.enabled))
                        DetailField(title: "Auto Sync", value: boolText(viewModel.webdavStatus?.autoSync))
                        DetailField(title: "Base URL", value: viewModel.webdavStatus?.baseUrl ?? "Not set")
                        DetailField(title: "Remote Root", value: viewModel.webdavStatus?.remoteRoot ?? "cc-switch-sync")
                        DetailField(title: "Profile", value: viewModel.webdavStatus?.profile ?? "default")
                        DetailField(title: "Last Sync", value: timestampText(viewModel.webdavStatus?.status?.lastSyncAt))
                        DetailField(title: "Last Error", value: viewModel.webdavStatus?.status?.lastError ?? "None")
                        Divider()
                        HStack {
                            Button {
                                Task { await viewModel.checkWebDAVRemote() }
                            } label: {
                                if viewModel.isCheckingWebDAVRemote {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Fetch Remote Info", systemImage: "cloud")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canFetchWebDAVRemote || viewModel.isCheckingWebDAVRemote)
                            .help(webDAVRemoteInfoHelp)

                            if let webdavRemoteError = viewModel.webdavRemoteError {
                                Text(webdavRemoteError)
                                    .font(.caption)
                                    .foregroundStyle(Color.popStatusError)
                                    .lineLimit(2)
                            }
                        }

                        if let remoteInfo = viewModel.webdavRemoteInfo {
                            DetailField(title: "Remote Snapshot", value: remoteSnapshotText(remoteInfo))
                            DetailField(title: "Remote Device", value: remoteInfo.deviceName ?? "Unknown")
                            DetailField(title: "Remote Created", value: timestampText(remoteInfo.createdAt))
                            DetailField(title: "Remote Path", value: remoteInfo.remotePath ?? "Unknown")
                            DetailField(title: "Layout", value: remoteInfo.layout ?? "Unknown")
                            DetailField(title: "Compatible", value: boolText(remoteInfo.compatible))
                            DetailField(title: "Artifacts", value: remoteInfo.artifacts?.joined(separator: ", ") ?? "None")
                        }
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
        .popPageBackground()
        .task {
            if !viewModel.hasLoadedOnce {
                await viewModel.load()
            }
        }
    }

    private func countText(_ value: Int?) -> String {
        value.map(String.init) ?? "Unknown"
    }

    private func boolText(_ value: Bool?) -> String {
        value.map { $0 ? "Yes" : "No" } ?? "Unknown"
    }

    private func timestampText(_ value: Int?) -> String {
        guard let value else {
            return "Never"
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private var canFetchWebDAVRemote: Bool {
        viewModel.webdavStatus?.configured == true && viewModel.webdavStatus?.enabled == true
    }

    private var webDAVRemoteInfoHelp: String {
        guard let status = viewModel.webdavStatus else {
            return "Refresh settings before fetching WebDAV remote info"
        }

        guard status.configured else {
            return "Configure WebDAV in CC Switch before fetching remote info"
        }

        guard status.enabled == true else {
            return "Enable WebDAV sync before fetching remote info"
        }

        return "Fetch WebDAV Remote Info"
    }

    private func remoteSnapshotText(_ remoteInfo: WebDAVRemoteInfo) -> String {
        if remoteInfo.empty == true {
            return "Empty"
        }

        if let snapshotId = remoteInfo.snapshotId, !snapshotId.isEmpty {
            return snapshotId
        }

        return "Unknown"
    }

    private var repositoryCountText: String {
        guard let health = viewModel.health else {
            return "Unknown"
        }
        return "\(health.enabledRepositoryCount) enabled of \(health.repositoryCount)"
    }

    private var ipcDocsURL: URL? {
        if let bundledDocsURL = Bundle.main.resourceURL?.appendingPathComponent("ipc.md"),
           FileManager.default.fileExists(atPath: bundledDocsURL.path) {
            return bundledDocsURL
        }

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

struct WebDAVReadinessNote: View {
    let status: WebDAVStatus?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: PopskillRadius.smallCard))
        .overlay(
            RoundedRectangle(cornerRadius: PopskillRadius.smallCard)
                .stroke(color.opacity(0.16), lineWidth: 1)
        )
    }

    private var title: String {
        guard let status else {
            return "WebDAV status unknown"
        }

        guard status.configured else {
            return "WebDAV not configured"
        }

        guard status.enabled == true else {
            return "WebDAV configured but disabled"
        }

        return "WebDAV read-only bridge"
    }

    private var message: String {
        guard let status else {
            return "Refresh settings to load the saved CC Switch WebDAV configuration."
        }

        guard status.configured else {
            return "Popskill can inspect CC Switch WebDAV settings once they exist; configuration and Sync Now are still v0.1 work."
        }

        guard status.enabled == true else {
            return "Remote snapshot lookup is disabled until CC Switch WebDAV sync is enabled."
        }

        return "Remote snapshot lookup is available. Upload/download sync is intentionally not exposed from the sidecar yet."
    }

    private var symbolName: String {
        guard let status else {
            return "questionmark.circle"
        }

        if !status.configured {
            return "cloud.slash"
        }

        if status.enabled != true {
            return "pause.circle"
        }

        return "cloud"
    }

    private var color: Color {
        guard let status else {
            return .popStatusNeutral
        }

        if !status.configured || status.enabled != true {
            return .popStatusWarning
        }

        return .popSectionBlue
    }
}
