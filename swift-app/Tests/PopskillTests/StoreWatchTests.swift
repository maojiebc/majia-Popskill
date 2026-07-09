import XCTest
@testable import Popskill

/// FSEvents 监听器测试（v2.15）——真文件系统、低 latency。
/// 写文件必须走外部进程（/usr/bin/touch）：生产流配了 IgnoreSelf，
/// 本进程自己的写会被滤掉——这恰好也是对「终端写入能触发」这条核心假设的验证。
final class StoreWatchTests: XCTestCase {
    var dir: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("popskill-watch-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    func testExternalWriteFiresOnChange() throws {
        let exp = expectation(description: "onChange")
        exp.assertForOverFulfill = false   // 一批事件可能多次回调，只关心「有」
        let w = StoreWatcher(latency: 0.05) { exp.fulfill() }
        defer { w.stop() }
        w.sync(paths: [dir.path])
        XCTAssertEqual(w.watchedPaths, [dir.path])
        Thread.sleep(forTimeInterval: 0.3)   // 流从「现在」起算，给启动一点余量

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
        p.arguments = [dir.appendingPathComponent("SKILL.md").path]
        try p.run()
        p.waitUntilExit()

        wait(for: [exp], timeout: 5)
    }

    func testSyncPrunesMissingAndIsIdempotent() throws {
        let w = StoreWatcher(latency: 0.05) {}
        defer { w.stop() }
        let ghost = dir.appendingPathComponent("not-there").path
        w.sync(paths: [ghost, dir.path])
        XCTAssertEqual(w.watchedPaths, [dir.path], "不存在的路径不进监听集")
        w.sync(paths: [dir.path, ghost])
        XCTAssertEqual(w.watchedPaths, [dir.path], "同一集合换序重 sync 幂等")
        w.sync(paths: [ghost])
        XCTAssertEqual(w.watchedPaths, [], "全部路径消失即停流")
        w.stop()
        XCTAssertEqual(w.watchedPaths, [])
    }

    /// v2.17：store 根消失后改听父目录，重建后换回 store
    func testSyncSwitchesToParentWhenStoreMissingThenBack() throws {
        let store = dir.appendingPathComponent("agents")
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        let parent = dir.path
        let w = StoreWatcher(latency: 0.05) {}
        defer { w.stop() }
        w.sync(paths: [store.path])
        XCTAssertEqual(w.watchedPaths, [store.path])
        try fm.removeItem(at: store)
        // 模拟 AppModel.syncWatchPaths：根没了听父目录
        w.sync(paths: [parent])
        XCTAssertEqual(w.watchedPaths, [parent])
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        w.sync(paths: [store.path])
        XCTAssertEqual(w.watchedPaths, [store.path], "重建后应换回只听 store")
    }
}

/// 全链集成：终端动 store → AppModel 自动重扫（startWatching → 去抖 → refresh）。
/// 用生产默认参数（1s 合并窗口），验证的是接线而不只是 FSEvents 本身。
@MainActor
final class StoreWatchIntegrationTests: XCTestCase {
    func testExternalStoreWriteAutoRefreshesModel() async throws {
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory.appendingPathComponent("popskill-watchint-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: sandbox) }
        let store = sandbox.appendingPathComponent("agents")
        try fm.createDirectory(at: store.appendingPathComponent("skills/alpha"), withIntermediateDirectories: true)
        try "---\nname: alpha\ndescription: 初始技能\n---\n".write(
            to: store.appendingPathComponent("skills/alpha/SKILL.md"), atomically: true, encoding: .utf8)
        let env = StoreEnv(storeRoot: store, toolRoots: [
            "claude": sandbox.appendingPathComponent("claude"),
            "codex": sandbox.appendingPathComponent("codex"),
        ])

        let model = AppModel(env: env)
        model.startWatching()
        XCTAssertEqual(model.entries.map(\.name), ["alpha"])

        // 外部进程加一个技能目录（IgnoreSelf 滤不掉它——这就是终端场景）
        let beta = store.appendingPathComponent("skills/beta")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "mkdir -p '\(beta.path)' && printf -- '---\\nname: beta\\ndescription: 终端新增\\n---\\n' > '\(beta.path)/SKILL.md'"]
        try p.run()
        p.waitUntilExit()

        // 1s 合并窗口 + 350ms 尾去抖 + 调度余量：轮询到 8s
        for _ in 0..<160 where model.entries.count < 2 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(model.entries.map(\.name).sorted(), ["alpha", "beta"],
                       "终端新增技能后模型应自动跟上，无需 ⌘R/切前台")
    }
}
