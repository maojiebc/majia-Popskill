import XCTest
@testable import Popskill

/// 真实环境只读冒烟（POPSKILL_REAL_SMOKE=1 才跑）：扫真 ~/.agents 验证来源回填与归拢，零写入。
final class RealEnvSmoke: XCTestCase {
    func testScanRealEnvironmentReadOnly() throws {
        guard ProcessInfo.processInfo.environment["POPSKILL_REAL_SMOKE"] == "1" else {
            throw XCTSkip("仅手动触发")
        }
        let fs = StoreFS(env: .real())
        let meta = fs.loadMeta()
        let tools = fs.scanTools(meta: meta)
        let entries = fs.scanEntries(tools: tools, meta: meta)
        print("== 条目总数: \(entries.count)")
        for e in entries where e.isBundle {
            print("== 套装[\(e.bundleKind == .source ? "源式" : "目录")] \(e.name): \(e.children?.count ?? 0) 项 · src=\(e.sourceUrl ?? "-")")
        }
        let sourced = entries.filter { $0.sourceUrl != nil }
        print("== 有来源条目: \(sourced.count)/\(entries.count)")
        for e in entries where !e.isBundle && e.sourceUrl != nil {
            print("   · \(e.name) ← \(e.sourceUrl!)")
        }
        XCTAssertFalse(entries.isEmpty)
    }
}

/// 文件系统引擎测试 — 全部在临时目录沙盘里跑，不碰真实 ~/.agents。
final class StoreFSTests: XCTestCase {
    var sandbox: URL!
    var env: StoreEnv!
    var fs: StoreFS!
    let fm = FileManager.default

    override func setUpWithError() throws {
        sandbox = fm.temporaryDirectory.appendingPathComponent("popskill-test-\(UUID().uuidString.prefix(8))")
        let store = sandbox.appendingPathComponent("agents")
        env = StoreEnv(storeRoot: store, toolRoots: [
            "claude": sandbox.appendingPathComponent("claude"),
            "codex": sandbox.appendingPathComponent("codex"),
        ])
        fs = StoreFS(env: env)
        try fm.createDirectory(at: store.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try fm.createDirectory(at: env.toolRoots["claude"]!.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try fm.createDirectory(at: env.toolRoots["codex"]!.appendingPathComponent("skills"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: sandbox)
    }

    // ── 造数据 ───────────────────────────────────────────

    @discardableResult
    func makeSkill(_ name: String, desc: String = "测试技能", version: String? = "1.0.0", in parent: URL? = nil) throws -> URL {
        let dir = (parent ?? env.storeRoot.appendingPathComponent("skills")).appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var front = "---\nname: \(name)\ndescription: \(desc)\n"
        if let version { front += "version: \(version)\n" }
        front += "---\n\n# \(name)\n"
        try front.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return dir
    }

    @discardableResult
    func makeBundle(_ name: String, children: [String]) throws -> URL {
        let dir = env.storeRoot.appendingPathComponent("skills").appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for c in children { try makeSkill(c, in: dir) }
        return dir
    }

    var tools: [Tool] { fs.scanTools(meta: StoreMeta()) }
    func scan() -> [Entry] { fs.scanEntries(tools: tools, meta: fs.loadMeta()) }
    func claudeLink(_ name: String) -> URL { env.toolRoots["claude"]!.appendingPathComponent("skills").appendingPathComponent(name) }

    // ── 扫描 ─────────────────────────────────────────────

    func testScanStandaloneSkill() throws {
        try makeSkill("foo", desc: "一个技能")
        let entries = scan()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "foo")
        XCTAssertFalse(entries[0].isBundle)
        XCTAssertEqual(entries[0].cap.desc, "一个技能")
        XCTAssertEqual(entries[0].cap.version, "1.0.0")
        XCTAssertEqual(entries[0].cap.status("claude"), .off)
    }

    func testScanBundle() throws {
        try makeBundle("suite", children: ["alpha", "beta"])
        let entries = scan()
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].isBundle)
        XCTAssertEqual(entries[0].children?.map(\.name), ["alpha", "beta"])
    }

