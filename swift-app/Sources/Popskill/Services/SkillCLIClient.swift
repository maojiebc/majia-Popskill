import Foundation

actor SkillCLIClient {
    private let executableURL: URL

    init(executableURL: URL? = nil) {
        self.executableURL = executableURL ?? Self.resolveExecutableURL()
    }

    static var resolvedExecutablePath: String {
        resolveExecutableURL().path
    }

    static var executableOverridePath: String? {
        let override = ProcessInfo.processInfo.environment["POPSKILL_CLI"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let override, !override.isEmpty else {
            return nil
        }
        return override
    }

    func health() async throws -> SidecarHealth {
        let data = try run(arguments: ["health", "--json"])
        return try Self.decodeResponse(SidecarHealth.self, from: data)
    }

    func list() async throws -> [Skill] {
        let data = try run(arguments: ["list", "--json"])
        return try Self.decodeResponse([Skill].self, from: data)
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
        ])
    }

    private func run(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = Self.commandFailureMessage(
                stdout: output,
                stderr: errorOutput,
                status: process.terminationStatus
            )
            throw CLIClientError.commandFailed(message)
        }

        return output
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
        if let override = ProcessInfo.processInfo.environment["POPSKILL_CLI"], !override.isEmpty {
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
