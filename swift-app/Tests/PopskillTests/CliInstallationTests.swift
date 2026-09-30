import XCTest
@testable import Popskill

final class CliInstallationTests: XCTestCase {
    func testBrewAgentAndCloudFormulaeFindTheirActualCommands() {
        XCTAssertEqual(cliBinName("claude-code"), "claude")
        XCTAssertEqual(cliBinName("gemini-cli"), "gemini")
        XCTAssertEqual(cliBinName("aliyun-cli"), "aliyun")
    }

    func testNativeClaudeUsesItsOwnUpdaterAndNeverFallsBackToNpm() throws {
        let cli = try XCTUnwrap(pathCliInstallation(
            package: "@anthropic-ai/claude-code", binary: "/home/test/.local/bin/claude",
            resolved: "/home/test/.local/share/claude/versions/2.1.3", home: "/home/test", managers: [:]))
        XCTAssertEqual(cli.channel.rawValue, "native")
        XCTAssertEqual(cli.command.executable, "/home/test/.local/bin/claude")
        XCTAssertEqual(cli.command.arguments, ["update"])
        XCTAssertNil(pathCliInstallation(package: "@anthropic-ai/claude-code", binary: "/usr/local/bin/claude",
                                         resolved: "/opt/custom/claude", home: "/home/test", managers: [:]))
    }

    func testBunAndPnpmUpdateTheGlobalStoreThatOwnsTheExecutable() throws {
        let bun = try XCTUnwrap(pathCliInstallation(
            package: "@openai/codex", binary: "/home/test/.bun/bin/codex",
            resolved: "/home/test/.bun/install/global/node_modules/@openai/codex/bin/codex.js",
            home: "/home/test", managers: [.bun: "/home/test/.bun/bin/bun"]))
        XCTAssertEqual(bun.command.executable, "/home/test/.bun/bin/bun")
        XCTAssertEqual(bun.command.environment["BUN_INSTALL"], "/home/test/.bun")
        XCTAssertEqual(bun.prefix, "/home/test/.bun/install/global")
        let pnpm = try XCTUnwrap(pathCliInstallation(
            package: "@openai/codex", binary: "/home/test/Library/pnpm/codex",
            resolved: "/home/test/Library/pnpm/global/5/.pnpm/@openai+codex@0.100.0/node_modules/@openai/codex/bin/codex.js",
            home: "/home/test", managers: [.pnpm: "/home/test/Library/pnpm/pnpm"],
            pnpmGlobalRoot: "/home/test/Library/pnpm/global/5/node_modules"))
        XCTAssertEqual(pnpm.prefix, "/home/test/Library/pnpm/global/5")
        XCTAssertEqual(pnpm.command.arguments,
                       ["add", "--global", "--config.global-dir=/home/test/Library/pnpm/global",
                        "--config.global-bin-dir=/home/test/Library/pnpm", "@openai/codex@{version}"])
        XCTAssertNil(pathCliInstallation(package: "@openai/codex", binary: "/tmp/codex",
            resolved: "/project/node_modules/@openai/codex/bin/codex.js", home: "/home/test", managers: [:]))
    }