    func testFrontmatterParsing() throws {
        let dir = try makeSkill("fm")
        try "---\nname: fm\ndescription: \"带引号的描述\"\nversion: 2.1.0\nauthor: majia\n---\n正文".write(
            to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let front = fs.frontmatter(dir.appendingPathComponent("SKILL.md"))
        XCTAssertEqual(front["description"], "带引号的描述")
        XCTAssertEqual(front["version"], "2.1.0")
        XCTAssertEqual(front["author"], "majia")
    }

    // ── 链接状态 ──────────────────────────────────────────

    func testLinkStatusOn() throws {
        let dir = try makeSkill("foo")
        try fm.createSymbolicLink(at: claudeLink("foo"), withDestinationURL: dir)
        XCTAssertEqual(scan()[0].cap.status("claude"), .on)
        XCTAssertEqual(scan()[0].cap.status("codex"), .off)
    }

    func testLinkStatusBroken() throws {
        try makeSkill("foo")
        try fm.createSymbolicLink(at: claudeLink("foo"), withDestinationURL: env.storeRoot.appendingPathComponent("skills/gone"))
        let cap = scan()[0].cap
        XCTAssertEqual(cap.status("claude"), .broken)
        XCTAssertEqual(cap.brokenCause["claude"], "断链")
    }

    func testLinkStatusLocalCopyIsStub() throws {
        try makeSkill("foo")
        try fm.createDirectory(at: claudeLink("foo"), withIntermediateDirectories: true)  // 真实目录占位
        let cap = scan()[0].cap
        XCTAssertEqual(cap.status("claude"), .stub)
        XCTAssertEqual(cap.brokenCause["claude"], "本地副本")
    }

    // ── 开关防呆 ──────────────────────────────────────────

    func testToggleOnOff() throws {
        let dir = try makeSkill("foo")
        let tool = tools.first { $0.id == "claude" }!
        try fs.setLink(tool: tool, kind: .skill, name: "foo", storeDir: dir, on: true)
        XCTAssertEqual(scan()[0].cap.status("claude"), .on)
        try fs.setLink(tool: tool, kind: .skill, name: "foo", storeDir: dir, on: false)
        XCTAssertEqual(scan()[0].cap.status("claude"), .off)
        XCTAssertTrue(fm.fileExists(atPath: dir.path), "store 目录绝不能被开关动到")
    }

    func testRemoveLinkRefusesRealDirectory() throws {
        try makeSkill("foo")
        try fm.createDirectory(at: claudeLink("foo"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try fs.removeLink(at: claudeLink("foo"))) { err in
            guard case StoreError.notASymlink = err else { return XCTFail("应拒绝删除真实目录") }
        }
        XCTAssertTrue(fm.fileExists(atPath: claudeLink("foo").path), "真实目录必须原样保留")
    }

    // ── 套装：整链 ↔ 物化 ────────────────────────────────

    func testBundleWholeLinkAllChildrenOn() throws {
        let dir = try makeBundle("suite", children: ["alpha", "beta"])
        try fm.createSymbolicLink(at: claudeLink("suite"), withDestinationURL: dir)
        let kids = scan()[0].children!
        XCTAssertEqual(kids.map { $0.status("claude") }, [.on, .on])
    }

    func testBundleChildToggleMaterializes() throws {
        let dir = try makeBundle("suite", children: ["alpha", "beta"])
        try fm.createSymbolicLink(at: claudeLink("suite"), withDestinationURL: dir)
        let tool = tools.first { $0.id == "claude" }!

        // 关掉 alpha：整链应物化为目录，beta 保持 on
        try fs.setBundleChildLink(tool: tool, bundleName: "suite", bundleDir: dir,
                                  childName: "alpha", allChildren: ["alpha", "beta"], on: false)
        XCTAssertFalse(fs.isSymlink(claudeLink("suite")), "整链应已物化为目录")
        let kids = scan()[0].children!
        XCTAssertEqual(kids.first { $0.name == "alpha" }!.status("claude"), .off)
        XCTAssertEqual(kids.first { $0.name == "beta" }!.status("claude"), .on)

        // 再开回 alpha
        try fs.setBundleChildLink(tool: tool, bundleName: "suite", bundleDir: dir,
                                  childName: "alpha", allChildren: ["alpha", "beta"], on: true)
        XCTAssertEqual(scan()[0].children!.map { $0.status("claude") }, [.on, .on])
    }

    // ── 安装 / 移除 ───────────────────────────────────────

    func testResolveAndInstallLocalSource() throws {
        let src = sandbox.appendingPathComponent("my-skill")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try "---\nname: my-skill\ndescription: 本地源\nversion: 0.1.0\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let resolved = try fs.resolve(src.path)
        XCTAssertEqual(resolved.kind, .local)
        XCTAssertEqual(resolved.items.count, 1)
        XCTAssertFalse(resolved.isBundle)

        try fs.install(resolved, linkTools: tools.filter { $0.id == "claude" })
        let entries = scan()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].cap.status("claude"), .on)
        XCTAssertEqual(entries[0].cap.status("codex"), .off)
        XCTAssertEqual(entries[0].sourceUrl, src.path)
        XCTAssertTrue(fm.fileExists(atPath: src.path), "local 源安装是复制，原目录保留")
    }

