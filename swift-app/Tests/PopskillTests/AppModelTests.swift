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
}
