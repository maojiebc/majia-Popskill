import XCTest
@testable import Popskill

final class WorkModeTests: XCTestCase {
    private func cap(_ name: String, claude: LinkStatus, codex: LinkStatus = .off) -> Capability {
        var c = Capability(
            id: typedId(.skill, name), name: name, type: .skill, desc: "",
            version: nil, author: nil, tokens: 0,
            dirURL: URL(fileURLWithPath: "/tmp/\(name)"))
        c.links = ["claude": claude, "codex": codex]
        return c
    }

    private var tools: [Tool] {
        let home = URL(fileURLWithPath: "/tmp")
        return [
            Tool(id: "claude", name: "Claude Code", root: home.appendingPathComponent("claude"),
                 connected: true, defaultTarget: true),
            Tool(id: "codex", name: "Codex CLI", root: home.appendingPathComponent("codex"),
                 connected: true, defaultTarget: true),
        ]
    }

    func testCaptureWritesEmptyArrayNotMissingKey() {
        let e = Entry(id: typedId(.skill, "a"), cap: cap("a", claude: .off), children: nil)
        let snap = captureWorkSnapshot(entries: [e], tools: tools)
        XCTAssertEqual(snap["claude"], [])
        XCTAssertEqual(snap["codex"], [])
        XCTAssertNil(snap["grok"], "没出现的工具列不应进快照")
    }

    func testCaptureSkipsMarketplace() {
        var kid = cap("plug", claude: .on)
        kid.links = ["claude": .on, "codex": .off]
        let plugin = Entry(
            id: "plugin:demo", cap: kid, children: [kid],
            bundleKind: .marketplace, sourceUrl: "github.com/x/y")
        let snap = captureWorkSnapshot(entries: [plugin], tools: tools)
        XCTAssertEqual(snap["claude"], [], "Marketplace 不入工作模式")
    }

    func testDiffEmptyArrayMeansAllOff() {
        let e = Entry(id: typedId(.skill, "a"), cap: cap("a", claude: .on, codex: .on), children: nil)
        let changes = diffWorkSnapshot(
            desired: ["claude": [], "codex": [typedId(.skill, "a")]],
            entries: [e], tools: tools)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].toolId, "claude")
        XCTAssertEqual(changes[0].turnOff, ["a"])
        XCTAssertTrue(changes[0].turnOn.isEmpty)
    }

    func testDiffSkipsUnknownToolAndReportsMissingCap() {
        let e = Entry(id: typedId(.skill, "a"), cap: cap("a", claude: .off), children: nil)
        let changes = diffWorkSnapshot(
            desired: [
                "mystery": ["skill:ghost"],
                "claude": [typedId(.skill, "a"), "skill:ghost"],
            ],
            entries: [e], tools: tools)
        XCTAssertEqual(changes.map(\.toolId), ["claude"])
        XCTAssertEqual(changes[0].turnOn, ["a"])
        XCTAssertEqual(changes[0].missing, ["skill:ghost"])
    }

    func testDiffBlocksStubAndBroken() {
        let e = Entry(id: typedId(.skill, "a"), cap: cap("a", claude: .stub), children: nil)
        let changes = diffWorkSnapshot(
            desired: ["claude": [typedId(.skill, "a")]],
            entries: [e], tools: tools)
        XCTAssertEqual(changes[0].blocked, ["a"])
        XCTAssertTrue(changes[0].turnOn.isEmpty)
    }

    func testSnapshotMatchIgnoresExtraCurrentTools() {
        let desired = ["claude": ["skill:a"]]
        let current = ["claude": ["skill:a"], "codex": ["skill:b"]]
        XCTAssertTrue(workSnapshotMatches(desired: desired, current: current),
                      "模式没写的工具不参与脏检测")
        XCTAssertFalse(workSnapshotMatches(
            desired: ["claude": ["skill:a"]], current: ["claude": ["skill:b"]]))
    }

    func testToolRegistryPaths() {
        let roots = StoreEnv.toolRoots(at: URL(fileURLWithPath: "/tmp/base"))
        XCTAssertEqual(roots["claude"]?.path, "/tmp/base/.claude")
        XCTAssertEqual(roots["pi"]?.path, "/tmp/base/.pi/agent")
        XCTAssertEqual(roots["opencode"]?.path, "/tmp/base/.config/opencode")
        XCTAssertEqual(ToolDef.builtins.filter(\.alwaysShow).map(\.id), ["claude", "codex"])
    }
}