    func testInstallRefusesDuplicate() throws {
        try makeSkill("dup")
        let src = sandbox.appendingPathComponent("dup")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try "---\nname: dup\n---\n".write(to: src.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let resolved = try fs.resolve(src.path)
        XCTAssertThrowsError(try fs.install(resolved, linkTools: []))
    }

    func testRemoveEntryGoesToTrash() throws {
        let dir = try makeSkill("foo")
        try fm.createSymbolicLink(at: claudeLink("foo"), withDestinationURL: dir)
        let entry = scan()[0]
        try fs.removeEntry(entry, tools: tools)
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
        XCTAssertFalse(fs.isSymlink(claudeLink("foo")))
        let trash = (try? fm.contentsOfDirectory(atPath: fs.trashURL.path)) ?? []
        XCTAssertEqual(trash.filter { $0.hasPrefix("foo-") }.count, 1, "store 副本应进回收站而不是直接删除")
    }

    func testRemoveBundleCleansMaterializedDir() throws {
        let dir = try makeBundle("suite", children: ["alpha", "beta"])
        let tool = tools.first { $0.id == "claude" }!
        try fm.createSymbolicLink(at: claudeLink("suite"), withDestinationURL: dir)
        try fs.setBundleChildLink(tool: tool, bundleName: "suite", bundleDir: dir,
                                  childName: "alpha", allChildren: ["alpha", "beta"], on: false)
        let entry = scan()[0]
        try fs.removeEntry(entry, tools: tools)
        XCTAssertFalse(fm.fileExists(atPath: claudeLink("suite").path), "物化目录应被清理")
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
    }

    // ── 修复 ─────────────────────────────────────────────

    func testReplaceCopyWithLink() throws {
        let dir = try makeSkill("foo")
        try fm.createDirectory(at: claudeLink("foo"), withIntermediateDirectories: true)
        try "私货".write(to: claudeLink("foo").appendingPathComponent("local.md"), atomically: true, encoding: .utf8)
        try fs.replaceCopyWithLink(at: claudeLink("foo"), target: dir)
        XCTAssertTrue(fs.isSymlink(claudeLink("foo")))
        XCTAssertEqual(scan()[0].cap.status("claude"), .on)
        // 原目录进了回收站
        let trash = (try? fm.contentsOfDirectory(atPath: fs.trashURL.path)) ?? []
        XCTAssertEqual(trash.filter { $0.hasPrefix("foo-") }.count, 1)
    }

    // ── 文档摘要提取（PATCH-01 详情 peek）─────────────────

    func testReadmeExtractionSkipsFrontmatterAndHeadings() throws {
        let dir = try makeSkill("foo")
        try """
        ---
        name: foo
        description: 描述
        ---

        # foo

        这是正文首段第一句。
        这是同段第二句。

        第二段不应出现。
        """.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let cap = scan()[0].cap
        XCTAssertEqual(cap.readme, "这是正文首段第一句。 这是同段第二句。")
    }

    func testReadmeTruncatesAt120() throws {
        let dir = try makeSkill("foo")
        let long = String(repeating: "字", count: 200)
        try "---\nname: foo\n---\n\n\(long)\n".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let readme = scan()[0].cap.readme
        XCTAssertEqual(readme?.count, 121)   // 120 字 + …
        XCTAssertTrue(readme?.hasSuffix("…") == true)
    }

    func testReadmeSkipsCodeFence() throws {
        let dir = try makeSkill("foo")
        try "---\nname: foo\n---\n\n```bash\nrm -rf /\n```\n\n真正的首段。\n".write(
            to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(scan()[0].cap.readme, "真正的首段。")
    }

    func testReadmeCLIPrefix() throws {
        let kindDir = env.storeRoot.appendingPathComponent("bin")
        let dir = kindDir.appendingPathComponent("mytool")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# mytool\n\n高性能工具。\n".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let entries = scan()
        let cli = entries.first { $0.name == "mytool" }
        XCTAssertEqual(cli?.cap.readme, "二进制 CLI，无 SKILL.md。高性能工具。")
    }

    // ── 更新机制（v2.1：内容哈希）────────────────────────

    func testDirHashStableAndSensitive() throws {
        let dir = try makeSkill("foo")
        let h1 = fs.computeDirHash(dir)
        XCTAssertEqual(h1, fs.computeDirHash(dir), "同内容哈希必须稳定")
        try "改动".write(to: dir.appendingPathComponent("extra.md"), atomically: true, encoding: .utf8)
        XCTAssertNotEqual(h1, fs.computeDirHash(dir), "内容变化哈希必须变化")
        // 隐藏文件不参与
        let h2 = fs.computeDirHash(dir)
        try "junk".write(to: dir.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        XCTAssertEqual(h2, fs.computeDirHash(dir), "隐藏文件不应影响哈希")
    }

    func testCheckUpdateAndApply() throws {
        // 本地源安装 → 上游改动 → 检查到更新 → 执行更新（备份 + 落盘 + 链接延续）
        let src = sandbox.appendingPathComponent("up-skill")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try "---\nname: up-skill\nversion: 1.0.0\n---\n旧内容\n".write(
            to: src.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let resolved = try fs.resolve(src.path)
        try fs.install(resolved, linkTools: tools.filter { $0.id == "claude" })

        var entry = scan()[0]
        XCTAssertNil(try fs.checkUpdate(entry), "未变化时不应报更新")

        try "---\nname: up-skill\nversion: 1.1.0\n---\n新内容\n".write(
            to: src.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let check = try XCTUnwrap(try fs.checkUpdate(entry))
        XCTAssertEqual(check.latest, "1.1.0")

        try fs.applyUpdate(entry)
        entry = scan()[0]
        XCTAssertEqual(entry.cap.version, "1.1.0", "store 应换成上游新版")
        XCTAssertEqual(entry.cap.status("claude"), .on, "symlink 路径不变应自动延续")
        let trash = (try? fm.contentsOfDirectory(atPath: fs.trashURL.path)) ?? []
        XCTAssertEqual(trash.filter { $0.hasPrefix("up-skill-") }.count, 1, "更新前必须备份旧版")
    }

    func testTrashPruneKeepsNewest() throws {
        for i in 0..<25 {
            let d = sandbox.appendingPathComponent("junk\(i)")
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try fs.moveToTrash(d)
        }
        let count = ((try? fm.contentsOfDirectory(atPath: fs.trashURL.path)) ?? []).count
        XCTAssertLessThanOrEqual(count, StoreFS.trashRetainCount, "回收站最多保留 \(StoreFS.trashRetainCount) 份")
    }

    // ── 来源回填 + 源式套装（v2.1）────────────────────────

    func writeLock(_ skills: [String: [String: String]]) throws {
        let dict: [String: Any] = ["version": 3, "skills": skills]
        let data = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
        try data.write(to: env.storeRoot.appendingPathComponent(".skill-lock.json"))
    }

    func testLockProvenanceGroupsIntoSourceBundle() throws {
        try makeSkill("alpha")
        try makeSkill("beta")
        try makeSkill("loner")
        try writeLock([
            "alpha": ["source": "jim/x", "sourceUrl": "https://github.com/Jim/X.git", "skillPath": "skills/alpha/SKILL.md"],
            "beta":  ["source": "jim/x", "sourceUrl": "https://github.com/Jim/X.git", "skillPath": "skills/beta/SKILL.md"],
            "loner": ["source": "other/y", "sourceUrl": "https://github.com/other/y.git", "skillPath": "SKILL.md"],
        ])
        let entries = scan()
        let bundle = try XCTUnwrap(entries.first(where: \.isBundle))
        XCTAssertEqual(bundle.bundleKind, .source)
        XCTAssertEqual(bundle.sourceUrl, "github.com/jim/x", "URL 应归一化（去协议/.git/小写）")
        XCTAssertEqual(bundle.children?.map(\.name), ["alpha", "beta"])
        XCTAssertEqual(bundle.children?.first?.repoSubdir, "skills/alpha")
        // 单成员的源不归拢
        let loner = try XCTUnwrap(entries.first(where: { $0.name == "loner" }))
        XCTAssertFalse(loner.isBundle)
        XCTAssertEqual(loner.sourceUrl, "github.com/other/y")
    }

    func testGitRemoteProvenance() throws {
        let dir = try makeSkill("cloned")
        _ = fs.run("/usr/bin/git", ["-C", dir.path, "init", "-q"])
        _ = fs.run("/usr/bin/git", ["-C", dir.path, "remote", "add", "origin", "https://github.com/op/Cloned-Skill.git"])
        let entry = try XCTUnwrap(scan().first(where: { $0.name == "cloned" }))
        XCTAssertEqual(entry.sourceUrl, "github.com/op/cloned-skill")
    }

    func testDevSymlinkEntryNotGrouped() throws {
        // store 里指向私有仓的软链接成员：不参与归拢、更新时跳过
        try makeSkill("alpha")
        let priv = sandbox.appendingPathComponent("private-repo/dev-skill")
        try fm.createDirectory(at: priv, withIntermediateDirectories: true)
        try "---\nname: dev-skill\n---\n".write(to: priv.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(
            at: env.storeRoot.appendingPathComponent("skills/dev-skill"), withDestinationURL: priv)
        try writeLock([
            "alpha": ["source": "jim/x", "sourceUrl": "https://github.com/jim/x.git", "skillPath": "skills/alpha/SKILL.md"],
            "dev-skill": ["source": "jim/x", "sourceUrl": "https://github.com/jim/x.git", "skillPath": "skills/dev-skill/SKILL.md"],
        ])
        let entries = scan()
        XCTAssertNil(entries.first(where: \.isBundle), "软链成员不计入，单成员不成套装")
    }

    func testSourceBundleUpdateOnlyChangedMember() throws {
        // 本地 monorepo 当上游：skills/a + skills/b
        let upstream = sandbox.appendingPathComponent("mono")
        for n in ["a", "b"] {
            let d = upstream.appendingPathComponent("skills/\(n)")
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try "---\nname: \(n)\nversion: 1.0.0\n---\n旧\n".write(to: d.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        // 本地安装态 = 从 monorepo 拷出来的平铺目录 + lock 记录
        for n in ["a", "b"] {
            try fm.copyItem(at: upstream.appendingPathComponent("skills/\(n)"),
                            to: env.storeRoot.appendingPathComponent("skills/\(n)"))
        }
        try writeLock([
            "a": ["source": upstream.path, "sourceUrl": upstream.path, "skillPath": "skills/a/SKILL.md"],
            "b": ["source": upstream.path, "sourceUrl": upstream.path, "skillPath": "skills/b/SKILL.md"],
        ])
        var entries = scan()
        // 本地路径源不参与 github 归拢 → 仍是两个独立条目，但带来源可检查
        let a = try XCTUnwrap(entries.first(where: { $0.name == "a" }))
        XCTAssertNil(try fs.checkUpdate(a), "未变化不报更新")

        // 上游改 a + 新增 c
        try "---\nname: a\nversion: 2.0.0\n---\n新\n".write(
            to: upstream.appendingPathComponent("skills/a/SKILL.md"), atomically: true, encoding: .utf8)
        let cDir = upstream.appendingPathComponent("skills/c")
        try fm.createDirectory(at: cDir, withIntermediateDirectories: true)
        try "---\nname: c\n---\n".write(to: cDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let check = try XCTUnwrap(try fs.checkUpdate(a))
        XCTAssertEqual(check.latest, "2.0.0")
        XCTAssertEqual(check.changedMembers, ["a"])
        XCTAssertTrue(check.upstreamNew.contains("c"), "应报告上游新增未安装的技能")

        let result = try fs.applyUpdate(a)
        XCTAssertEqual(result.updated, ["a"])
        entries = scan()
        XCTAssertEqual(entries.first(where: { $0.name == "a" })?.cap.version, "2.0.0")
        XCTAssertEqual(entries.first(where: { $0.name == "b" })?.cap.version, "1.0.0", "未变化成员不应被动")
    }

    // ── 排序 / 类型推断 / 前缀收编（v2.1.2）──────────────

    func testSortBundlesFirstThenType() throws {
        try makeSkill("zeta")                      // Skill
        try makeSkill("acme-cli")                  // → CLI（名称特征）
        try makeBundle("suite", children: ["a"])   // 目录形套装
        let names = scan().map(\.name)
        XCTAssertEqual(names, ["suite", "zeta", "acme-cli"], "套装置顶 → Skill → CLI")
    }

    func testInferTypeKeepsLinkLayout() throws {
        let dir = try makeSkill("guancli")
        let entry = scan()[0]
        XCTAssertEqual(entry.cap.type, .cli, "名称特征应推断为 CLI")
        XCTAssertEqual(entry.cap.layoutKind, .skill, "链接布局必须留在 skills/")
        // 开关仍写到 ~/.claude/skills/，不是 bin/
        let tool = tools.first { $0.id == "claude" }!
        try fs.setLink(tool: tool, kind: entry.cap.layoutKind, name: "guancli", storeDir: dir, on: true)
        XCTAssertTrue(fs.isSymlink(claudeLink("guancli")))
    }

    func testFrontmatterExplicitTypeWins() throws {
        let dir = try makeSkill("weird-name")
        try "---\nname: weird-name\ntype: mcp\n---\n".write(
            to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(scan()[0].cap.type, .mcp)
    }

    func testPrefixFamilyAbsorbsOrphan() throws {
        // 5 个 lock 成员 + 1 个无来源同前缀散件 → 收编成 6 项
        var lock: [String: [String: String]] = [:]
        for i in 1...5 {
            try makeSkill("fam-s\(i)")
            lock["fam-s\(i)"] = ["source": "own/fam", "sourceUrl": "https://github.com/own/fam.git",
                                 "skillPath": "skills/fam-s\(i)/SKILL.md"]
        }
        try makeSkill("fam-orphan")    // 不在 lock、无 homepage
        try makeSkill("other-thing")   // 不同前缀，不该被收
        try writeLock(lock)
        let entries = scan()
        let bundle = try XCTUnwrap(entries.first(where: \.isBundle))
        XCTAssertEqual(bundle.children?.count, 6, "散件应被前缀族收编")
        XCTAssertEqual(bundle.children?.first(where: { $0.name == "fam-orphan" })?.repoSubdir, "skills/fam-orphan")
        XCTAssertNotNil(entries.first(where: { $0.name == "other-thing" }), "异前缀不收")
    }

    // ── 安全校验（v2.1）──────────────────────────────────

    func testSanitizeNameRejectsTraversal() {
        XCTAssertThrowsError(try sanitizeName("../evil"))
        XCTAssertThrowsError(try sanitizeName("a/b"))
        XCTAssertThrowsError(try sanitizeName(".hidden"))
        XCTAssertThrowsError(try sanitizeName(""))
        XCTAssertEqual(try? sanitizeName("good-name"), "good-name")
    }

    // ── 未托管目录导入（v2.1）────────────────────────────

    func testScanAndImportUnmanaged() throws {
        // 工具目录里有一个真实技能目录，store 没有同名
        let wild = claudeLink("wild-skill")
        try fm.createDirectory(at: wild, withIntermediateDirectories: true)
        try "---\nname: wild-skill\ndescription: 散养的\n---\n".write(
            to: wild.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let found = fs.scanUnmanaged(tools: tools, knownNames: [])
        XCTAssertEqual(found.map(\.name), ["wild-skill"])

        let imported = try fs.importUnmanaged(found)
        XCTAssertEqual(imported, ["wild-skill"])
        let entries = scan()
        XCTAssertEqual(entries.map(\.name), ["wild-skill"])
        XCTAssertEqual(entries[0].cap.status("claude"), .on, "原位应已换成 symlink")
        XCTAssertTrue(fs.isSymlink(wild))
    }

    // ── 元数据 ───────────────────────────────────────────

    func testMetaRoundtrip() throws {
        var meta = StoreMeta()
        meta.entries["foo"] = StoreMeta.EntryMeta(sourceUrl: "github.com/a/b", autoUpdate: true, latest: nil)
        meta.tools["claude"] = StoreMeta.ToolMeta(defaultTarget: false)
        fs.saveMeta(meta)
        let loaded = fs.loadMeta()
        XCTAssertEqual(loaded.entries["foo"]?.sourceUrl, "github.com/a/b")
        XCTAssertEqual(loaded.entries["foo"]?.autoUpdate, true)
        XCTAssertEqual(loaded.tools["claude"]?.defaultTarget, false)
    }

    // ── 派生统计 ──────────────────────────────────────────

    func testStatsAndIssues() throws {
        let dir = try makeSkill("foo")
        try makeSkill("bar")
        try fm.createSymbolicLink(at: claudeLink("foo"), withDestinationURL: dir)
        try fm.createSymbolicLink(at: claudeLink("bar"), withDestinationURL: env.storeRoot.appendingPathComponent("skills/gone"))
        let entries = scan()
        let stats = deriveStats(entries, tools: tools)
        XCTAssertEqual(stats.total, 2)
        XCTAssertEqual(stats.symlinks, 1)
        XCTAssertEqual(stats.broken, 1)
        let issues = deriveIssues(entries, tools: tools)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].capName, "bar")
        XCTAssertEqual(issues[0].toolId, "claude")
    }
}
