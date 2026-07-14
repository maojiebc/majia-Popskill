import XCTest
@testable import Popskill

/// AppModel 纯逻辑测试（v2.8）：修复推荐矩阵与键盘导航状态机。
/// 全部跑在临时沙盘 StoreEnv 上，不碰真实 ~/.agents。
@MainActor
final class AppModelTests: XCTestCase {
    var sandbox: URL!
    var model: AppModel!
    let fm = FileManager.default

    override func setUp() {
        super.setUp()
        setenv("POPSKILL_NO_AUTOCHECK", "1", 1)
        sandbox = fm.temporaryDirectory.appendingPathComponent("popskill-am-\(UUID().uuidString.prefix(8))")
        let store = sandbox.appendingPathComponent("agents")
        try? fm.createDirectory(at: store.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: sandbox.appendingPathComponent("claude/skills"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: sandbox.appendingPathComponent("codex/skills"), withIntermediateDirectories: true)
        model = AppModel(env: StoreEnv(storeRoot: store, toolRoots: [
            "claude": sandbox.appendingPathComponent("claude"),
            "codex": sandbox.appendingPathComponent("codex"),
        ]))
    }

    override func tearDown() {
        try? fm.removeItem(at: sandbox)
        super.tearDown()
    }

    private func makeCap(_ name: String, dirExists: Bool) -> Capability {
        let dir = sandbox.appendingPathComponent("agents/skills/\(name)")
        if dirExists { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        return Capability(id: name, name: name, type: .skill, desc: "",
                          version: nil, author: nil, tokens: 0, dirURL: dir)
    }

    private var tool: Tool {
        Tool(id: "claude", name: "Claude Code",
             root: sandbox.appendingPathComponent("claude"), connected: true, defaultTarget: true)
    }

    private func target(_ kind: LinkStatus, cap: Capability, entry: Entry) -> FixTarget {
        FixTarget(issueKind: kind, cap: cap, entry: entry, tool: tool, anchor: .zero, flip: false)
    }

    // ── 修复推荐矩阵：推荐必须唯一（有更新 > store 健在重链 > 重拉）──

    func testFixOptionsBrokenWithUpdateRecommendsUpdate() {
        let c = makeCap("x", dirExists: true)
        let e = Entry(id: "x", cap: c, children: nil, sourceUrl: "github.com/o/r", latest: "2.0")
        let opts = model.fixOptions(for: target(.broken, cap: c, entry: e))
        XCTAssertEqual(opts.filter(\.rec).count, 1, "推荐必须唯一")
        XCTAssertEqual(opts.first(where: \.rec)?.kind, .update)
    }

    func testFixOptionsBrokenStoreAliveRecommendsRelink() {
        let c = makeCap("y", dirExists: true)
        let e = Entry(id: "y", cap: c, children: nil, sourceUrl: "github.com/o/r")
        let opts = model.fixOptions(for: target(.broken, cap: c, entry: e))
        XCTAssertEqual(opts.filter(\.rec).count, 1)
        XCTAssertEqual(opts.first(where: \.rec)?.kind, .relink)
        XCTAssertTrue(opts.contains { $0.kind == .repull }, "github 源应提供重拉选项")
    }

    func testFixOptionsBrokenStoreGoneRecommendsRepull() {
        let c = makeCap("z", dirExists: false)
        let e = Entry(id: "z", cap: c, children: nil, sourceUrl: "github.com/o/r")
        let opts = model.fixOptions(for: target(.broken, cap: c, entry: e))
        XCTAssertEqual(opts.first(where: \.rec)?.kind, .repull)
        XCTAssertFalse(opts.contains { $0.kind == .relink }, "store 副本没了不该出现重链")
    }

    func testFixOptionsStubRecommendsAdopt() {
        let c = makeCap("s", dirExists: true)
        let e = Entry(id: "s", cap: c, children: nil)
        let opts = model.fixOptions(for: target(.stub, cap: c, entry: e))
        XCTAssertEqual(opts.map(\.kind), [.adopt, .trashCopy, .keep])
        XCTAssertEqual(opts.first(where: \.rec)?.kind, .adopt)
    }

    // ── 键盘导航状态机 ────────────────────────────────────

    func testKbMoveClampsAndEntersFromEdge() {
        model.kbFocusList = ["a", "b", "c"].map { KbItem(id: $0, isBundle: false, entryId: $0, capId: $0) }
        model.kbMove(1)
        XCTAssertEqual(model.kbFocusId, "a", "从无焦点向下应落在第一项")
        model.kbMove(-1)
        XCTAssertEqual(model.kbFocusId, "a", "顶端继续向上应钉住")
        model.kbMove(1); model.kbMove(1); model.kbMove(5)
        XCTAssertEqual(model.kbFocusId, "c", "底端越界应钉住")
    }

    func testKbMoveOnEmptyListIsNoop() {
        model.kbFocusList = []
        model.kbMove(1)
        XCTAssertNil(model.kbFocusId)
    }

    func testKbSetToolClamps() {
        model.kbFocusList = [KbItem(id: "a", isBundle: false, entryId: "a", capId: "a")]
        model.kbMove(1)
        model.kbSetTool(99)
        XCTAssertEqual(model.kbToolIdx, model.tools.count - 1)
        model.kbSetTool(-3)
        XCTAssertEqual(model.kbToolIdx, 0)
    }

    func testKbValidateClearsVanishedFocus() {
        model.kbFocusList = [KbItem(id: "a", isBundle: false, entryId: "a", capId: "a")]
        model.kbMove(1)
        model.kbFocusList = []
        model.kbValidate()
        XCTAssertNil(model.kbFocusId, "焦点项从可见列表消失后必须清除")
    }

    // ── 更新计数与跳转（v2.14）───────────────────────────

    private func entryWithUpdate(_ id: String, children: [String]? = nil, changed: [String]? = nil) -> Entry {
        let cap = makeCap(id, dirExists: false)
        return Entry(id: id, cap: cap,
                     children: children?.map { makeCap($0, dirExists: false) },
                     bundleKind: children != nil ? .source : nil,
                     sourceUrl: "github.com/t/\(id)",
                     latest: "新版", changedMembers: changed)
    }

    func testUpdateCountCountsMembersNotSources() {
        // 用户之痛：套装里 5 个成员待更新，横幅只写 1——计数必须是技能数
        let solo = entryWithUpdate("solo")
        let bundle = entryWithUpdate("pack", children: ["a", "b", "c", "d", "e"], changed: ["a", "b", "c", "d", "e"])
        let legacy = entryWithUpdate("legacy", children: ["x", "y"], changed: nil)   // 旧 meta 无明细
        model.entries = [solo, bundle, legacy]
        XCTAssertEqual(solo.updateCount, 1)
        XCTAssertEqual(bundle.updateCount, 5)
        XCTAssertEqual(legacy.updateCount, 1, "缺明细保守计 1")
        XCTAssertEqual(model.updateItemCount, 7)
        var fresh = solo
        fresh.latest = nil
        XCTAssertEqual(fresh.updateCount, 0)
    }

    func testJumpToNextUpdateCyclesExpandsAndClearsFilter() {
        let a = entryWithUpdate("aaa", children: ["a1", "a2"], changed: ["a1"])
        let b = entryWithUpdate("bbb")
        var clean = entryWithUpdate("ccc")
        clean.latest = nil
        model.entries = [a, b, clean]
        model.query = "挡视线的搜索词"
        model.typeFilter = .mcp
        model.jumpToNextUpdate()
        XCTAssertEqual(model.kbFocusId, "aaa")
        XCTAssertTrue(model.expanded.contains("aaa"), "套装必须展开露出待更新成员")
        XCTAssertEqual(model.flashId, "aaa")
        XCTAssertEqual(model.query, "", "跳转意图优先于过滤")
        XCTAssertNil(model.typeFilter)
        model.jumpToNextUpdate()
        XCTAssertEqual(model.kbFocusId, "bbb")
        model.jumpToNextUpdate()
        XCTAssertEqual(model.kbFocusId, "aaa", "到尾后循环回第一个")
    }

    // ── v2.17 深链接 / 上游新增定位 ──

    func testHandleDeepLinkInstallPrefillsAddSheet() {
        let url = URL(string: "popskill://install?src=github.com/anthropics/skills")!
        model.handleDeepLink(url)
        XCTAssertEqual(model.sheet, .add)
        XCTAssertEqual(model.pendingAddURL, "github.com/anthropics/skills")
    }

    func testHandleDeepLinkInstallWithUrlQuery() {
        let url = URL(string: "popskill://install?url=https://github.com/foo/bar")!
        model.handleDeepLink(url)
        XCTAssertEqual(model.pendingAddURL, "https://github.com/foo/bar")
        XCTAssertEqual(model.sheet, .add)
    }

    func testHandleDeepLinkUnknownHost() {
        model.sheet = nil
        model.handleDeepLink(URL(string: "popskill://settings")!)
        XCTAssertNil(model.sheet)
    }

    func testJumpToNextUpstreamNew() {
        var a = entryWithUpdate("src-a", children: ["x"], changed: nil)
        a.latest = nil
        a.upstreamNew = ["new-1", "new-2"]
        var b = entryWithUpdate("src-b")
        b.latest = nil
        b.upstreamNew = ["new-3"]
        var clean = entryWithUpdate("src-c")
        clean.latest = nil
        model.entries = [a, b, clean]
        XCTAssertEqual(model.upstreamNewItemCount, 3)
        model.query = "noise"
        model.jumpToNextUpstreamNew()
        XCTAssertEqual(model.kbFocusId, "src-a")
        XCTAssertEqual(model.query, "")
        model.jumpToNextUpstreamNew()
        XCTAssertEqual(model.kbFocusId, "src-b")
    }

    // ── v2.18.1：语言判定与大小写形态无关（坑 #22）────────

    /// SwiftPM 把资源 bundle 的 lproj 目录名小写成 zh-hans，Bundle.localizations
    /// 返回磁盘真实名，协商结果就是 "zh-hans"——曾拿它跟 "zh-Hans" 裸比判 false，
    /// 中文界面下 Catalog 精选目录整片走英文面（v2.14 起潜伏三版）
    func testLangIsChineseIgnoresTagShape() {
        XCTAssertTrue(l10nLangIsChinese("zh-hans"), "SwiftPM 产物的真实形态——本 bug 的现场")
        XCTAssertTrue(l10nLangIsChinese("zh-Hans"), "catalog 里的标准形态")
        XCTAssertTrue(l10nLangIsChinese("zh-Hans-CN"))
        XCTAssertTrue(l10nLangIsChinese("zh_CN"))
        XCTAssertTrue(l10nLangIsChinese("zh"))
        XCTAssertFalse(l10nLangIsChinese("en"))
        XCTAssertFalse(l10nLangIsChinese("en-US"))
        XCTAssertFalse(l10nLangIsChinese(""))
        XCTAssertFalse(l10nLangIsChinese("zhuang"), "zh 前缀不等于中文，要认边界")
    }

    /// 协商 → 判定 全链（纯函数，锁死真实现场的输入形态）。
    /// available 必须写 SwiftPM 产物的**小写** "zh-hans"——测试进程里资源 bundle
    /// 找不到会走兜底 lang="zh-Hans"，断言全局 l10nIsChinese 是结构性假绿，
    /// 拿 bug 版代码也照过；只有喂真实形态的纯函数才抓得住（v2.18.1 实撞）
    func testLangNegotiationUnderSwiftPMLowercasedLproj() {
        let available = ["zh-hans", "en"]   // = Bundle.localizations 在真实 .app 里的值
        let picked = l10nLangCandidates(available: available, prefs: ["zh-Hans-CN"]).first
        XCTAssertEqual(picked, "zh-hans", "协商返回目录真实名，不是标准 tag")
        XCTAssertTrue(l10nLangIsChinese(picked ?? ""), "中文系统下必须判成中文——Catalog 靠它挑面")
        // 英文系统仍要落英文
        let en = l10nLangCandidates(available: available, prefs: ["en-US"]).first
        XCTAssertFalse(l10nLangIsChinese(en ?? ""))
        // 不支持的语言 → en 兜底
        let fallback = l10nLangCandidates(available: available, prefs: ["fr-FR"])
        XCTAssertTrue(fallback.contains("en"))
        XCTAssertFalse(l10nLangIsChinese(fallback.first ?? ""))
    }

    /// 挑面逻辑本身：中文取 desc、英文取 en、缺 en 落回 desc
    func testCatalogLocalizedDescPicksSide() {
        let e = CatalogEntry(desc: "中文简介", en: "English blurb")
        XCTAssertEqual(e.localizedDesc(chinese: true), "中文简介")
        XCTAssertEqual(e.localizedDesc(chinese: false), "English blurb")
        XCTAssertEqual(CatalogEntry(desc: "只有中文").localizedDesc(chinese: false), "只有中文", "缺英文落回中文")
    }
}
