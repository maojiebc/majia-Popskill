import Foundation

// npm 源与全局 CLI 巡检（v2.14）。
//
// 现实模型（以 @guandata/guanskill 为标本）：npm 包发布的是 CLI 本体（bin/），
// skill 目录是 CLI 的 install-skill 子命令在本机生成的——tarball 里根本没有 SKILL.md。
// 所以 npm 源的更新语义 = registry 最新版 vs 全局已装版，更新 = npm i -g；
// 绝不去动 store 里的技能目录（那是 install-skill 的产物，覆盖会打断 symlink 体系）。
//
// 全局 CLI 巡检：npm ls -g 一次拿全部全局包（claude-code / lark-cli / getnote 们），
// 逐包比 registry——用户装的 CLI 从此进 Popskill 的更新雷达（吸收 cc-switch 工具版本矩阵）。

// ── 纯函数（单测覆盖，不碰网络/进程）─────────────────────

/// "npm:@guandata/guanskill" → "@guandata/guanskill"；非 npm 源返回 nil
func npmPkgName(_ sourceUrl: String?) -> String? {
    guard let s = sourceUrl?.trimmingCharacters(in: .whitespaces).lowercased(),
          s.hasPrefix("npm:") else { return nil }
    let pkg = String(s.dropFirst(4)).trimmingCharacters(in: .whitespaces)
    return pkg.isEmpty ? nil : pkg
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

// ── 全局 CLI 巡检模型 ────────────────────────────────────

struct GlobalCli: Identifiable, Equatable {
    let name: String        // npm 包名（@scope/pkg）
    let installed: String
    var latest: String?     // nil = registry 没查到（网络失败等），不算可升级
    var id: String { name }
    var hasUpdate: Bool { latest != nil && latest != installed }
}

// ── npm 环境探测（一次探测，进程生命周期内缓存）──────────

enum NpmEnv {
    private static let lock = NSLock()
    private static var cached: String??

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
    func npmLatestVersion(_ pkg: String) throws -> String {
        guard let url = npmRegistryLatestURL(pkg) else {
            throw StoreError.resolveFailed(L("包名不合法：\(pkg)"))
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(URLError(.unknown))
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err { result = .failure(err); return }
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                result = .failure(URLError(.badServerResponse)); return
            }
            result = .success(data)
        }.resume()
        _ = sem.wait(timeout: .now() + 25)
        switch result {
        case .success(let data):
            guard let v = parseNpmRegistryLatest(data) else {
                throw StoreError.resolveFailed(L("registry 响应异常：\(pkg)"))
            }
            return v
        case .failure:
            throw StoreError.resolveFailed(L("连不上 npm registry——检查网络后重试。"))
        }
    }

    /// 全局已装版本。没装 npm / 没装这个包 → nil（不算错误：无从比较就不进更新雷达）
    func npmGlobalVersion(_ pkg: String) -> String? {
        npmGlobalList()[pkg]
    }

    /// 全局包全量清单（CLI 巡检入口）。npm ls 依赖树报错时仍吐 JSON，照常解析
    func npmGlobalList() -> [String: String] {
        guard NpmEnv.npmBin() != nil else { return [:] }
        let r = runProcess("/bin/zsh", ["-lc", "npm ls -g --json --depth=0 2>/dev/null"], timeout: 60)
        return parseNpmGlobalList(Data(r.out.utf8))
    }

    /// npm i -g 升级到指定版本。走 login shell 继承 node 环境；失败抛人话
    func npmGlobalInstall(_ pkg: String, version: String) throws {
        guard NpmEnv.npmBin() != nil else {
            throw StoreError.resolveFailed(L("未检测到 npm——请先安装 Node.js。"))
        }
        // pkg 来自 npm ls 输出或已存 meta，版本来自 registry；仍拒绝空白/引号防注入
        guard !pkg.contains("'"), !pkg.contains(" "), !version.contains("'"), !version.contains(" ") else {
            throw StoreError.unsafeName("\(pkg)@\(version)")
        }
        let r = runProcess("/bin/zsh", ["-lc", "npm i -g '\(pkg)@\(version)' 2>&1"], timeout: 300)
        guard r.status == 0 else {
            let tail = (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines).suffix(200)
            throw StoreError.resolveFailed(tail.isEmpty ? L("npm 安装失败") : L("npm 安装失败：\(String(tail))"))
        }
    }

    /// npm 源 entry 的更新检查：registry vs 全局已装。
    /// 返回 nil = 已最新或全局根本没装（无从比较）；网络失败如实抛。
    func checkNpmUpdate(_ entry: Entry) throws -> UpdateCheck? {
        guard let pkg = npmPkgName(entry.sourceUrl) else { return nil }
        // 先查本地（无网络开销）：没装全局 CLI 就没有「CLI 更新」这回事
        guard let installed = npmGlobalVersion(pkg) else {
            if loadMeta().entries[entry.name]?.latest != nil { saveLatest(entry.name, latest: nil) }
            return nil
        }
        let latest = try npmLatestVersion(pkg)
        saveCheckpoint(entry.name, head: latest, localDigest: localDigest(entry))
        guard latest != installed else {
            if loadMeta().entries[entry.name]?.latest != nil { saveLatest(entry.name, latest: nil) }
            return nil
        }
        return UpdateCheck(entryId: entry.id, latest: "CLI v\(latest)", changedMembers: [], upstreamNew: [])
    }

    /// npm 源 entry 的更新执行：升级全局 CLI，不碰 store 技能目录。
    /// 返回值对齐 applyUpdate 形状（updated = 包名）。
    func applyNpmUpdate(_ entry: Entry) throws -> (updated: [String], upstreamNew: [String]) {
        guard let pkg = npmPkgName(entry.sourceUrl) else {
            throw StoreError.resolveFailed(L("该源没有记录 npm 包名，无法更新"))
        }
        let latest = try npmLatestVersion(pkg)
        try npmGlobalInstall(pkg, version: latest)
        saveLatest(entry.name, latest: nil)
        saveCheckpoint(entry.name, head: latest, localDigest: localDigest(entry))
        return (updated: [pkg], upstreamNew: [])
    }
}
