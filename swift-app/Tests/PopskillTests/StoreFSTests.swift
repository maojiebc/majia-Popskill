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
        // v2.16：链接状态分布（linkStatus 改比对 expectedTarget 后，真实环境不能出现误判风暴）
        var dist: [String: Int] = [:]
        for e in entries { for c in e.allCaps { for t in tools {
            let st = c.status(t.id)
            dist["\(t.id).\(st)", default: 0] += 1
            if st == .broken, let cause = c.brokenCause[t.id] { print("   ⚠ broken: \(c.name) · \(t.id) — \(cause)") }
        } } }
        print("== 状态分布: \(dist.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
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
    /// 回收站全部条目名（v2.8 起按 kind 分桶 + 兼容历史平铺）
    func trashNames() -> [String] { fs.listTrash().map { $0.url.lastPathComponent } }

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

    func testFrontmatterBlockScalar() throws {
        let dir = try makeSkill("blocky")
        try """
        ---
        name: blocky
        description: |
          第一行描述。
          第二行接着说。

          空行后的不要。
        version: 1.0.0
        ---
        """.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let front = fs.frontmatter(dir.appendingPathComponent("SKILL.md"))
        XCTAssertEqual(front["description"], "第一行描述。 第二行接着说。", "块标量应取首段，不再显示 |")
        XCTAssertEqual(front["version"], "1.0.0", "块标量后的 key 不能丢")
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

    func testFrontmatterNestedMetadata() throws {
        // Agent Skills 标准格式：version/author 嵌在 metadata: 下（majia-guanyuan 实例）
        let dir = try makeSkill("nested")
        try """
        ---
        name: nested
        license: MIT
        metadata:
          version: "3.0.5"
          author: "超级马甲 / maojiebc"
          openclaw:
            emoji: "📊"
            os:
              - macos
        ---
        正文
        """.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let front = fs.frontmatter(dir.appendingPathComponent("SKILL.md"))
        XCTAssertEqual(front["version"], "3.0.5", "metadata 直接子级的 version 要能读到")
        XCTAssertEqual(front["author"], "超级马甲 / maojiebc")
        XCTAssertEqual(front["license"], "MIT", "顶层 key 不受嵌套块影响")
        XCTAssertNil(front["emoji"], "更深层（openclaw:）不收，避免误拾")
    }

    func testCheckUpdateClearsStaleLatest() throws {
        // 用户在终端手动把 store 同步到了上游：完整比对确认一致后，
        // 上次检查残留的 latest 徽标必须熄灭（HEAD 短路路径不受影响——
        // latest 非 nil 时不短路，见 checkUpdate）
        let upstream = sandbox.appendingPathComponent("up-fresh")
        let upSkill = upstream.appendingPathComponent("skills/fresh")
        try fm.createDirectory(at: upSkill, withIntermediateDirectories: true)
        try "---\nname: fresh\nversion: 2.0.0\n---\n已同步内容\n".write(
            to: upSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try fm.copyItem(at: upSkill, to: env.storeRoot.appendingPathComponent("skills/fresh"))
        fs.saveLatest("fresh", latest: "新版", changed: ["fresh"])   // 上次检查的残留

        let cap = Capability(id: "fresh", name: "fresh", type: .skill, linkKind: .skill, desc: "",
                             version: "2.0.0", author: nil, tokens: 0,
                             dirURL: env.storeRoot.appendingPathComponent("skills/fresh"))
        let entry = Entry(id: "fresh", cap: cap, children: nil, bundleKind: nil,
                          sourceUrl: upstream.path, latest: "新版")

        XCTAssertNil(try fs.checkUpdate(entry), "内容一致应返回 nil")
        XCTAssertNil(fs.loadMeta().entries["fresh"]?.latest, "确认一致后残留徽标要熄灭")
        XCTAssertNil(fs.loadMeta().entries["fresh"]?.changed)
    }

    func testCheckUpdateKeepsLatestWhenStillChanged() throws {
        // 上游仍有差异：latest 维持（重新解析出上游版本号）
        let upstream = sandbox.appendingPathComponent("up-diff")
        let upSkill = upstream.appendingPathComponent("skills/diffy")
        try fm.createDirectory(at: upSkill, withIntermediateDirectories: true)
        try "---\nname: diffy\nversion: 3.1.0\n---\n上游新内容\n".write(
            to: upSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        _ = try makeSkill("diffy", version: "3.0.5")

        let cap = Capability(id: "diffy", name: "diffy", type: .skill, linkKind: .skill, desc: "",
                             version: "3.0.5", author: nil, tokens: 0,
                             dirURL: env.storeRoot.appendingPathComponent("skills/diffy"))
        let entry = Entry(id: "diffy", cap: cap, children: nil, bundleKind: nil,
                          sourceUrl: upstream.path, latest: "新版")

        let check = try XCTUnwrap(try fs.checkUpdate(entry), "有差异应返回 UpdateCheck")
        XCTAssertEqual(check.latest, "3.1.0", "应解析出上游版本号而非笼统的「新版」")
    }

    // ── 跳过此版本（v2.15）───────────────────────────────

    /// 上游 fixture + store 本地版 + entry 三件套（跳过场景共用）
    private func makeSkipFixture(_ name: String, upstreamBody: String) throws -> (upstream: URL, entry: Entry) {
        let upstream = sandbox.appendingPathComponent("up-\(name)")
        let upSkill = upstream.appendingPathComponent("skills/\(name)")
        try fm.createDirectory(at: upSkill, withIntermediateDirectories: true)
        try "---\nname: \(name)\nversion: 2.0.0\n---\n\(upstreamBody)\n".write(
            to: upSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        _ = try makeSkill(name, version: "1.0.0")
        let cap = Capability(id: name, name: name, type: .skill, linkKind: .skill, desc: "",
                             version: "1.0.0", author: nil, tokens: 0,
                             dirURL: env.storeRoot.appendingPathComponent("skills/\(name)"))
        return (upstream, Entry(id: name, cap: cap, children: nil, bundleKind: nil,
                                sourceUrl: upstream.path, latest: nil))
    }

    func testSkipSuppressesSameUpstreamState() throws {
        let (_, entry) = try makeSkipFixture("skippy", upstreamBody: "上游新内容")
        let check = try XCTUnwrap(try fs.checkUpdate(entry), "有差异应报更新")
        XCTAssertFalse(check.fingerprint.isEmpty, "检查结论必须带上游状态指纹")
        fs.saveLatest("skippy", latest: check.latest, changed: check.changedMembers,
                      fingerprint: check.fingerprint)

        fs.skipLatest("skippy")
        let m = fs.loadMeta().entries["skippy"]
        XCTAssertNil(m?.latest, "跳过后徽标应熄灭")
        XCTAssertNil(m?.latestFingerprint)
        XCTAssertEqual(m?.skipped, check.fingerprint, "跳过钉住的是指纹，不是文案标签")

        XCTAssertNil(try fs.checkUpdate(entry), "同一上游状态：跳过抑制生效，不再报更新")
        XCTAssertEqual(fs.loadMeta().entries["skippy"]?.skipped, check.fingerprint,
                       "抑制路径不得误清跳过标记")
    }

    func testNewUpstreamStateClearsSkipAndRealerts() throws {
        let (upstream, entry) = try makeSkipFixture("hoppy", upstreamBody: "第一版上游内容")
        let first = try XCTUnwrap(try fs.checkUpdate(entry))
        fs.saveLatest("hoppy", latest: first.latest, changed: first.changedMembers,
                      fingerprint: first.fingerprint)
        fs.skipLatest("hoppy")
        XCTAssertNil(try fs.checkUpdate(entry), "跳过态先确认抑制住")

        // 上游又出了新东西：指纹必变 → 抑制失效、跳过标记自动清除
        try "---\nname: hoppy\nversion: 3.0.0\n---\n第二版上游内容\n".write(
            to: upstream.appendingPathComponent("skills/hoppy/SKILL.md"),
            atomically: true, encoding: .utf8)
        let second = try XCTUnwrap(try fs.checkUpdate(entry), "新上游状态应重新报更新")
        XCTAssertNotEqual(second.fingerprint, first.fingerprint)
        XCTAssertNil(fs.loadMeta().entries["hoppy"]?.skipped, "新状态出现后旧跳过应自动清除")
    }

    func testUnskipClearsCheckpointSoRecheckSeesUpdate() throws {
        let (_, entry) = try makeSkipFixture("comeback", upstreamBody: "上游内容")
        let check = try XCTUnwrap(try fs.checkUpdate(entry))
        fs.saveLatest("comeback", latest: check.latest, changed: check.changedMembers,
                      fingerprint: check.fingerprint)
        fs.skipLatest("comeback")
        XCTAssertNil(try fs.checkUpdate(entry))

        fs.unskipLatest("comeback")
        let m = fs.loadMeta().entries["comeback"]
        XCTAssertNil(m?.skipped)
        XCTAssertNil(m?.lastHead, "恢复提醒必须清检查点，否则 HEAD 短路会钉死「最新」")
        let again = try XCTUnwrap(try fs.checkUpdate(entry), "恢复提醒后重查应重新报更新")
        XCTAssertEqual(again.fingerprint, check.fingerprint, "上游没动，指纹应一致")
    }

    func testFrontmatterTopLevelWinsOverMetadata() throws {
        let dir = try makeSkill("nested2")
        try """
        ---
        name: nested2
        metadata:
          version: "9.9.9"
          type: agent
        version: "1.0.0"
        ---
        """.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let front = fs.frontmatter(dir.appendingPathComponent("SKILL.md"))
        XCTAssertEqual(front["version"], "1.0.0", "顶层与 metadata 同名时顶层优先")
        XCTAssertEqual(front["type"], "agent", "metadata 只补顶层缺失的 key")
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

    func testFreshMachineScanAndInstall() throws {
        // 新用户零基建：store 根本不存在 → 扫描得空表；首次安装自建全部目录
        let virgin = StoreEnv(storeRoot: sandbox.appendingPathComponent("virgin/.agents"),
                              toolRoots: ["claude": sandbox.appendingPathComponent("virgin/.claude")])
        let vfs = StoreFS(env: virgin)
        let vtools = vfs.scanTools(meta: StoreMeta())
        XCTAssertEqual(vfs.scanEntries(tools: vtools, meta: StoreMeta()).count, 0, "无 store 应得空表而非崩溃")
        XCTAssertFalse(vtools[0].connected, "工具根不存在应显示未连接")

        let src = sandbox.appendingPathComponent("first-skill")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try "---\nname: first-skill\ndescription: 第一个\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try vfs.install(try vfs.resolve(src.path), linkTools: vtools)
        let entries = vfs.scanEntries(tools: vfs.scanTools(meta: StoreMeta()), meta: vfs.loadMeta())
        XCTAssertEqual(entries.map(\.name), ["first-skill"], "首次安装应自建 store 目录并入册")
        XCTAssertEqual(entries[0].cap.status("claude"), .on)
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
        XCTAssertEqual(trashNames().filter { $0.hasPrefix("foo-") }.count, 1, "store 副本应进回收站而不是直接删除")
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
        XCTAssertEqual(trashNames().filter { $0.hasPrefix("foo-") }.count, 1)
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

    // ── v2.13 体检修复 ───────────────────────────────────

    func testInstallRollbackOnCopyFailure() throws {
        // 源里有不可读文件 → install 的 copyItem 必败；曾留半个 dest 目录、重试报「已存在」卡死
        let src = sandbox.appendingPathComponent("frag-src")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try "---\nname: frag-src\n---\n".write(to: src.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let locked = src.appendingPathComponent("locked.md")
        try "x".write(to: locked, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        let resolved = try fs.resolve(src.path)
        XCTAssertThrowsError(try fs.install(resolved, linkTools: []))
        let dest = env.storeRoot.appendingPathComponent("skills/frag-src")
        XCTAssertFalse(fm.fileExists(atPath: dest.path), "失败后不能留半个目录")
    }

    func testTrashSameNameSameSecondNoCollision() throws {
        // 同名条目同一秒内二次入站：曾撞名抛错；现在补后缀，两份都活、操作不失败
        let a = sandbox.appendingPathComponent("dup"); try fm.createDirectory(at: a, withIntermediateDirectories: true)
        try fs.moveToTrash(a)
        let b = env.storeRoot.appendingPathComponent("skills/dup"); try fm.createDirectory(at: b, withIntermediateDirectories: true)
        XCTAssertNoThrow(try fs.moveToTrash(b))
        XCTAssertEqual(trashNames().filter { $0.hasPrefix("dup") }.count, 2, "同秒两次入站都应保留")
        // v2.16：撞名后缀改在名字段（~xxxx），戳保持结尾——listTrash 两条都解析出干净名
        // （旧形状把后缀追加在戳后，导致名字不去戳、时间沉底、恢复出脏名目录）
        let items = fs.listTrash().filter { $0.name == "dup" }
        XCTAssertEqual(items.count, 2, "撞名条目的名字也要解析干净")
        XCTAssertTrue(items.allSatisfy { $0.date != nil }, "撞名条目的入站时间不能丢")
    }

    func testHumanGitErrorMapping() {
        XCTAssertTrue(StoreFS.humanGitError(cloneURL: "x", stderr: "fatal: could not resolve host: github.com").contains(L("连不上网络，没法获取这个仓库——检查网络后重试。")))
        XCTAssertTrue(StoreFS.humanGitError(cloneURL: "x", stderr: "fatal: Authentication failed").contains(L("这个仓库需要登录（可能是私有仓库）——Popskill 暂时只支持公开仓库。")))
        XCTAssertTrue(StoreFS.humanGitError(cloneURL: "x", stderr: "fatal: repository not found").contains(L("找不到这个仓库——检查地址是否写对、是否为公开仓库。")))
        // stderr 全空也绝不返回冒号后空白
        let blank = StoreFS.humanGitError(cloneURL: "x", stderr: "   \n ")
        XCTAssertFalse(blank.hasSuffix("："))
        XCTAssertFalse(blank.isEmpty)
    }

    func testSourceWebURLMapping() {
        // npm:@scope/pkg → npm 包页（曾把 npm:@x/y 拼成 https://npm:@x/y 点了跳不动）
        XCTAssertEqual(StoreFS.sourceWebURL("npm:@guandata/guanskill")?.absoluteString,
                       "https://www.npmjs.com/package/@guandata/guanskill")
        XCTAssertEqual(StoreFS.sourceWebURL("npm:typescript")?.absoluteString,
                       "https://www.npmjs.com/package/typescript")
        // github 各形态都收敛到 github.com/owner/repo
        XCTAssertEqual(StoreFS.sourceWebURL("github.com/dotey/skills")?.absoluteString,
                       "https://github.com/dotey/skills")
        XCTAssertEqual(StoreFS.sourceWebURL("https://github.com/Foo/Bar.git")?.absoluteString,
                       "https://github.com/foo/bar")
        // 本地源不给网址（调用方走访达）
        XCTAssertNil(StoreFS.sourceWebURL("~/work/my-skills/x"))
        XCTAssertNil(StoreFS.sourceWebURL("npm:"))   // 空包名不崩
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

    func testDirHashDoesNotFollowSymlinks() throws {
        let dir = try makeSkill("linky")
        // 环路软链 + 逃逸软链：遍历都不得跟随
        try fm.createSymbolicLink(at: dir.appendingPathComponent("loop"), withDestinationURL: dir)
        let secret = sandbox.appendingPathComponent("secret.txt")
        try "外部内容 v1".write(to: secret, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: dir.appendingPathComponent("escape"), withDestinationURL: secret)
        let h1 = fs.computeDirHash(dir)   // 环路下正常返回即通过防护
        try "外部内容 v2 变了".write(to: secret, atomically: true, encoding: .utf8)
        XCTAssertEqual(h1, fs.computeDirHash(dir), "软链目标的内容不参与哈希——绝不跟随读 store 外文件")
        try fm.removeItem(at: dir.appendingPathComponent("escape"))
        XCTAssertNotEqual(h1, fs.computeDirHash(dir), "软链本身（指向路径）参与哈希")
    }

    func testRunTimeoutKillsHungProcess() throws {
        let t0 = Date()
        let r = fs.run("/bin/sleep", ["30"], timeout: 2)
        XCTAssertEqual(r.status, -1)
        XCTAssertTrue(r.err.contains("超时"), "超时要在错误信息里说清楚")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 15, "watchdog 必须在超时后很快返回")
    }

    func testRunDrainsBigStderrWithoutDeadlock() throws {
        // stderr 灌 200KB（远超 64KB 管道缓冲）——顺序 readToEnd 的旧实现会死锁
        let r = fs.run("/bin/sh", ["-c",
            "dd if=/dev/zero bs=1024 count=200 2>/dev/null | tr '\\0' 'x' 1>&2; echo done"], timeout: 30)
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.out.trimmingCharacters(in: .whitespacesAndNewlines), "done")
        XCTAssertGreaterThan(r.err.count, 100_000, "stderr 必须被完整排空")
    }

    func testGithubTargetDerivesRepoName() throws {
        // 安装目录名必须 = 仓库名（曾用随机临时目录名 popskill-stage-xxxx 入库）
        let a = try StoreFS.githubTarget("https://github.com/Foo/My-Skills.git")
        XCTAssertEqual(a.repoName, "my-skills")
        XCTAssertEqual(a.cloneURL, "https://github.com/foo/my-skills.git")
        // 深路径粘贴也要收敛到 owner/repo
        let b = try StoreFS.githubTarget("github.com/foo/bar/tree/main/skills/x")
        XCTAssertEqual(b.cloneURL, "https://github.com/foo/bar.git")
        // owner/repo 简写
        XCTAssertEqual(try StoreFS.githubTarget("foo/bar").repoName, "bar")
        XCTAssertThrowsError(try StoreFS.githubTarget("github.com/onlyowner"))
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
        XCTAssertEqual(trashNames().filter { $0.hasPrefix("up-skill-") }.count, 1, "更新前必须备份旧版")
    }

    func testTrashPruneKeepsNewest() throws {
        for i in 0..<12 {
            let d = sandbox.appendingPathComponent("junk\(i)")
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try fs.moveToTrash(d)
        }
        fs.pruneTrash(keep: 10)
        XCTAssertEqual(trashNames().count, 10, "超过 keep 的部分应被清掉")
    }

    func testTrashPruneIsFIFOByTrashTime() throws {
        try fm.createDirectory(at: fs.trashURL, withIntermediateDirectories: true)
        // 老内容、新入站：目录 mtime 一年前（rename 入站不会更新它），入站戳是现在 → 必须存活。
        // 曾按 contentModificationDate 排序，这种刚备份的旧技能会被当「最旧」误删。
        let ancient = sandbox.appendingPathComponent("ancient")
        try fm.createDirectory(at: ancient, withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -86400 * 365)],
                             ofItemAtPath: ancient.path)
        let kept = try fs.moveToTrash(ancient)
        // 伪造 5 条早入站的平铺条目（v2.8 前的历史格式，戳在 2020 年，mtime 是现在）
        for i in 1...5 {
            let d = fs.trashURL.appendingPathComponent("junk\(i)-2020-01-0\(i)T00-00-00Z")
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        fs.pruneTrash(keep: 3)
        let names = trashNames()
        XCTAssertEqual(names.count, 3)
        XCTAssertTrue(names.contains(kept.lastPathComponent),
                      "刚入站的备份必须存活——按入站时间 FIFO，不看内容 mtime")
        XCTAssertFalse(names.contains("junk1-2020-01-01T00-00-00Z"), "最早入站的先被清")
        XCTAssertFalse(names.contains("junk2-2020-01-02T00-00-00Z"))
    }

    func testLocalDigestDetectsDrift() throws {
        // HEAD 短路的本地不变性校验：成员内容一变 digest 必变
        try makeSkill("drifty")
        let entry = scan()[0]
        let d1 = fs.localDigest(entry)
        XCTAssertEqual(d1, fs.localDigest(entry), "同内容 digest 必须稳定")
        try "改动".write(to: entry.cap.dirURL.appendingPathComponent("extra.md"),
                        atomically: true, encoding: .utf8)
        XCTAssertNotEqual(d1, fs.localDigest(entry), "本地漂移必须反映在 digest 里")
    }

    func testTrashRestoreKeepsKindDirectory() throws {
        // agent 类型条目移除后恢复，必须回 agents/ 而不是 skills/——
        // 错位会让 layoutKind 与 symlink 路径静默错乱（审查发现）
        let agentsDir = env.storeRoot.appendingPathComponent("agents")
        try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        let dir = try makeSkill("my-agent", in: agentsDir)
        var entry = scan().first { $0.name == "my-agent" }!
        XCTAssertEqual(entry.cap.layoutKind, .agent)
        try fs.removeEntry(entry, tools: tools)
        XCTAssertFalse(fm.fileExists(atPath: dir.path))

        let item = fs.listTrash().first { $0.name == "my-agent" }!
        XCTAssertEqual(item.kindDir, "agents", "入站桶必须记住原 kind")
        try fs.restoreFromTrash(item)
        XCTAssertTrue(fm.fileExists(atPath: agentsDir.appendingPathComponent("my-agent").path),
                      "必须恢复回 agents/ 原位")
        entry = scan().first { $0.name == "my-agent" }!
        XCTAssertEqual(entry.cap.layoutKind, .agent)
    }

    func testTrashListAndRestore() throws {
        try makeSkill("revive-me", desc: "要被复活的")
        let entry = scan()[0]
        try fs.removeEntry(entry, tools: tools)
        XCTAssertTrue(scan().isEmpty, "移除后 store 应为空")

        let items = fs.listTrash()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "revive-me", "名称应去掉时间戳后缀")
        XCTAssertNotNil(items[0].date, "入站时间应可解析")

        try fs.restoreFromTrash(items[0])
        let back = scan()
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].name, "revive-me")
        XCTAssertTrue(fs.listTrash().isEmpty, "恢复后回收站应清空该项")

        // 同名已存在时拒绝恢复
        try makeSkill("blocker")
        let dup = scan().first { $0.name == "blocker" }!
        try fs.removeEntry(dup, tools: tools)
        try makeSkill("blocker")
        XCTAssertThrowsError(try fs.restoreFromTrash(fs.listTrash()[0]))
    }

    func testApplyUpdateCopyFailureLeavesStoreIntact() throws {
        // 上游有不可读文件 → 拷贝必败。曾经先弃旧版再拷，失败即丢数据 + symlink 全断。
        let src = sandbox.appendingPathComponent("frag-skill")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try "---\nname: frag-skill\nversion: 1.0.0\n---\n旧内容\n".write(
            to: src.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let resolved = try fs.resolve(src.path)
        try fs.install(resolved, linkTools: tools.filter { $0.id == "claude" })

        try "---\nname: frag-skill\nversion: 2.0.0\n---\n新内容\n".write(
            to: src.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let locked = src.appendingPathComponent("locked.md")
        try "不可读".write(to: locked, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        let entry = scan()[0]
        XCTAssertThrowsError(try fs.applyUpdate(entry), "拷贝失败必须抛错而不是吞掉")

        let storeDir = env.storeRoot.appendingPathComponent("skills").appendingPathComponent("frag-skill")
        let text = try String(contentsOf: storeDir.appendingPathComponent("SKILL.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("1.0.0"), "更新失败 store 必须保持旧版无损")
        XCTAssertEqual(scan()[0].cap.status("claude"), .on, "symlink 不能断")
        let kindDir = try fm.contentsOfDirectory(atPath: storeDir.deletingLastPathComponent().path)
        XCTAssertFalse(kindDir.contains { $0.hasPrefix(".popskill-incoming-") }, "不能留半成品")
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

    func testNormalizeSourceCollapsesDeepPaths() {
        // 异机实测教训（v2.4.2）：逐 skill 不同的深路径必须收敛到同一分组键
        let expect = "github.com/jimliu/baoyu-skills"
        for raw in [
            "https://github.com/JimLiu/baoyu-skills/tree/main/skills/baoyu-comic",
            "github.com/jimliu/baoyu-skills/blob/main/skills/baoyu-diagram/SKILL.md",
            "https://www.github.com/JimLiu/baoyu-skills.git",
            "https://raw.githubusercontent.com/JimLiu/baoyu-skills/main/README.md",
            "github.com/jimliu/baoyu-skills#baoyu-comic",
            "github.com/jimliu/baoyu-skills/",
            "git@github.com:JimLiu/baoyu-skills.git",
        ] {
            XCTAssertEqual(StoreFS.normalizeSource(raw), expect, raw)
        }
    }

    func testPerSkillDeepHomepageStillGroups() throws {
        // 每个 skill 的 homepage 指向仓库内自己的子路径 → 仍应归成一个套装
        for n in ["deep-a", "deep-b"] {
            let dir = try makeSkill(n)
            try """
            ---
            name: \(n)
            homepage: https://github.com/Own/Mono/tree/main/skills/\(n)
            ---
            """.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let entries = scan()
        let bundle = try XCTUnwrap(entries.first(where: \.isBundle), "深路径 homepage 应收敛归拢")
        XCTAssertEqual(bundle.sourceUrl, "github.com/own/mono")
        XCTAssertEqual(bundle.children?.count, 2)
    }

    func testSymlinkStoreEntriesStillGroup() throws {
        // dotfiles 同步类布局：store 条目本身是软链 + github 来源 → 照样归拢（显示层）
        let real = sandbox.appendingPathComponent("dotfiles")
        for n in ["s-a", "s-b"] {
            let d = real.appendingPathComponent(n)
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try "---\nname: \(n)\n---\n".write(to: d.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            try fm.createSymbolicLink(at: env.storeRoot.appendingPathComponent("skills/\(n)"),
                                      withDestinationURL: d)
        }
        try writeLock([
            "s-a": ["source": "own/dots", "sourceUrl": "https://github.com/own/dots.git", "skillPath": "skills/s-a/SKILL.md"],
            "s-b": ["source": "own/dots", "sourceUrl": "https://github.com/own/dots.git", "skillPath": "skills/s-b/SKILL.md"],
        ])
        let bundle = try XCTUnwrap(scan().first(where: \.isBundle), "整 store 软链的机器也应归拢")
        XCTAssertEqual(bundle.children?.count, 2)
    }

    func testUpdateSkipsSymlinkMembers() throws {
        // 安全层不变：套装更新逐成员跳过软链（手工构造 entry，源用本地路径走通 resolve）
        let upstream = sandbox.appendingPathComponent("mono2")
        for n in ["s-a", "s-b"] {
            let d = upstream.appendingPathComponent("skills/\(n)")
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try "---\nname: \(n)\nversion: 1.0.0\n---\n旧\n".write(to: d.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        try fm.copyItem(at: upstream.appendingPathComponent("skills/s-a"),
                        to: env.storeRoot.appendingPathComponent("skills/s-a"))
        try fm.createSymbolicLink(at: env.storeRoot.appendingPathComponent("skills/s-b"),
                                  withDestinationURL: upstream.appendingPathComponent("skills/s-b"))
        func cap(_ n: String) -> Capability {
            var c = Capability(id: n, name: n, type: .skill, linkKind: .skill, desc: "", version: "1.0.0",
                               author: nil, tokens: 0,
                               dirURL: env.storeRoot.appendingPathComponent("skills/\(n)"))
            c.repoSubdir = "skills/\(n)"
            return c
        }
        var head = cap("bundle-head"); head.type = .bundle
        let entry = Entry(id: "src:test", cap: head, children: [cap("s-a"), cap("s-b")],
                          bundleKind: .source, sourceUrl: upstream.path)

        for n in ["s-a", "s-b"] {
            try "---\nname: \(n)\nversion: 2.0.0\n---\n新\n".write(
                to: upstream.appendingPathComponent("skills/\(n)/SKILL.md"), atomically: true, encoding: .utf8)
        }
        let check = try XCTUnwrap(try fs.checkUpdate(entry))
        XCTAssertEqual(check.changedMembers, ["s-a"], "软链成员必须被更新检查跳过")
        let result = try fs.applyUpdate(entry)
        XCTAssertEqual(result.updated, ["s-a"], "软链成员绝不能被更新写入")
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

    // ── 内置精选目录（v2.3）──────────────────────────────

    func testCatalogDescOverridesFrontmatter() throws {
        try makeSkill("defuddle", desc: "Extract clean article content from web pages")
        let cap = scan()[0].cap
        XCTAssertEqual(cap.desc, "网页正文净化抽取：去广告导航留正文", "目录简介应覆盖上游英文描述")
        // 不在目录里的保持 frontmatter
        try makeSkill("zz-unknown", desc: "原始描述")
        XCTAssertEqual(scan().first { $0.name == "zz-unknown" }?.cap.desc, "原始描述")
    }

    func testCatalogTypeHint() throws {
        try makeSkill("guancli")   // 目录提示 CLI（名称特征也会命中，但 guands 只有目录能定）
        try makeSkill("guands")
        let caps = scan().flatMap(\.allCaps)
        XCTAssertEqual(caps.first { $0.name == "guancli" }?.type, .cli)
        XCTAssertEqual(caps.first { $0.name == "guands" }?.type, .skill)
        XCTAssertEqual(caps.first { $0.name == "guancli" }?.layoutKind, .skill, "链接布局不受目录影响")
    }

    // ── 目录来源提示 + npm 套装归拢（v2.4）───────────────

    func testNormalizeSourceNpmPassthrough() {
        XCTAssertEqual(StoreFS.normalizeSource("npm:@guandata/guanskill"), "npm:@guandata/guanskill")
        XCTAssertEqual(StoreFS.normalizeSource("https://github.com/A/B.git"), "github.com/a/b")
    }

    func testCatalogSourceGroupsCopyInstalledFamily() throws {
        // guanskill 复制安装五件套：lock 无 / .git 无 / homepage 无 → 目录 source 提示归拢
        for n in ["guancli", "guands", "guanetl", "guanvis", "guanwf"] { try makeSkill(n) }
        let entries = scan()
        let bundle = try XCTUnwrap(entries.first(where: \.isBundle))
        XCTAssertEqual(bundle.bundleKind, .source)
        XCTAssertEqual(bundle.name, "guanskill")
        XCTAssertEqual(bundle.sourceUrl, "npm:@guandata/guanskill")
        XCTAssertEqual(bundle.children?.count, 5)
        XCTAssertEqual(bundle.children?.first { $0.name == "guancli" }?.type, .cli, "套装内 CLI tag 保留")
        // 注入「没装 npm」：v2.14 起 npm 源会真检查（比对全局 CLI），单测不能打网络、
        // 也不能依赖跑测试这台机器全局装没装包
        NpmEnv._setForTest(.some(nil))
        defer { NpmEnv._setForTest(nil) }
        XCTAssertNil(try fs.checkUpdate(bundle), "没装 npm 时更新检查应安全跳过")
    }

    // ── npm 源 + 全局 CLI 巡检（v2.14）───────────────────

    func testNpmPureParsers() {
        XCTAssertEqual(npmPkgName("npm:@guandata/guanskill"), "@guandata/guanskill")
        XCTAssertEqual(npmPkgName("NPM:@A/B"), "@a/b")
        XCTAssertNil(npmPkgName("github.com/a/b"))
        XCTAssertNil(npmPkgName("npm:"))
        XCTAssertNil(npmPkgName(nil))
        XCTAssertEqual(npmRegistryLatestURL("@guandata/guanskill")?.absoluteString,
                       "https://registry.npmjs.org/@guandata%2Fguanskill/latest")
        XCTAssertEqual(parseNpmRegistryLatest(Data(#"{"name":"x","version":"0.1.11"}"#.utf8)), "0.1.11")
        XCTAssertNil(parseNpmRegistryLatest(Data("oops".utf8)))
        let ls = #"{"dependencies":{"@larksuite/cli":{"version":"1.0.63"},"@getnote/cli":{"version":"1.1.8"}}}"#
        let parsed = parseNpmGlobalList(Data(ls.utf8))
        XCTAssertEqual(parsed["@larksuite/cli"], "1.0.63")
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parseNpmGlobalList(Data("{}".utf8)), [:])
    }

    func testNpmGlobalInstallRejectsInjection() {
        NpmEnv._setForTest("/usr/bin/true")   // 假装有 npm，让校验分支先跑到
        defer { NpmEnv._setForTest(nil) }
        XCTAssertThrowsError(try fs.npmGlobalInstall("a'; rm -rf ~", version: "1.0.0"))
        XCTAssertThrowsError(try fs.npmGlobalInstall("ok-pkg", version: "1.0.0 --evil"))
    }

    // ── well-known 源（v2.14）────────────────────────────

    func testWellKnownNormalizationAndHelpers() {
        XCTAssertEqual(StoreFS.normalizeSource("https://open.feishu.cn/.well-known/skills/lark-doc/SKILL.md"),
                       "wk:open.feishu.cn")
        XCTAssertEqual(SourceKind.of("wk:open.feishu.cn"), .wellKnown)
        XCTAssertEqual(SourceKind.of("https://open.feishu.cn/.well-known/skills/x/SKILL.md"), .wellKnown)
        XCTAssertEqual(wellKnownHost("https://open.feishu.cn/.well-known/skills/lark-doc/SKILL.md"), "open.feishu.cn")
        XCTAssertNil(wellKnownHost("https://github.com/a/b"))
        XCTAssertEqual(wellKnownSkillName("https://open.feishu.cn/.well-known/skills/lark-doc/SKILL.md"), "lark-doc")
        XCTAssertEqual(wellKnownSkillURL(host: "open.feishu.cn", name: "lark-im")?.absoluteString,
                       "https://open.feishu.cn/.well-known/skills/lark-im/SKILL.md")
    }

    func testWellKnownLockEntriesGroupIntoOneBundle() throws {
        // skills.sh 2026-06 改版后 lark 系的真实形态：lock 记 well-known URL。
        // 曾被 prefix(3) 截成 "open.feishu.cn/.well-known/skills" 当 github 源——
        // 套装名显示 ".well-known/skills"、checkUpdate 去 clone 必失败
        for n in ["lark-doc", "lark-im", "lark-base"] { try makeSkill(n) }
        try writeLock([
            "lark-doc":  ["source": "open.feishu.cn", "sourceUrl": "https://open.feishu.cn/.well-known/skills/lark-doc/SKILL.md"],
            "lark-im":   ["source": "open.feishu.cn", "sourceUrl": "https://open.feishu.cn/.well-known/skills/lark-im/SKILL.md"],
            "lark-base": ["source": "open.feishu.cn", "sourceUrl": "https://open.feishu.cn/.well-known/skills/lark-base/SKILL.md"],
        ])
        let entries = scan()
        let bundle = try XCTUnwrap(entries.first(where: \.isBundle))
        XCTAssertEqual(bundle.bundleKind, .source)
        XCTAssertEqual(bundle.name, "open.feishu.cn", "套装名 = 分发域名，不再是 .well-known/skills")
        XCTAssertEqual(bundle.sourceUrl, "wk:open.feishu.cn")
        XCTAssertEqual(bundle.children?.count, 3)
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
        XCTAssertEqual(imported.imported, ["wild-skill"])
        XCTAssertTrue(imported.skippedSameName.isEmpty)
        let entries = scan()
        XCTAssertEqual(entries.map(\.name), ["wild-skill"])
        XCTAssertEqual(entries[0].cap.status("claude"), .on, "原位应已换成 symlink")
        XCTAssertTrue(fs.isSymlink(wild))
    }

    // ── v2.16 打磨批：meta 防护 / 链接判定 / 物化收敛 / 回收站 / 导入 ──

    @MainActor
    func testAutoUpdateSurvivesRescanForSourceBundle() throws {
        // v2.16 修复的 P0：源式套装 id 是 "src:…"，曾拿它当 meta 键写、按 repoName 读——
        // 开关看似打开，任何一次 refresh 就悄悄回落
        for n in ["m-one", "m-two"] {
            try makeSkill(n)
            fs.mutateMeta { meta in
                meta.entries[n] = StoreMeta.EntryMeta(sourceUrl: "github.com/owner/repo")
            }
        }
        let model = AppModel(env: env)
        let bundle = try XCTUnwrap(model.entries.first(where: { $0.bundleKind == .source }),
                                   "两个同源成员应归拢成源式套装")
        XCTAssertEqual(bundle.id, "src:github.com/owner/repo")
        XCTAssertFalse(bundle.autoUpdate)
        model.toggleAutoUpdate(bundle.id)
        model.refresh()
        let again = try XCTUnwrap(model.entries.first(where: { $0.bundleKind == .source }))
        XCTAssertTrue(again.autoUpdate, "重扫后自动更新开关必须还开着（meta 键 = entry.name）")
    }

    func testGcMetaRemovesOrphanKeys() throws {
        try makeSkill("alive")
        fs.mutateMeta { meta in
            meta.entries["alive"] = StoreMeta.EntryMeta(sourceUrl: "github.com/o/alive")
            meta.entries["ghost"] = StoreMeta.EntryMeta(sourceUrl: "github.com/o/ghost", autoUpdate: true)
            meta.entries["src:github.com/o/r"] = StoreMeta.EntryMeta(autoUpdate: true)   // 历史写错键
        }
        fs.gcMeta(keep: ["alive"])
        let keys = Set(fs.loadMeta().entries.keys)
        XCTAssertEqual(keys, ["alive"], "孤儿键（终端删掉的条目/历史错键）应被清掉——它会让重装的同名技能继承前世 sourceUrl+autoUpdate")
    }

    func testLoadMetaCorruptedBacksUpInsteadOfSilentReset() throws {
        fs.saveLatest("x", latest: "新版")
        try "{ 这不是合法 JSON ——<<<<<<< git 冲突标记".write(to: fs.metaURL, atomically: true, encoding: .utf8)
        let meta = fs.loadMeta()
        XCTAssertTrue(meta.entries.isEmpty, "损坏时返回空 meta（不炸）")
        XCTAssertTrue(fs.metaCorruptBackupExists, "第一现场必须备份成 .corrupt")
        let backup = try String(contentsOf: fs.metaURL.appendingPathExtension("corrupt"), encoding: .utf8)
        XCTAssertTrue(backup.contains("git 冲突标记"), "备份保留损坏原文，人工可恢复")
    }

    func testLinkStatusWrongTargetReportsBroken() throws {
        let store = try makeSkill("right")
        let elsewhere = sandbox.appendingPathComponent("elsewhere-copy")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let link = claudeLink("right")
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: elsewhere)

        let (st, cause) = fs.linkStatus(linkPath: link, expectedTarget: store)
        XCTAssertEqual(st, .broken, "指到别处旧副本的链接不能谎报健康 on")
        XCTAssertTrue(cause?.contains(L("指向别处")) == true)
    }

    func testLinkStatusRelativeSymlinkToCorrectTargetIsOn() throws {
        // skills.sh CLI 写的是相对 symlink——正确目标的相对链必须仍判 on（回归兜底）
        let store = try makeSkill("relly")
        let linkDir = env.toolRoots["claude"]!.appendingPathComponent("skills")
        let link = linkDir.appendingPathComponent("relly")
        let rel = relativePath(from: linkDir, to: store)
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: rel)
        let (st, _) = fs.linkStatus(linkPath: link, expectedTarget: store)
        XCTAssertEqual(st, .on, "相对 symlink 指对目标应为 on")
    }

    private func relativePath(from: URL, to: URL) -> String {
        let f = from.standardizedFileURL.pathComponents
        let t = to.standardizedFileURL.pathComponents
        var i = 0
        while i < min(f.count, t.count), f[i] == t[i] { i += 1 }
        return Array(repeating: "..", count: f.count - i).joined(separator: "/") + "/" + t[i...].joined(separator: "/")
    }

    func testBundleChildLinksConvergeBackToWholeLink() throws {
        let dir = try makeBundle("suiteconv", children: ["ca", "cb"])
        let tool = tools.first { $0.id == "claude" }!
        try fs.setLink(tool: tool, kind: .bundle, name: "suiteconv", storeDir: dir, on: true)
        let bundleLink = claudeLink("suiteconv")
        XCTAssertTrue(fs.isSymlink(bundleLink), "初始整套一条 symlink")

        // 关一个子项 → 物化
        try fs.setBundleChildLink(tool: tool, bundleName: "suiteconv", bundleDir: dir,
                                  childName: "ca", allChildren: ["ca", "cb"], on: false)
        XCTAssertFalse(fs.isSymlink(bundleLink), "部分挂载 = 物化目录")

        // 再开回来 → 收敛回整链（v2.16：曾永久物化，上游新增子项默认漏挂）
        try fs.setBundleChildLink(tool: tool, bundleName: "suiteconv", bundleDir: dir,
                                  childName: "ca", allChildren: ["ca", "cb"], on: true)
        XCTAssertTrue(fs.isSymlink(bundleLink), "全 on 应收敛回整套一条 symlink")

        // 物化目录里混入真实文件：绝不收敛、绝不删用户数据
        try fs.setBundleChildLink(tool: tool, bundleName: "suiteconv", bundleDir: dir,
                                  childName: "cb", allChildren: ["ca", "cb"], on: false)
        try "user data".write(to: bundleLink.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try fs.setBundleChildLink(tool: tool, bundleName: "suiteconv", bundleDir: dir,
                                  childName: "cb", allChildren: ["ca", "cb"], on: true)
        XCTAssertFalse(fs.isSymlink(bundleLink), "有未知真实文件时保持物化")
        XCTAssertTrue(fm.fileExists(atPath: bundleLink.appendingPathComponent("notes.txt").path))
    }

    func testRemoveEntryCleansDSStoreOnlyMaterializedDir() throws {
        let dir = try makeBundle("suiteghost", children: ["g1"])
        let tool = tools.first { $0.id == "claude" }!
        try fs.setLink(tool: tool, kind: .bundle, name: "suiteghost", storeDir: dir, on: true)
        try fs.setBundleChildLink(tool: tool, bundleName: "suiteghost", bundleDir: dir,
                                  childName: "g1", allChildren: ["g1"], on: false)
        let bundleLink = claudeLink("suiteghost")
        try Data().write(to: bundleLink.appendingPathComponent(".DS_Store"))   // Finder 逛过一次

        let entry = scan().first { $0.name == "suiteghost" }!
        try fs.removeEntry(entry, tools: tools)
        XCTAssertFalse(fm.fileExists(atPath: bundleLink.path),
                       "只剩 .DS_Store 的物化目录不该留成 UI 看不见的幽灵")
    }

    func testImportUnmanagedReportsSkippedAndCleansHalfCopy() throws {
        try makeSkill("occupied")   // store 已有同名
        let wild = claudeLink("occupied")
        try fm.createDirectory(at: wild, withIntermediateDirectories: true)
        try "---\nname: occupied\n---\n".write(to: wild.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let fresh = claudeLink("fresh-one")
        try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
        try "---\nname: fresh-one\n---\n".write(to: fresh.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let r = try fs.importUnmanaged([
            StoreFS.UnmanagedDir(name: "occupied", toolId: "claude", url: wild),
            StoreFS.UnmanagedDir(name: "fresh-one", toolId: "claude", url: fresh),
        ])
        XCTAssertEqual(r.imported, ["fresh-one"])
        XCTAssertEqual(r.skippedSameName, ["occupied"], "同名跳过要报账，不再静默吞")
    }

    func testEmptyTrash() throws {
        let a = try makeSkill("trashme")
        try fs.moveToTrash(a)
        XCTAssertFalse(fs.listTrash().isEmpty)
        try fs.emptyTrash()
        XCTAssertTrue(fs.listTrash().isEmpty)
    }

    func testNpmWebURLRecognizedAsNpmSource() {
        XCTAssertEqual(SourceKind.of("https://www.npmjs.com/package/@guandata/guanskill"), .npm,
                       "npmjs.com 包页 URL 应认成 npm 源，让引导语有机会出场")
        XCTAssertEqual(npmPkgName("https://www.npmjs.com/package/@guandata/guanskill?activeTab=readme"),
                       "@guandata/guanskill")
        XCTAssertEqual(npmPkgName("npm:@guandata/guanskill"), "@guandata/guanskill")
        XCTAssertNil(npmPkgName("github.com/owner/repo"))
    }

    // ── Marketplace 插件只读层（v2.6）────────────────────

    func testMarketplacePluginScanReadOnly() throws {
        // 仿真 ~/.claude/plugins：installed_plugins.json v2 + known_marketplaces + cache/skills
        let claude = env.toolRoots["claude"]!
        let plugins = claude.appendingPathComponent("plugins")
        let install = plugins.appendingPathComponent("cache/mkt/dbs/1.0.0")
        for n in ["dbs-hook", "dbs-save"] {
            let d = install.appendingPathComponent("skills/\(n)")
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try "---\nname: \(n)\ndescription: 测试 \(n)\n---\n正文。\n".write(
                to: d.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        try JSONSerialization.data(withJSONObject: [
            "version": 2,
            "plugins": ["dbs@mkt": [["scope": "user", "installPath": install.path, "version": "1.0.0"]]],
        ]).write(to: plugins.appendingPathComponent("installed_plugins.json"))
        try JSONSerialization.data(withJSONObject: [
            "mkt": ["source": ["source": "github", "repo": "dontbesilent2025/dbskill"]],
        ]).write(to: plugins.appendingPathComponent("known_marketplaces.json"))

        let entries = scan()
        let plugin = try XCTUnwrap(entries.first { $0.bundleKind == .marketplace })
        XCTAssertEqual(plugin.name, "dbs")
        XCTAssertEqual(plugin.cap.version, "1.0.0")
        XCTAssertEqual(plugin.sourceUrl, "github.com/dontbesilent2025/dbskill")
        XCTAssertEqual(plugin.children?.count, 2)
        XCTAssertEqual(plugin.children?.first?.status("claude"), .on, "插件由 Claude 加载")
        XCTAssertEqual(plugin.children?.first?.status("codex"), .off, "Codex 不消费插件")
        // 只读三守卫
        XCTAssertThrowsError(try fs.removeEntry(plugin, tools: tools), "引擎层必须拒删插件")
        XCTAssertNil(try fs.checkUpdate(plugin), "插件更新检查必须跳过")
        XCTAssertTrue(plugin.isManagedExternally)
    }

    // ── 元数据 ───────────────────────────────────────────

    func testMetaRoundtrip() throws {
        var meta = StoreMeta()
        meta.entries["foo"] = StoreMeta.EntryMeta(sourceUrl: "github.com/a/b", autoUpdate: true, latest: "2 项", changed: ["x", "y"])
        meta.tools["claude"] = StoreMeta.ToolMeta(defaultTarget: false)
        fs.saveMeta(meta)
        let loaded = fs.loadMeta()
        XCTAssertEqual(loaded.entries["foo"]?.sourceUrl, "github.com/a/b")
        XCTAssertEqual(loaded.entries["foo"]?.autoUpdate, true)
        XCTAssertEqual(loaded.entries["foo"]?.changed, ["x", "y"], "变更成员名要能持久化往返")
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

    func testStatsByTypeAndInactive() throws {
        // 顶部统计条派生（v2.13）：类型计数走摊平后的 cap，Bundle = 套装数
        try makeSkill("solo-skill")                                  // 独立 skill
        try makeBundle("kit", children: ["a", "b", "c"])             // 套装 + 3 子 skill
        let agentsDir = env.storeRoot.appendingPathComponent("agents")
        try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        let ag = try makeSkill("my-agent", in: agentsDir)            // 1 个 agent
        try fm.createSymbolicLink(at: claudeLink("solo-skill"),
                                  withDestinationURL: env.storeRoot.appendingPathComponent("skills/solo-skill"))

        let entries = scan()
        let s = deriveStats(entries, tools: tools)
        XCTAssertEqual(s.byType[.skill], 4, "solo + 套装 3 子项都是 skill")
        XCTAssertEqual(s.byType[.agent], 1)
        XCTAssertEqual(s.byType[.bundle], 1, "Bundle 计套装数，不是子项数")
        XCTAssertEqual(s.byType[.mcp] ?? 0, 0)
        // 激活/未挂载拆分：只 solo-skill 在 claude 侧 on，其余未挂载
        XCTAssertEqual(s.activeByTool["claude"], 1)
        XCTAssertEqual(s.inactiveByTool["claude"], s.total - 1)
        XCTAssertEqual(s.activeByTool["codex"], 0)
        XCTAssertEqual(s.inactiveByTool["codex"], s.total)
        _ = ag
    }

    // ── v2.17：上游新增 / 回收站 meta / 四 kind 未托管 ──

    func testSaveUpstreamNewSurvivesScan() throws {
        try makeSkill("a1")
        try makeSkill("a2")
        fs.mutateMeta { meta in
            meta.entries["a1"] = StoreMeta.EntryMeta(sourceUrl: "github.com/owner/repo")
            meta.entries["a2"] = StoreMeta.EntryMeta(sourceUrl: "github.com/owner/repo")
            meta.entries["owner/repo"] = StoreMeta.EntryMeta(
                sourceUrl: "github.com/owner/repo", upstreamNew: ["a3", "a4"])
        }
        let entries = scan()
        let bundle = try XCTUnwrap(entries.first(where: { $0.bundleKind == .source }))
        XCTAssertEqual(bundle.upstreamNew, ["a3", "a4"])
        XCTAssertEqual(bundle.upstreamNewCount, 2)
        XCTAssertTrue(bundle.hasUpstreamNew)
        XCTAssertFalse(bundle.hasUpdate)
    }

    func testInstallUpstreamMembersFromLocalStaging() throws {
        // 本地 monorepo 源：skills/ 下有 a1（已装）和 a-new（未装）
        let monorepo = sandbox.appendingPathComponent("upstream-repo")
        try makeSkill("a1", in: monorepo.appendingPathComponent("skills"))
        try makeSkill("a-new", desc: "上游新增", in: monorepo.appendingPathComponent("skills"))
        // store 只装 a1，同源
        try makeSkill("a1")
        fs.mutateMeta { meta in
            meta.entries["a1"] = StoreMeta.EntryMeta(sourceUrl: monorepo.path)
            meta.entries["a1"]?.sourceUrl = monorepo.path
            // 独立条目源
            meta.entries["a1"] = StoreMeta.EntryMeta(sourceUrl: monorepo.path, upstreamNew: ["a-new"])
        }
        // 再扫：单源只有一个成员不会归拢成套装
        var entries = scan()
        var entry = try XCTUnwrap(entries.first(where: { $0.name == "a1" }))
        entry.sourceUrl = monorepo.path
        entry.upstreamNew = ["a-new"]
        let installed = try fs.installUpstreamMembers(entry, names: ["a-new"], linkTools: tools)
        XCTAssertEqual(installed, ["a-new"])
        entries = scan()
        XCTAssertTrue(entries.contains(where: { $0.name == "a-new" || ($0.children ?? []).contains(where: { $0.name == "a-new" }) }))
        let dest = env.storeRoot.appendingPathComponent("skills/a-new")
        XCTAssertTrue(fm.fileExists(atPath: dest.path))
        // 已挂载默认工具
        XCTAssertTrue(fs.isSymlink(claudeLink("a-new")))
    }

    func testTrashRestoreRestoresMetaSourceUrl() throws {
        let dir = try makeSkill("keep-src")
        fs.mutateMeta { meta in
            meta.entries["keep-src"] = StoreMeta.EntryMeta(
                sourceUrl: "github.com/owner/keep-src", autoUpdate: true)
        }
        let entry = try XCTUnwrap(scan().first(where: { $0.name == "keep-src" }))
        try fs.removeEntry(entry, tools: tools)
        XCTAssertNil(fs.loadMeta().entries["keep-src"], "移除后 meta 键应清掉")
        let item = try XCTUnwrap(fs.listTrash().first(where: { $0.name == "keep-src" }))
        // 快照应在回收站目录内
        XCTAssertTrue(fm.fileExists(atPath: item.url.appendingPathComponent(".popskill-meta.json").path))
        try fs.restoreFromTrash(item)
        let restored = fs.loadMeta().entries["keep-src"]
        XCTAssertEqual(restored?.sourceUrl, "github.com/owner/keep-src")
        XCTAssertEqual(restored?.autoUpdate, true)
        XCTAssertNil(restored?.latest, "恢复后检查点清空，避免误亮徽标")
        XCTAssertTrue(fm.fileExists(atPath: env.storeRoot.appendingPathComponent("skills/keep-src").path))
        _ = dir
    }

    func testScanUnmanagedFourKinds() throws {
        // skill
        let wildSkill = claudeLink("wild-skill")
        try fm.createDirectory(at: wildSkill, withIntermediateDirectories: true)
        try "---\nname: wild-skill\ndescription: s\n---\n".write(
            to: wildSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        // agent
        let agents = env.toolRoots["claude"]!.appendingPathComponent("agents")
        try fm.createDirectory(at: agents, withIntermediateDirectories: true)
        let wildAgent = agents.appendingPathComponent("wild-agent")
        try fm.createDirectory(at: wildAgent, withIntermediateDirectories: true)
        try "# agent\n".write(to: wildAgent.appendingPathComponent("AGENT.md"), atomically: true, encoding: .utf8)
        // mcp
        let mcp = env.toolRoots["claude"]!.appendingPathComponent("mcp")
        let wildMcp = mcp.appendingPathComponent("wild-mcp")
        try fm.createDirectory(at: wildMcp, withIntermediateDirectories: true)
        // cli
        let bin = env.toolRoots["claude"]!.appendingPathComponent("bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try "#!/bin/sh\necho hi\n".write(to: bin.appendingPathComponent("wild-cli"), atomically: true, encoding: .utf8)

        let found = fs.scanUnmanaged(tools: tools, knownNames: [])
        let byKind = Dictionary(grouping: found, by: \.kind)
        XCTAssertEqual(byKind[.skill]?.map(\.name), ["wild-skill"])
        XCTAssertEqual(byKind[.agent]?.map(\.name), ["wild-agent"])
        XCTAssertEqual(byKind[.mcp]?.map(\.name), ["wild-mcp"])
        XCTAssertEqual(byKind[.cli]?.map(\.name), ["wild-cli"])

        let r = try fs.importUnmanaged(found)
        XCTAssertEqual(Set(r.imported), Set(["wild-skill", "wild-agent", "wild-mcp", "wild-cli"]))
        XCTAssertTrue(fm.fileExists(atPath: env.storeRoot.appendingPathComponent("skills/wild-skill").path))
        XCTAssertTrue(fm.fileExists(atPath: env.storeRoot.appendingPathComponent("agents/wild-agent").path))
        XCTAssertTrue(fm.fileExists(atPath: env.storeRoot.appendingPathComponent("mcp/wild-mcp").path))
        XCTAssertTrue(fm.fileExists(atPath: env.storeRoot.appendingPathComponent("bin/wild-cli").path))
        XCTAssertTrue(fs.isSymlink(wildSkill))
        XCTAssertTrue(fs.isSymlink(wildAgent))
    }

    func testHasUpdateIgnoresEmptyLatest() {
        var e = Entry(id: "x", cap: Capability(
            id: "x", name: "x", type: .skill, desc: "", version: nil, author: nil,
            tokens: 0, dirURL: URL(fileURLWithPath: "/tmp")), children: nil, latest: "")
        XCTAssertFalse(e.hasUpdate)
        e.latest = "1.2.0"
        XCTAssertTrue(e.hasUpdate)
        e.upstreamNew = ["n1"]
        XCTAssertEqual(e.upstreamNewCount, 1)
    }
}
