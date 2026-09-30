import Foundation

/// Inspired by Magpie's installation-aware updater. Keep the installation's
/// executable and manager in the plan so queue preflight can verify both.
struct CliUpdateCommand: Equatable, Sendable {
    let executable: String
    var arguments: [String]
    var environment: [String: String] = [:]

    func arguments(version: String) -> [String] {
        arguments.map { $0.replacingOccurrences(of: "{version}", with: version) }
    }
    var display: String {
        ([executable] + arguments).map(cliShellQuote).joined(separator: " ")
    }
}

struct PathCliInstallation: Equatable, Sendable {
    let channel: CliChannel
    let prefix: String
    let command: CliUpdateCommand
}

func cliShellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// A login shell supplies the Node/runtime PATH used by the user's actual CLI.
/// Every argument remains literal; no installer script or untrusted command is evaluated.
func runCliUpdateCommand(_ command: CliUpdateCommand, version: String, timeout: TimeInterval = 300)
    -> (status: Int32, out: String, err: String) {
    let env = command.environment.keys.sorted().map { "\($0)=\(command.environment[$0]!)" }
    let parts = ["/usr/bin/env"] + env + [command.executable] + command.arguments(version: version)
    return runProcess("/bin/zsh", ["-lc", "exec " + parts.map(cliShellQuote).joined(separator: " ")], timeout: timeout)
}

func parseCliExecutableVersion(_ text: String) -> String? {
    let ansi = text.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression)
    guard let expression = try? NSRegularExpression(pattern: "(?:^|[^A-Za-z0-9.])v?([0-9]+\\.[0-9]+(?:\\.[0-9]+)*(?:-[0-9A-Za-z][0-9A-Za-z.]*)?)"),
          let match = expression.firstMatch(in: ansi, range: NSRange(ansi.startIndex..., in: ansi)),
          let range = Range(match.range(at: 1), in: ansi) else { return nil }
    return String(ansi[range]).trimmingCharacters(in: CharacterSet(charactersIn: "."))
}

func parseBrewLatestVersion(_ data: Data, cask: Bool) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let version = cask ? json["version"] as? String : (json["versions"] as? [String: Any])?["stable"] as? String
    guard let version, !cliVersionComponents(version).isEmpty else { return nil }
    return version
}

