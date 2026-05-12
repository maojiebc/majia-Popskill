import Foundation

actor SkillCLIClient {
    private let executableURL: URL

    init(executableURL: URL? = nil) {
        self.executableURL = executableURL ?? Self.resolveExecutableURL()
    }

    func list() async throws -> [Skill] {
        let data = try run(arguments: ["list", "--json"])
        let response = try Self.makeDecoder().decode(CLIResponse<[Skill]>.self, from: data)
        if let skills = response.data, response.ok {
            return skills
        }
        throw response.error ?? CLIClientError.invalidResponse
    }

    func scanUnmanaged() async throws -> [UnmanagedSkill] {
        let data = try run(arguments: ["scan-unmanaged", "--json"])
        let response = try Self.makeDecoder().decode(CLIResponse<[UnmanagedSkill]>.self, from: data)
        if let skills = response.data, response.ok {
            return skills
        }
        throw response.error ?? CLIClientError.invalidResponse
    }

    func detail(skillID: String) async throws -> Skill {
        let data = try run(arguments: ["detail", skillID, "--json"])
        let response = try Self.makeDecoder().decode(CLIResponse<Skill>.self, from: data)
        if let skill = response.data, response.ok {
            return skill
        }
        throw response.error ?? CLIClientError.invalidResponse
    }

    func checkUpdates() async throws -> [SkillUpdateInfo] {
        let data = try run(arguments: ["check-updates", "--json"])
        let response = try Self.makeDecoder().decode(CLIResponse<[SkillUpdateInfo]>.self, from: data)
        if let updates = response.data, response.ok {
            return updates
        }
        throw response.error ?? CLIClientError.invalidResponse
    }

    func discover(query: String?, limit: Int = 80) async throws -> [CatalogSkill] {
        var arguments = ["discover", "--json", "--limit", String(limit)]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--query", query])
        }

        let data = try run(arguments: arguments)
        let response = try Self.makeDecoder().decode(CLIResponse<[CatalogSkill]>.self, from: data)
        if let skills = response.data, response.ok {
            return skills
        }
        throw response.error ?? CLIClientError.invalidResponse
    }

    func install(skillKey: String, app: TargetApp) async throws -> Skill {
        let data = try run(arguments: [
            "install",
            skillKey,
            "--app",
            app.rawValue,
            "--json",
        ])
        let response = try Self.makeDecoder().decode(CLIResponse<Skill>.self, from: data)
        if let skill = response.data, response.ok {
            return skill
        }
        throw response.error ?? CLIClientError.invalidResponse
    }

    func update(skillID: String) async throws -> Skill {
        let data = try run(arguments: ["update", skillID, "--json"])
        let response = try Self.makeDecoder().decode(CLIResponse<Skill>.self, from: data)
        if let skill = response.data, response.ok {
            return skill
        }
        throw response.error ?? CLIClientError.invalidResponse
    }

    func uninstall(skillID: String) async throws -> SkillUninstallResult {
        let data = try run(arguments: ["uninstall", skillID, "--json"])
        let response = try Self.makeDecoder().decode(CLIResponse<SkillUninstallResult>.self, from: data)
        if let result = response.data, response.ok {
            return result
        }
        throw response.error ?? CLIClientError.invalidResponse
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
            let message = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIClientError.commandFailed(message ?? "skill-cli exited with \(process.terminationStatus)")
        }

        return output
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func resolveExecutableURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["POPSKILL_CLI"], !override.isEmpty {
            return URL(fileURLWithPath: override)
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
