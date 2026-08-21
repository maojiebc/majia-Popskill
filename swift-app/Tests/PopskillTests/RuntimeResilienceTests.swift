import CoreServices
import XCTest
@testable import Popskill

final class RuntimeResilienceTests: XCTestCase {
    func testNpmPackagePageWithoutPackageReturnsNilInsteadOfCrashing() {
        XCTAssertNil(npmPkgName("https://www.npmjs.com/package/"))
        XCTAssertNil(npmPkgName("https://www.npmjs.com/package/?activeTab=readme"))
        XCTAssertNil(npmPkgName("https://www.npmjs.com/package/#readme"))
    }

    func testNpmPackagePageKeepsScopedNameAndDropsQueryOrFragment() {
        XCTAssertEqual(
            npmPkgName("https://www.npmjs.com/package/@Scope/Package?activeTab=readme#usage"),
            "@scope/package"
        )
    }

    func testOptionalAppDetectionIncludesUserApplicationsDirectory() {
        let cursor = ToolDef(
            id: "cursor",
            name: "Cursor",
            rootRelative: ".cursor",
            alwaysShow: true,
            appBundle: "Cursor.app"
        )
        let home = "/Users/tester"
        let userApp = "/Users/tester/Applications/Cursor.app"
        var checked: [String] = []

        let presence = cursor.presence(
            fileExists: { path in
                checked.append(path)
                return path == userApp
            },
            isExecutable: { _ in false },
            home: home,
            pathEnv: ""
        )

        XCTAssertEqual(presence, .app("Cursor.app"))
        XCTAssertEqual(checked, ["/Applications/Cursor.app", userApp])
    }

    func testWatcherStartFailureDoesNotClaimPathsAndCanRetry() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("popskill-watch-start-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        var starts = 0
        let watcher = StoreWatcher(latency: 0.01, startStream: { _ in
            starts += 1
            return false
        }) {}
        defer { watcher.stop() }

        watcher.sync(paths: [dir.path])
        XCTAssertEqual(watcher.watchedPaths, [], "启动失败时不能伪装成已监听")

        watcher.sync(paths: [dir.path])
        XCTAssertEqual(starts, 2, "同一路径下一次 sync 必须继续重试")
        XCTAssertEqual(watcher.watchedPaths, [])
    }
}
