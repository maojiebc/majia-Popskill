import Foundation

// npm 源与全局 CLI 巡检（v2.14）。
//
// 现实模型（以 @guandata/guanskill 为标本）：npm 包发布的是 CLI 本体（bin/），
// skill 目录是 CLI 的 install-skill 子命令在本机生成的——tarball 里根本没有 SKILL.md。
// 所以 npm 源的更新语义 = registry 最新版 vs 全局已装版，更新 = npm i -g；
// 绝不去动 store 里的技能目录（那是 install-skill 的产物，覆盖会打断 symlink 体系）。
//
// 全局 CLI 巡检（v2.20）：按前缀分别 `npm ls -g --prefix`，升级时打回同一前缀。
// 启动只查常用白名单；打开面板才扫全部。见 CliInventory.swift。

// ── 纯函数（单测覆盖，不碰网络/进程）─────────────────────

/// "npm:@guandata/guanskill" 或 npmjs.com 包页 URL → "@guandata/guanskill"；非 npm 源返回 nil
func npmPkgName(_ sourceUrl: String?) -> String? {
    guard let s = sourceUrl?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
    if s.hasPrefix("npm:") {
        let pkg = String(s.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        return pkg.isEmpty ? nil : pkg
    }
    if let r = s.range(of: "npmjs.com/package/") {
        // 截到查询串/锚点为止；scoped 包路径里的 @scope/name 原样保留。
        // 不用 split(...)[0]：用户粘贴裸 /package/ 或 /package/?tab 时，
        // 空切片会触发越界并直接崩溃。
        let tail = s[r.upperBound...]
        let end = tail.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? tail.endIndex
        let pkg = String(tail[..<end]).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return pkg.isEmpty ? nil : pkg
    }
    return nil
}

/// registry 最新版查询地址。scoped 包的 / 必须转 %2F（registry 的路径约定）
func npmRegistryLatestURL(_ pkg: String) -> URL? {
    let encoded = pkg.replacingOccurrences(of: "/", with: "%2F")
    return URL(string: "https://registry.npmjs.org/\(encoded)/latest")
}

/// registry /latest 响应 → 版本号
func parseNpmRegistryLatest(_ data: Data) -> String? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let v = obj["version"] as? String, !v.isEmpty else { return nil }
    return v
}

/// `npm ls -g --json --depth=0` 输出 → {包名: 版本}。
/// npm 在依赖树有问题时会非零退出但照样吐 JSON，所以只看能不能解析。
func parseNpmGlobalList(_ data: Data) -> [String: String] {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let deps = obj["dependencies"] as? [String: Any] else { return [:] }
    var out: [String: String] = [:]
    for (name, info) in deps {
        if let d = info as? [String: Any], let v = d["version"] as? String { out[name] = v }
    }
    return out
}

// ── npm 环境探测（一次探测，进程生命周期内缓存）──────────

enum NpmEnv {
    private static let lock = NSLock()
    // 全部读写都在下方 lock 临界区内——nonisolated(unsafe) 只是向编译器声明
    // 「互斥由我保证」，不是消音（v2.18 严格并发整改）
    nonisolated(unsafe) private static var cached: String??

    /// GUI app 的 PATH 只有 /usr/bin:/bin 一族，nvm / npm prefix ~/.local 都不在——
    /// 走一次 login shell 探测真实 PATH 里的 npm，探测结果（含「没有」）缓存。
    static func npmBin() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        let r = runProcess("/bin/zsh", ["-lc", "command -v npm"], timeout: 20)
        let path = r.status == 0 ? r.out.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        cached = path.isEmpty ? .some(nil) : path
        return cached ?? nil
    }

    /// 测试钩子：注入假 npm 路径 / 重置缓存
    static func _setForTest(_ v: String??) { lock.lock(); cached = v; lock.unlock() }
}

// ── StoreFS 扩展：网络与进程 ─────────────────────────────

extension StoreFS {
    /// registry 一次 HTTP 拿最新版（等价 github 源的 ls-remote HEAD）。
    /// URLSession 遵循系统代理；失败抛错——断网必须如实计入「检查失败」，不能装最新。
    /// 同步桥复用 httpGet（v2.18：ResultBox 化，消除 semaphore 超时后的回调竞态）
    func npmLatestVersion(_ pkg: String) throws -> String {
        guard let url = npmRegistryLatestURL(pkg) else {
            throw StoreError.resolveFailed(L("包名不合法：\(pkg)"))
        }
        let data: Data
        do { data = try httpGet(url, accept: "application/json") }
        catch { throw StoreError.resolveFailed(L("连不上 npm registry——检查网络后重试。")) }
        guard let v = parseNpmRegistryLatest(data) else {
            throw StoreError.resolveFailed(L("registry 响应异常：\(pkg)"))
        }
        return v
    }

