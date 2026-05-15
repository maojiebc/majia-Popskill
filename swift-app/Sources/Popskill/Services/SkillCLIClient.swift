import Foundation

actor SkillCLIClient {
    private let executableURL: URL
    static let webDAVPasswordEnvironmentKey = "POPSKILL_WEBDAV_PASSWORD"

    init(executableURL: URL? = nil) {
        self.executableURL = executableURL ?? Self.resolveExecutableURL()
    }

    static var resolvedExecutablePath: String {
        resolveExecutableURL().path
    }

    static var executableOverridePath: String? {
        normalizedExecutableOverridePath(ProcessInfo.processInfo.environment["POPSKILL_CLI"])
    }

    static func normalizedExecutableOverridePath(_ value: String?) -> String? {
        let override = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let override, !override.isEmpty else {
            return nil
        }
        return (override as NSString).expandingTildeInPath
    }

    func domainSchema() async throws -> AssetDomainSchema {
        let data = try run(arguments: ["domain-schema", "--json"])
        return try Self.decodeResponse(AssetDomainSchema.self, from: data)
    }

    func health() async throws -> SidecarHealth {
        let data = try run(arguments: ["health", "--json"])
        return try Self.decodeResponse(SidecarHealth.self, from: data)
    }

    func webdavStatus() async throws -> WebDAVStatus {
        let data = try run(arguments: ["webdav-status", "--json"])
        return try Self.decodeResponse(WebDAVStatus.self, from: data)
    }

    func configureWebDAV(_ configuration: WebDAVConfiguration) async throws -> WebDAVStatus {
        let invocation = Self.webDAVConfigureInvocation(for: configuration)
        let data = try run(arguments: invocation.arguments, environment: invocation.environment)
        return try Self.decodeResponse(WebDAVStatus.self, from: data)
    }

    func webdavRemoteInfo() async throws -> WebDAVRemoteInfo {
        let data = try run(arguments: ["webdav-remote-info", "--json"])
        return try Self.decodeResponse(WebDAVRemoteInfo.self, from: data)
    }

    func webdavSyncPlan() async throws -> WebDAVSyncPlan {
        let data = try run(arguments: ["webdav-sync-plan", "--json"])
        return try Self.decodeResponse(WebDAVSyncPlan.self, from: data)
    }

    func list() async throws -> [Skill] {
        let data = try run(arguments: ["list", "--json"])
        return try Self.decodeResponse([Skill].self, from: data)
    }

    func listPackages() async throws -> [CapabilityPackage] {
        let data = try run(arguments: ["package-list", "--json"])
        return try Self.decodeResponse([CapabilityPackage].self, from: data)
    }

    func packageDetail(packageID: String) async throws -> CapabilityPackage {
        let data = try run(arguments: ["package-detail", packageID, "--json"])
        return try Self.decodeResponse(CapabilityPackage.self, from: data)
    }

    func packageInstall(packageID: String) async throws -> PackageInstallResult {
        let data = try run(arguments: ["package-install", packageID, "--json"])
        return try Self.decodeResponse(PackageInstallResult.self, from: data)
    }

    func packageConfig(packageID: String, key: String, valueEnvironmentKey: String? = nil) async throws -> PackageConfigResult {
        var arguments = ["package-config", packageID, "--key", key, "--json"]
        if let valueEnvironmentKey, !valueEnvironmentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--value-env", valueEnvironmentKey])
        }
        let data = try run(arguments: arguments)
        return try Self.decodeResponse(PackageConfigResult.self, from: data)
    }

    func listAgents() async throws -> [LocalAgent] {
        let data = try run(arguments: ["agent-list", "--json"])
        return try Self.decodeResponse([LocalAgent].self, from: data)
    }

    func listAgentTargets() async throws -> [AgentTarget] {
        let data = try run(arguments: ["agent-targets", "--json"])
        return try Self.decodeResponse([AgentTarget].self, from: data)
    }

    func catalogAgents(query: String? = nil, limit: Int = 80) async throws -> [CatalogAgent] {
        var arguments = ["agent-catalog", "--json", "--limit", String(limit)]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--query", query]
        }
        let data = try run(arguments: arguments)
        return try Self.decodeResponse([CatalogAgent].self, from: data)
    }

    func agentInstallPlan(agentKey: String, target: String = "claude-code") async throws -> AgentInstallPlan {
        let data = try run(arguments: ["agent-install-plan", agentKey, "--target", target, "--json"])
        return try Self.decodeResponse(AgentInstallPlan.self, from: data)
    }

    func scanUnmanaged() async throws -> [UnmanagedSkill] {
        let data = try run(arguments: ["scan-unmanaged", "--json"])
        return try Self.decodeResponse([UnmanagedSkill].self, from: data)
    }

    func detail(skillID: String) async throws -> Skill {
        let data = try run(arguments: ["detail", skillID, "--json"])
        return try Self.decodeResponse(Skill.self, from: data)
    }

    func checkUpdates() async throws -> [SkillUpdateInfo] {
        let data = try run(arguments: ["check-updates", "--json"])
        return try Self.decodeResponse([SkillUpdateInfo].self, from: data)
    }

    func discover(query: String?, limit: Int = 80) async throws -> [CatalogSkill] {
        var arguments = ["discover", "--json", "--limit", String(limit)]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--query", query])
        }

        let data = try run(arguments: arguments)
        return try Self.decodeResponse([CatalogSkill].self, from: data)
    }

    func listRepositories() async throws -> [SkillRepository] {
        let data = try run(arguments: ["repo-list", "--json"])
        return try Self.decodeResponse([SkillRepository].self, from: data)
    }

    func addRepository(
        owner: String,
        name: String,
        branch: String,
        enabled: Bool
    ) async throws -> SkillRepository {
        let data = try run(arguments: [
            "repo-add",
            "--owner",
            owner,
            "--name",
            name,
            "--branch",
            branch,
            "--enabled",
            String(enabled),
            "--json",
        ])
        return try Self.decodeResponse(SkillRepository.self, from: data)
    }

    func setRepositoryEnabled(
        _ enabled: Bool,
        owner: String,
        name: String
    ) async throws -> SkillRepositoryToggleResult {
        let data = try run(arguments: [
            "repo-toggle",
            "--owner",
            owner,
            "--name",
            name,
            "--enabled",
            String(enabled),
            "--json",
        ])
        return try Self.decodeResponse(SkillRepositoryToggleResult.self, from: data)
    }

    func removeRepository(owner: String, name: String) async throws -> SkillRepositoryRemoveResult {
        let data = try run(arguments: [
            "repo-remove",
            "--owner",
            owner,
            "--name",
            name,
            "--json",
        ])
        return try Self.decodeResponse(SkillRepositoryRemoveResult.self, from: data)
    }

    func installPlan(skillKey: String, app: TargetApp) async throws -> InstallPlan {
        let data = try run(arguments: [
            "install-plan",
            skillKey,
            "--app",
            app.rawValue,
            "--json",
        ])
        return try Self.decodeResponse(InstallPlan.self, from: data)
    }

    func install(skillKey: String, app: TargetApp) async throws -> Skill {
        let data = try run(arguments: [
            "install",
            skillKey,
            "--app",
            app.rawValue,
            "--json",
        ])
        return try Self.decodeResponse(Skill.self, from: data)
    }

    func update(skillID: String) async throws -> Skill {
        let data = try run(arguments: ["update", skillID, "--json"])
        return try Self.decodeResponse(Skill.self, from: data)
    }

    func uninstall(skillID: String) async throws -> SkillUninstallResult {
        let data = try run(arguments: ["uninstall", skillID, "--json"])
        return try Self.decodeResponse(SkillUninstallResult.self, from: data)
    }

    func listStubs() async throws -> [StubbedSkill] {
        let data = try run(arguments: ["stub-list", "--json"])
        return try Self.decodeResponse([StubbedSkill].self, from: data)
    }

    func stub(skillID: String) async throws -> StubbedSkill {
        let data = try run(arguments: ["stub", skillID, "--json"])
        return try Self.decodeResponse(StubbedSkill.self, from: data)
    }

    func rehydrate(skillID: String, app: TargetApp) async throws -> Skill {
        let data = try run(arguments: [
            "rehydrate",
            skillID,
            "--app",
            app.rawValue,
            "--json",
        ])
        return try Self.decodeResponse(Skill.self, from: data)
    }

    func securityScans() async throws -> [SecurityScanRecord] {
        let data = try run(arguments: ["security-scan-list", "--json"])
        return try Self.decodeResponse([SecurityScanRecord].self, from: data)
    }

    func securityScan(skillID: String? = nil, skillDirectory: String) async throws -> SecurityScanResult {
        var arguments = ["security-scan", skillDirectory, "--json"]
        if let skillID {
            arguments.append(contentsOf: ["--skill-id", skillID])
        }

        let data = try run(arguments: arguments)
        return try Self.decodeResponse(SecurityScanResult.self, from: data)
    }

    func listBackups() async throws -> [SkillBackup] {
        let data = try run(arguments: ["backup-list", "--json"])
        return try Self.decodeResponse([SkillBackup].self, from: data)
    }

    func restoreBackup(backupID: String, app: TargetApp) async throws -> Skill {
        let data = try run(arguments: [
            "backup-restore",
            backupID,
            "--app",
            app.rawValue,
            "--json",
        ])
        return try Self.decodeResponse(Skill.self, from: data)
    }

    func deleteBackup(backupID: String) async throws -> SkillBackupDeleteResult {
        let data = try run(arguments: ["backup-delete", backupID, "--json"])
        return try Self.decodeResponse(SkillBackupDeleteResult.self, from: data)
    }

    func importUnmanaged(directory: String, apps: [TargetApp]) async throws -> [Skill] {
        var arguments = ["import-unmanaged", directory, "--json"]
        for app in apps {
            arguments.append(contentsOf: ["--app", app.rawValue])
        }

        let data = try run(arguments: arguments)
        return try Self.decodeResponse([Skill].self, from: data)
    }

    func toggle(skillID: String, app: TargetApp, enabled: Bool) async throws {
        _ = try run(arguments: [
            "toggle",
            skillID,
            "--app",
            app.rawValue,
            "--enabled",
            String(enabled),
            "--json",
        ])
    }

    private func run(arguments: [String], environment: [String: String]? = nil) throws -> Data {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment {
            var mergedEnvironment = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                mergedEnvironment[key] = value
            }
            process.environment = mergedEnvironment
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Drain stdout and stderr concurrently. readDataToEndOfFile() blocks
        // until EOF; if we read stdout sequentially while stderr fills its
        // 64 KiB OS pipe buffer, the child would block on stderr write while
        // we wait on stdout, deadlocking the call. Long sidecar commands
        // (discover, security-scan, transcript scanners) can plausibly
        // produce that much warning output.
        //
        // DispatchGroup.wait() is a synchronization barrier: after it
        // returns, writes inside the async closures are visible without
        // extra locks. See docs/ipc.md for the stdout/stderr channel
        // separation contract this method implements.
        var stdoutBuffer = Data()
        var stderrBuffer = Data()
        let ioGroup = DispatchGroup()

        ioGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBuffer = outputPipe.fileHandleForReading.readDataToEndOfFile()
            ioGroup.leave()
        }

        ioGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBuffer = errorPipe.fileHandleForReading.readDataToEndOfFile()
            ioGroup.leave()
        }

        ioGroup.wait()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = Self.commandFailureMessage(
                stdout: stdoutBuffer,
                stderr: stderrBuffer,
                status: process.terminationStatus
            )
            throw CLIClientError.commandFailed(message)
        }

        return stdoutBuffer
    }

    static func webDAVConfigureInvocation(
        for configuration: WebDAVConfiguration
    ) -> (arguments: [String], environment: [String: String]?) {
        var arguments = [
            "webdav-configure",
            "--base-url",
            configuration.baseUrl,
            "--username",
            configuration.username,
            "--remote-root",
            configuration.remoteRoot,
            "--profile",
            configuration.profile,
            "--enabled",
            String(configuration.enabled),
            "--auto-sync",
            String(configuration.autoSync),
            "--json",
        ]
        var environment: [String: String]?

        if !configuration.password.isEmpty {
            arguments.append(contentsOf: ["--password-env", webDAVPasswordEnvironmentKey])
            environment = [webDAVPasswordEnvironmentKey: configuration.password]
        }

        return (arguments, environment)
    }

    static func commandFailureMessage(stdout: Data, stderr: Data, status: Int32) -> String {
        for data in [stderr, stdout] where !data.isEmpty {
            if let message = decodedErrorMessage(from: data) {
                return message
            }
        }

        for data in [stderr, stdout] where !data.isEmpty {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                return message
            }
        }

        return "skill-cli exited with \(status)"
    }

    private static func decodedErrorMessage(from data: Data) -> String? {
        guard
            let envelope = try? makeDecoder().decode(CLIErrorEnvelope.self, from: data),
            let error = envelope.error
        else {
            return nil
        }

        let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? error.code : message
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let response = try makeDecoder().decode(CLIResponse<T>.self, from: data)
        if let payload = response.data, response.ok {
            return payload
        }
        throw response.error ?? CLIClientError.invalidResponse
    }

    private static func resolveExecutableURL() -> URL {
        if let override = executableOverridePath {
            return URL(fileURLWithPath: override)
        }

        if let bundledSidecarURL = Bundle.main.resourceURL?.appendingPathComponent("skill-cli"),
           FileManager.default.isExecutableFile(atPath: bundledSidecarURL.path) {
            return bundledSidecarURL
        }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFile
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // Popskill
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // swift-app
            .deletingLastPathComponent() // repo root

        return repoRoot
            .appendingPathComponent("skill-cli")
            .appendingPathComponent("target")
            .appendingPathComponent("debug")
            .appendingPathComponent("skill-cli")
    }
}

private struct CLIErrorEnvelope: Decodable {
    let error: CLIErrorPayload?
}

enum CLIClientError: LocalizedError {
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message): message
        case .invalidResponse: "skill-cli returned an invalid response"
        }
    }
}