    func testPnpmShimKeepsItsReferencedStoreAndRejectsAmbiguousShellPaths() throws {
        let shim = "#!/bin/sh\n" + #"basedir=$(dirname "$(echo "$0" | sed -e 's,\\,/,g')")"# + "\n"
            + #"exec node "$basedir/global/4/node_modules/@openai/codex/bin/codex.js" "$@""# + "\n"
        let target = try XCTUnwrap(pnpmShimTarget(shim, binary: "/home/test/old-pnpm/codex", package: "@openai/codex"))
        XCTAssertEqual(target, "/home/test/old-pnpm/global/4/node_modules/@openai/codex/bin/codex.js")
        let installation = try XCTUnwrap(pathCliInstallation(package: "@openai/codex", binary: "/home/test/old-pnpm/codex",
            resolved: target, home: "/home/test", managers: [.pnpm: "/home/test/new-pnpm/pnpm"],
            pnpmGlobalRoot: "/home/test/old-pnpm/global/4/node_modules"))
        XCTAssertEqual(installation.prefix, "/home/test/old-pnpm/global/4")
        XCTAssertTrue(installation.command.arguments.contains("--config.global-dir=/home/test/old-pnpm/global"))
        XCTAssertNil(pathCliInstallation(package: "@openai/codex", binary: "/home/test/old-pnpm/codex",
            resolved: target, home: "/home/test", managers: [.pnpm: "/home/test/new-pnpm/pnpm"],
            pnpmGlobalRoot: "/home/test/old-pnpm/global/5/node_modules"), "A current manager must not migrate an older installation generation")
        XCTAssertNil(pathCliInstallation(package: "@openai/codex", binary: "/home/test/old-pnpm/codex",
            resolved: target, home: "/home/test", managers: [.pnpm: "/home/test/new-pnpm/pnpm"]), "Unknown manager layout is not safe to update")
        let custom = "#!/bin/sh\n" + #"exec node "/custom/pnpm/global/5/node_modules/@openai/codex/bin/codex.js" "$@""#
        XCTAssertEqual(pnpmShimTarget(custom, binary: "/bin/codex", package: "@openai/codex"),
                       "/custom/pnpm/global/5/node_modules/@openai/codex/bin/codex.js")
        XCTAssertNil(pnpmShimTarget(shim.replacingOccurrences(of: "$basedir/global", with: "$(pnpm root)/global"), binary: "/bin/codex", package: "@openai/codex"))
        XCTAssertNil(pnpmShimTarget(shim + #"exec node "/other/global/5/node_modules/@openai/codex/bin/codex.js" "$@""#, binary: "/bin/codex", package: "@openai/codex"))
    }

    func testVersionParsingHandlesActualAgentOutputs() {
        XCTAssertEqual(parseCliExecutableVersion("codex-cli 0.155.1\n"), "0.155.1")
        XCTAssertEqual(parseCliExecutableVersion("\u{1b}[1m2.1.284 (Claude Code)\u{1b}[0m"), "2.1.284")
        XCTAssertEqual(parseCliExecutableVersion("GitHub Copilot CLI 1.0.87-0.\n"), "1.0.87-0")
        XCTAssertNil(parseCliExecutableVersion("command not found"))
    }

    func testBrewVersionUsesTheCorrectFormulaOrCaskResponse() throws {
        let formula = Data("{\"versions\":{\"stable\":\"0.155.1\",\"head\":\"HEAD\"}}".utf8)
        let cask = Data("{\"version\":\"2.1.284\"}".utf8)
        XCTAssertEqual(parseBrewLatestVersion(formula, cask: false), "0.155.1")
        XCTAssertEqual(parseBrewLatestVersion(cask, cask: true), "2.1.284")
        XCTAssertNil(parseBrewLatestVersion(formula, cask: true))
        XCTAssertNil(parseBrewLatestVersion(Data("{\"version\":\"latest\"}".utf8), cask: true))
    }

    func testGenericNpmNameCannotImpersonateTheOfficialAgentPackage() {
        XCTAssertFalse(GlobalCli(name: "codex", installed: "1.0.0", latest: "2.0.0").safeRecognizedAgentUpdate)
        XCTAssertFalse(GlobalCli(name: "claude", installed: "1.0.0", latest: "2.0.0").safeRecognizedAgentUpdate)
        XCTAssertTrue(GlobalCli(name: "codex", installed: "1.0.0", latest: "2.0.0", channel: .brew).safeRecognizedAgentUpdate)
    }

    func testUpdateArgumentsArePassedLiterally() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("popskill-cli-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("updater's tool")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\"\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let result = runCliUpdateCommand(CliUpdateCommand(executable: executable.path,
            arguments: ["literal'; $(touch forbidden); `echo expanded`", "{version}"]), version: "1.2.3")
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.out, "literal'; $(touch forbidden); `echo expanded`\n1.2.3\n")
    }

    func testQueuedUpgradeRejectsExecutableAndUpdaterReplacement() {
        let original = GlobalCli(name: "@openai/codex", installed: "1.0.0", channel: .native,
            prefix: "/home/test/.local/bin", pathHit: "/home/test/.local/bin/codex",
            resolvedPath: "/home/test/.codex/packages/standalone/releases/1.0.0/codex",
            updateCommand: CliUpdateCommand(executable: "/home/test/.local/bin/codex", arguments: ["update"]))
        var replaced = original
        replaced.resolvedPath = "/opt/unrelated/codex"
        XCTAssertFalse(sameCliInstallation(replaced, as: original))
        replaced = original
        replaced.updateCommand = CliUpdateCommand(executable: "/tmp/codex", arguments: ["update"])
        XCTAssertFalse(sameCliInstallation(replaced, as: original))
    }
}