    /// 全局已装版本。没装 npm / 没装这个包 → nil（不算错误：无从比较就不进更新雷达）
    func npmGlobalVersion(_ pkg: String) -> String? {
        npmInstallFact(pkg)?.version
    }

    /// 默认前缀的全量清单（兼容旧测试 / 单前缀路径）
    func npmGlobalList() -> [String: String] {
        npmGlobalList(prefix: nil)
    }

    func npmGlobalList(prefix: String?) -> [String: String] {
        guard NpmEnv.npmBin() != nil else { return [:] }
        let cmd: String
        if let prefix, !prefix.isEmpty {
            guard !prefix.contains("'") else { return [:] }
            cmd = "npm ls -g --prefix '\(prefix)' --json --depth=0 2>/dev/null"
        } else {
            cmd = "npm ls -g --json --depth=0 2>/dev/null"
        }
        let r = runProcess("/bin/zsh", ["-lc", cmd], timeout: 60)
        return parseNpmGlobalList(Data(r.out.utf8))
    }

    /// login shell 的 `npm prefix -g`，再并上 ~/.local 与 Homebrew 前缀（目录真实存在才收）
    func npmPrefixes() -> [String] {
        var defaultPrefix: String?
        if NpmEnv.npmBin() != nil {
            let r = runProcess("/bin/zsh", ["-lc", "npm prefix -g"], timeout: 20)
            if r.status == 0 {
                let p = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty { defaultPrefix = p }
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return candidateNpmPrefixes(home: home, defaultPrefix: defaultPrefix).filter(prefixHasNodeModules)
    }

    /// 这个包实际装在哪个前缀。优先 PATH 命中的那份。
    func npmInstallFact(_ pkg: String) -> (prefix: String, version: String)? {
        let prefixes = npmPrefixes()
        let hit = loginWhich(cliBinName(pkg))
        if let hit {
            if let prefix = prefixes.first(where: { pathHitsPrefix(hit, prefix: $0) }),
               let ver = npmGlobalList(prefix: prefix)[pkg] {
                return (prefix, ver)
            }
        }
        for prefix in prefixes {
            if let ver = npmGlobalList(prefix: prefix)[pkg] { return (prefix, ver) }
        }
        return nil
    }

    func loginWhich(_ bin: String) -> String? {
        guard !bin.contains("'"), !bin.contains(" ") else { return nil }
        let r = runProcess("/bin/zsh", ["-lc", "command -v '\(bin)'"], timeout: 15)
        guard r.status == 0 else { return nil }
        let path = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// npm i -g 升级到指定版本。prefix 非空时打回那一份，避免升错副本。
    func npmGlobalInstall(_ pkg: String, version: String, prefix: String? = nil) throws {
        guard NpmEnv.npmBin() != nil else {
            throw StoreError.resolveFailed(L("未检测到 npm——请先安装 Node.js。"))
        }
        // pkg 来自 npm ls 输出或已存 meta，版本来自 registry；仍拒绝空白/引号防注入
        guard !pkg.contains("'"), !pkg.contains(" "), !version.contains("'"), !version.contains(" ") else {
            throw StoreError.unsafeName("\(pkg)@\(version)")
        }
        if let prefix, prefix.contains("'") { throw StoreError.unsafeName(prefix) }
        let prefixFlag = prefix.map { " --prefix '\($0)'" } ?? ""
        let r = runProcess("/bin/zsh", ["-lc", "npm i -g\(prefixFlag) '\(pkg)@\(version)' 2>&1"], timeout: 300)
        guard r.status == 0 else {
            let tail = (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines).suffix(200)
            throw StoreError.resolveFailed(tail.isEmpty ? L("npm 安装失败") : L("npm 安装失败：\(String(tail))"))
        }
        if let prefix, let hit = loginWhich(cliBinName(pkg)), !pathHitsPrefix(hit, prefix: prefix) {
            throw StoreError.resolveFailed(L("已写入 \(abbrev(prefix))，但 PATH 仍命中 \(abbrev(hit))——命令行用的还是另一份"))
        }
    }

    /// npm 源 entry 的更新检查：registry vs 全局已装。
    /// 返回 nil = 已最新或全局根本没装（无从比较）；网络失败如实抛。
    func checkNpmUpdate(_ entry: Entry) throws -> UpdateCheck? {
        guard let pkg = npmPkgName(entry.sourceUrl) else { return nil }
        // 先查本地（无网络开销）：没装全局 CLI 就没有「CLI 更新」这回事
        guard let installed = npmGlobalVersion(pkg) else {
            if loadMeta().entries[entry.id]?.latest != nil { saveLatest(entry.id, latest: nil) }
            return nil
        }
        let latest = try npmLatestVersion(pkg)
        saveCheckpoint(entry.id, head: latest, localDigest: localDigest(entry))
        guard latest != installed else {
            if loadMeta().entries[entry.id]?.latest != nil { saveLatest(entry.id, latest: nil) }
            return nil
        }
        // npm 的上游状态指纹 = registry 版本号本身（跳过 1.2.3，出 1.2.4 自动重亮）
        if skipSuppressed(entry.id, fingerprint: latest) { return nil }
        return UpdateCheck(entryId: entry.id, latest: "CLI v\(latest)", changedMembers: [],
                           upstreamNew: [], fingerprint: latest)
    }

    func pypiLatestVersion(_ name: String) throws -> String {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://pypi.org/pypi/\(encoded)/json") else {
            throw StoreError.resolveFailed(L("包名不合法：\(name)"))
        }
        let data: Data
        do { data = try httpGet(url, accept: "application/json") }
        catch { throw StoreError.resolveFailed(L("连不上 PyPI——检查网络后重试。")) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = obj["info"] as? [String: Any],
              let v = info["version"] as? String, !v.isEmpty else {
            throw StoreError.resolveFailed(L("PyPI 响应异常：\(name)"))
        }
        return v
    }

    /// npm 源 entry 的更新执行：升级全局 CLI，不碰 store 技能目录。
    /// 返回值对齐 applyUpdate 形状（updated = 包名）。
    func applyNpmUpdate(_ entry: Entry) throws -> (updated: [String], upstreamNew: [String]) {
        guard let pkg = npmPkgName(entry.sourceUrl) else {
            throw StoreError.resolveFailed(L("该源没有记录 npm 包名，无法更新"))
        }
        let latest = try npmLatestVersion(pkg)
        try npmGlobalInstall(pkg, version: latest, prefix: npmInstallFact(pkg)?.prefix)
        saveLatest(entry.id, latest: nil)
        saveCheckpoint(entry.id, head: latest, localDigest: localDigest(entry))
        return (updated: [pkg], upstreamNew: [])
    }

    /// 扫本机维护型 CLI。full=false 只查白名单（启动 / 检查更新默认）。
    func scanMaintainedClis(extraNpm: Set<String> = [], full: Bool = false, checkVersions: Bool = true) -> [GlobalCli] {
        var out: [GlobalCli] = []
        out += scanNpmClis(extra: extraNpm, full: full)
        out += scanBrewClis(checkVersions: checkVersions)
        out += scanPipxClis()
        out += scanUvClis()
        return out.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func scanNpmClis(extra: Set<String>, full: Bool) -> [GlobalCli] {
        let prefixes = npmPrefixes()
        guard !prefixes.isEmpty else { return [] }
        let wanted = Set(maintainedNpmPackages.keys).union(extra)
        var rows: [GlobalCli] = []
        for prefix in prefixes {
            let installed = npmGlobalList(prefix: prefix)
            let names = full ? Set(installed.keys) : Set(installed.keys).intersection(wanted)
            for pkg in names.sorted() {
                let ver = installed[pkg] ?? ""
                let bin = cliBinName(pkg)
                let hit = loginWhich(bin)
                let allow = maintainedNpmPackages[pkg] != nil || extra.contains(pkg)
                rows.append(GlobalCli(
                    name: pkg, installed: ver, latest: nil,
                    displayName: pkg, channel: .npm, prefix: prefix,
                    pathHit: hit,
                    pathMatchesPrefix: hit.map { pathHitsPrefix($0, prefix: prefix) } ?? true,
                    excluded: isFoundationTool(pkg),
                    allowlisted: allow
                ))
            }
        }
        return rows
    }

    private func scanBrewClis(checkVersions: Bool) -> [GlobalCli] {
        let brew = loginWhich("brew")
        guard brew != nil else { return [] }
        var installed: [String: String] = [:]
        for formula in maintainedBrewFormulae {
            guard !formula.contains("'") else { continue }
            let r = runProcess("/bin/zsh", ["-lc", "brew list --versions '\(formula)'"], timeout: 20)
            guard r.status == 0 else { continue }
            let parts = r.out.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if parts.count >= 2 { installed[formula] = parts[1] }
        }
        guard !installed.isEmpty else { return [] }
        var latestByName: [String: String] = [:]
        let outdated = checkVersions ? runProcess("/bin/zsh", ["-lc", "HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 brew outdated --json=v2"], timeout: 40) : (status: Int32(-1), out: "", err: "")
        if outdated.status == 0 {
            for row in parseBrewOutdated(Data(outdated.out.utf8)) {
                latestByName[row.name] = row.latest
            }
        }
        return installed.keys.sorted().map { name in
            let ver = installed[name] ?? ""
            return GlobalCli(
                name: name, installed: ver, latest: outdated.status == 0 ? (latestByName[name] ?? ver) : nil,
                displayName: name, channel: .brew,
                excluded: isFoundationTool(name), allowlisted: true
            )
        }
    }

    private func scanPipxClis() -> [GlobalCli] {
        guard loginWhich("pipx") != nil else { return [] }
        let r = runProcess("/bin/zsh", ["-lc", "pipx list --json"], timeout: 30)
        guard r.status == 0 else { return [] }
        let installed = parsePipxList(Data(r.out.utf8))
        return maintainedPipxPackages.compactMap { name in
            guard let pkg = installed[name] else { return nil }
            let tracks = pipxTracksIndex(pkg.packageOrUrl)
            return GlobalCli(name: name, installed: pkg.version, latest: tracks ? nil : pkg.version,
                             displayName: name, channel: .pipx, allowlisted: true, tracksIndex: tracks)
        }
    }

    private func scanUvClis() -> [GlobalCli] {
        guard loginWhich("uv") != nil else { return [] }
        let r = runProcess("/bin/zsh", ["-lc", "uv tool list"], timeout: 20)
        guard r.status == 0 else { return [] }
        var out: [GlobalCli] = []
        for line in r.out.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2 else { continue }
            let name = parts[0]
            guard maintainedUvTools.contains(name) else { continue }
            let ver = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            out.append(GlobalCli(name: name, installed: ver, displayName: name,
                                 channel: .uv, allowlisted: true))
        }
        return out
    }

    func upgradeMaintainedCli(_ cli: GlobalCli) throws {
        guard !cli.excluded else {
            throw StoreError.resolveFailed(L("\(cli.name) 是基础工具，不在一键升级范围"))
        }
        guard let latest = cli.latest, latest != cli.installed else { return }
        switch cli.channel {
        case .npm:
            try npmGlobalInstall(cli.name, version: latest, prefix: cli.prefix)
        case .brew:
            guard !cli.name.contains("'") else { throw StoreError.unsafeName(cli.name) }
            let r = runProcess("/bin/zsh", ["-lc", "brew upgrade '\(cli.name)' 2>&1"], timeout: 300)
            guard r.status == 0 else {
                throw StoreError.resolveFailed(L("brew 升级失败：\(String((r.out + r.err).suffix(160)))"))
            }
        case .pipx:
            guard !cli.name.contains("'") else { throw StoreError.unsafeName(cli.name) }
            let r = runProcess("/bin/zsh", ["-lc", "pipx upgrade '\(cli.name)' 2>&1"], timeout: 300)
            guard r.status == 0 else {
                throw StoreError.resolveFailed(L("pipx 升级失败：\(String((r.out + r.err).suffix(160)))"))
            }
        case .uv:
            guard !cli.name.contains("'") else { throw StoreError.unsafeName(cli.name) }
            let r = runProcess("/bin/zsh", ["-lc", "uv tool upgrade '\(cli.name)' 2>&1"], timeout: 300)
            guard r.status == 0 else {
                throw StoreError.resolveFailed(L("uv 升级失败：\(String((r.out + r.err).suffix(160)))"))
            }
        }
    }
}
