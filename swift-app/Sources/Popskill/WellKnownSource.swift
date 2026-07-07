import CryptoKit
import Foundation

// well-known 源（v2.14）：skills.sh 生态的单文件分发协议——
// https://<host>/.well-known/skills/<name>/SKILL.md（lark 系 24 个技能都是这么装的）。
//
// 之前这类源被 normalizeSource 截断成 "open.feishu.cn/.well-known/skills" 当 github 源，
// 套装名显示成 ".well-known/skills"，checkUpdate 去 clone 必失败——手动检查永远
// 「1 个源检查失败」。现在：归拢键 = "wk:<host>"，更新检查 = 逐成员 GET SKILL.md 比内容。
//
// 已知局限（刻意）：well-known 协议只分发 SKILL.md 单文件，成员目录里的 references/
// 附属文件不在协议内——比对与更新都只针对 SKILL.md，注释写在这，别当 bug 修。

/// "https://open.feishu.cn/.well-known/skills/lark-doc/SKILL.md" → "open.feishu.cn"。
/// 非 well-known 形态返回 nil
func wellKnownHost(_ raw: String) -> String? {
    var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
    for p in ["https://", "http://"] where s.hasPrefix(p) { s.removeFirst(p.count) }
    guard let r = s.range(of: "/.well-known/skills/") else { return nil }
    let host = String(s[..<r.lowerBound])
    return host.isEmpty || host.contains("/") ? nil : host
}

/// well-known 源成员的 SKILL.md 下载地址（路径即协议约定，成员名可重建，无需存子路径）
func wellKnownSkillURL(host: String, name: String) -> URL? {
    URL(string: "https://\(host)/.well-known/skills/\(name)/SKILL.md")
}

/// ".../.well-known/skills/<name>/SKILL.md"（或 /<name>/）→ "<name>"
func wellKnownSkillName(_ raw: String) -> String? {
    let s = raw.trimmingCharacters(in: .whitespaces)
    guard let r = s.range(of: "/.well-known/skills/") else { return nil }
    let tail = s[r.upperBound...]
    let name = tail.split(separator: "/").first.map(String.init) ?? ""
    return name.isEmpty ? nil : name
}

/// 同步 GET（走系统代理）。调用方都在后台线程（checkUpdate/applyUpdate 的 Task.detached 世界）
func httpGet(_ url: URL, timeout: TimeInterval = 20) throws -> Data {
    var req = URLRequest(url: url, timeoutInterval: timeout)
    req.httpMethod = "GET"   // 部分 CDN（Tengine）对 HEAD 返回 404，别用 HEAD 探测
    let sem = DispatchSemaphore(value: 0)
    var result: Result<Data, Error> = .failure(URLError(.timedOut))
    URLSession.shared.dataTask(with: req) { data, resp, err in
        defer { sem.signal() }
        if let err { result = .failure(err); return }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
            result = .failure(URLError(.badServerResponse)); return
        }
        result = .success(data)
    }.resume()
    _ = sem.wait(timeout: .now() + timeout + 5)
    return try result.get()
}

extension StoreFS {
    /// well-known 源更新检查：逐成员 GET SKILL.md，与本地 SKILL.md 比内容哈希。
    /// 单个成员网络失败不吞——记为失败让整源如实报错，别把「没查到」当「没更新」
    func checkWellKnownUpdate(_ entry: Entry, host: String) throws -> UpdateCheck? {
        let members = entry.isBundle ? (entry.children ?? []) : [entry.cap]
        var changed: [String] = []
        var changedPairs: [(name: String, hash: String)] = []
        var failures = 0
        for cap in members where !isSymlink(cap.dirURL) {
            guard let url = wellKnownSkillURL(host: host, name: cap.name) else { continue }
            let localFile = cap.dirURL.appendingPathComponent("SKILL.md")
            guard let local = try? Data(contentsOf: localFile) else { continue }
            do {
                let remote = try httpGet(url)
                let remoteHash = SHA256.hash(data: remote)
                if remoteHash != SHA256.hash(data: local) {
                    changed.append(cap.name)
                    changedPairs.append((cap.name, remoteHash.map { String(format: "%02x", $0) }.joined()))
                }
            } catch {
                failures += 1
            }
        }
        if failures > 0 && changed.isEmpty {
            throw StoreError.resolveFailed(L("\(failures) 个成员的 SKILL.md 拉取失败（\(host)）"))
        }
        guard !changed.isEmpty else {
            if loadMeta().entries[entry.name]?.latest != nil { saveLatest(entry.name, latest: nil) }
            return nil
        }
        // 上游状态指纹 = 变化成员的远端内容组合哈希（协议无版本概念，内容即身份）
        let fingerprint = combinedFingerprint(changedPairs)
        if skipSuppressed(entry.name, fingerprint: fingerprint) { return nil }
        return UpdateCheck(entryId: entry.id,
                           latest: changed.count == 1 && members.count == 1 ? L("新版") : L("\(changed.count) 项"),
                           changedMembers: changed, upstreamNew: [], fingerprint: fingerprint)
    }

    /// well-known 源更新执行：只换有变化成员的 SKILL.md（旧文件备份进回收站），
    /// references/ 等附属文件原样保留——协议只分发单文件
    func applyWellKnownUpdate(_ entry: Entry, host: String) throws -> (updated: [String], upstreamNew: [String]) {
        let members = entry.isBundle ? (entry.children ?? []) : [entry.cap]
        var updated: [String] = []
        for cap in members where !isSymlink(cap.dirURL) {
            guard let url = wellKnownSkillURL(host: host, name: cap.name) else { continue }
            let localFile = cap.dirURL.appendingPathComponent("SKILL.md")
            guard let local = try? Data(contentsOf: localFile) else { continue }
            let remote = try httpGet(url)
            guard SHA256.hash(data: remote) != SHA256.hash(data: local) else { continue }
            // 原子换文件：先落临时名，成功后备份旧文件再换名——失败旧版无损
            let incoming = cap.dirURL.appendingPathComponent(".popskill-incoming-SKILL.md")
            try? fm.removeItem(at: incoming)
            do { try remote.write(to: incoming) }
            catch { try? fm.removeItem(at: incoming); throw error }
            let backupDir = try moveToTrash(localFile)
            do { try fm.moveItem(at: incoming, to: localFile) }
            catch {
                try? fm.moveItem(at: backupDir, to: localFile)
                throw error
            }
            updated.append(cap.name)
        }
        saveLatest(entry.name, latest: nil)
        return (updated: updated, upstreamNew: [])
    }
}