/// Read pnpm's standard shim as data. Never run it to infer ownership or ask
/// the current pnpm default root: an older shim may point at a different store.
func pnpmShimTarget(_ shim: String, binary: String, package: String) -> String? {
    guard shim.hasPrefix("#!/bin/sh\n"),
          let quotes = try? NSRegularExpression(pattern: #"["']([^"'\n]+)["']"#) else { return nil }
    let lines = shim.components(separatedBy: .newlines)
    let usesBinaryDirectory = lines.contains(#"basedir=$(dirname "$(echo "$0" | sed -e 's,\\,/,g')")"#)
        || lines.contains(#"basedir=$(dirname "$0")"#)
    let parent = URL(fileURLWithPath: binary).deletingLastPathComponent().path
    var targets = Set<String>()
    for line in lines where line.trimmingCharacters(in: .whitespaces).hasPrefix("exec ") {
        for match in quotes.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            guard let range = Range(match.range(at: 1), in: line) else { continue }
            var target = String(line[range])
            guard target.contains("/node_modules/" + package + "/") else { continue }
            if target.hasPrefix("$basedir/") || target.hasPrefix("${basedir}/") {
                guard usesBinaryDirectory else { return nil }
                target = parent + target.dropFirst(target.hasPrefix("$basedir/") ? 8 : 10)
            }
            guard target.hasPrefix("/"), !target.contains("$"), !target.contains("`"), !target.contains("\\") else { return nil }
            targets.insert(URL(fileURLWithPath: target).standardizedFileURL.resolvingSymlinksInPath().path)
        }
    }
    return targets.count == 1 ? targets.first : nil
}

func pnpmInstallationRoot(package: String, resolved: String) -> String? {
    guard let mark = resolved.range(of: "/node_modules/" + package + "/", options: .backwards) else { return nil }
    let store = String(resolved[..<mark.lowerBound])
    guard let global = store.range(of: "/global/") else { return nil }
    let generation = store[global.upperBound...].split(separator: "/").first.map(String.init) ?? ""
    guard !generation.isEmpty, generation.allSatisfy(\.isNumber) else { return nil }
    return String(store[...global.lowerBound]) + "global/" + generation
}

func pnpmGlobalRootCommand(manager: String, installationRoot: String, binary: String) -> CliUpdateCommand {
    let configuredRoot = URL(fileURLWithPath: installationRoot).deletingLastPathComponent().path
    let binFolder = URL(fileURLWithPath: binary).deletingLastPathComponent().path
    return CliUpdateCommand(executable: manager,
        arguments: ["root", "--global", "--config.global-dir=" + configuredRoot, "--config.global-bin-dir=" + binFolder])
}

/// Recognition requires the actual target, never just a friendly binary name.
/// Unknown/manual/project installations remain visible with no update action.
func pathCliInstallation(package: String, binary: String, resolved: String, home: String,
                         managers: [CliChannel: String], pnpmGlobalRoot: String? = nil) -> PathCliInstallation? {
    let binFolder = URL(fileURLWithPath: binary).deletingLastPathComponent().path
    let nativeRoot: String?
    let verb: String
    switch package {
    case "@anthropic-ai/claude-code": nativeRoot = home + "/.local/share/claude/versions/"; verb = "update"
    case "@openai/codex": nativeRoot = home + "/.codex/packages/standalone/"; verb = "update"
    case "opencode-ai": nativeRoot = home + "/.opencode/bin/"; verb = "upgrade"
    case "magpie":
        nativeRoot = (resolved == home + "/.local/bin/magpie" || resolved == "/Applications/magpie.app/Contents/MacOS/magpie") ? resolved : nil
        verb = "update"
    default: nativeRoot = nil; verb = ""
    }
    if let nativeRoot, resolved.hasPrefix(nativeRoot) {
        return PathCliInstallation(channel: .native, prefix: binFolder,
            command: CliUpdateCommand(executable: binary, arguments: [verb]))
    }
    guard let mark = resolved.range(of: "/node_modules/" + package + "/", options: .backwards) else { return nil }
    let store = String(resolved[..<mark.lowerBound])
    if store.hasSuffix("/install/global"), let manager = managers[.bun] {
        let bunRoot = String(store.dropLast("/install/global".count))
        return PathCliInstallation(channel: .bun, prefix: store,
            command: CliUpdateCommand(executable: manager, arguments: ["add", "--global", package + "@{version}"],
                                      environment: ["BUN_INSTALL": bunRoot]))
    }
    if let root = pnpmInstallationRoot(package: package, resolved: resolved), let manager = managers[.pnpm] {
        // pnpm appends its own layout generation to --global-dir. Refuse to
        // migrate an old generation or update a manager's different global store.
        guard let pnpmGlobalRoot,
              URL(fileURLWithPath: pnpmGlobalRoot).resolvingSymlinksInPath().path == root + "/node_modules" else { return nil }
        let configuredRoot = URL(fileURLWithPath: root).deletingLastPathComponent().path
        return PathCliInstallation(channel: .pnpm, prefix: root,
            command: CliUpdateCommand(executable: manager,
                arguments: ["add", "--global", "--config.global-dir=" + configuredRoot,
                            "--config.global-bin-dir=" + binFolder, package + "@{version}"]))
    }
    return nil
}

extension StoreFS {
    func scanPathClis(known: [GlobalCli]) -> [GlobalCli] {
        let home = fm.homeDirectoryForCurrentUser.path
        var managers: [CliChannel: String] = [:]
        if let bin = loginWhich("bun") { managers[.bun] = bin }
        if let bin = loginWhich("pnpm") { managers[.pnpm] = bin }
        var specifications = maintainedNpmPackages
        specifications["magpie"] = "magpie"
        var handled = Set<String>()
        var out: [GlobalCli] = []
        // Prefer the current Pi package when old and new aliases share one binary.
        for package in specifications.keys.sorted() {
            let bin = specifications[package]!
            guard !handled.contains(bin), let hit = loginWhich(bin), hit.hasPrefix("/"), fm.isExecutableFile(atPath: hit) else { continue }
            if known.contains(where: { $0.pathHit == hit && $0.pathMatchesPrefix }) { handled.insert(bin); continue }
            var resolved = URL(fileURLWithPath: hit).resolvingSymlinksInPath().path
            if specifications.contains(where: { $0.value == bin && $0.key != package && resolved.contains("/node_modules/" + $0.key + "/") }) { continue }
            // pnpm emits small shell shims rather than a symlink. Preserve the
            // package path referenced by that shim, including custom/old stores.
            if resolved == hit, managers[.pnpm] != nil,
               let size = (try? fm.attributesOfItem(atPath: hit)[.size]) as? NSNumber, size.intValue < 65_536,
               let shim = try? String(contentsOfFile: hit), let target = pnpmShimTarget(shim, binary: hit, package: package),
               fm.fileExists(atPath: target) {
                resolved = target
            }
            var pnpmGlobalRoot: String?
            if let manager = managers[.pnpm], let root = pnpmInstallationRoot(package: package, resolved: resolved) {
                let result = runCliUpdateCommand(pnpmGlobalRootCommand(manager: manager, installationRoot: root, binary: hit), version: "", timeout: 15)
                let reported = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.status == 0, reported.hasPrefix("/"), !reported.contains("\n") { pnpmGlobalRoot = reported }
            }
            guard let installation = pathCliInstallation(package: package, binary: hit, resolved: resolved, home: home,
                                                        managers: managers, pnpmGlobalRoot: pnpmGlobalRoot) else {
                let r = runCliUpdateCommand(CliUpdateCommand(executable: hit, arguments: ["--version"]), version: "", timeout: 10)
                out.append(GlobalCli(name: package, installed: parseCliExecutableVersion(r.out) ?? "—",
                    displayName: bin, channel: .unmanaged, pathHit: hit, tracksIndex: false, resolvedPath: resolved))
                handled.insert(bin)
                continue
            }
            let r = runCliUpdateCommand(CliUpdateCommand(executable: hit, arguments: ["--version"]), version: "", timeout: 10)
            let version = r.status == 0 ? parseCliExecutableVersion(r.out) : nil
            out.append(GlobalCli(name: package, installed: version ?? "—", displayName: bin,
                channel: installation.channel, prefix: installation.prefix, pathHit: hit,
                allowlisted: true, tracksIndex: version != nil, resolvedPath: resolved, updateCommand: installation.command))
            handled.insert(bin)
        }
        return out
    }

    func latestPathCliVersion(_ cli: GlobalCli) throws -> String {
        if cli.name != "magpie" { return try npmLatestVersion(cli.name) }
        let url = URL(string: "https://api.github.com/repos/yetone/magpie-releases/releases/latest")!
        let data = try httpGet(url, accept: "application/json")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, let version = parseCliExecutableVersion(tag) else {
            throw StoreError.resolveFailed(L("无法确认最新版本，请稍后重试。"))
        }
        return version
    }

    func brewLatestVersion(_ name: String, cask: Bool) throws -> String {
        guard maintainedBrewFormulae.contains(name), let url = URL(string:
            "https://formulae.brew.sh/api/\(cask ? "cask" : "formula")/\(name).json") else {
            throw StoreError.unsafeName(name)
        }
        let data = try httpGet(url, accept: "application/json")
        guard let version = parseBrewLatestVersion(data, cask: cask) else {
            throw StoreError.resolveFailed(L("Homebrew 检查失败，请重试。"))
        }
        return version
    }
}
