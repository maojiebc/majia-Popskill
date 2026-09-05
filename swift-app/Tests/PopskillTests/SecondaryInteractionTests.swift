import XCTest
@testable import Popskill

private final class InspectionSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(Bool, Bool)] = []
    func append(full: Bool, versions: Bool) { lock.lock(); defer { lock.unlock() }; values.append((full, versions)) }
    var calls: [(Bool, Bool)] { lock.lock(); defer { lock.unlock() }; return values }
}

@MainActor
final class SecondaryInteractionTests: XCTestCase {
    var root: URL!
    var defaults: UserDefaults!
    var suite: String!
    var model: AppModel!
    override func setUp() {
        super.setUp()
        setenv("POPSKILL_NO_AUTOCHECK", "1", 1)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("popskill-ui-\(UUID())")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "popskill-ui-tests-\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        model = AppModel(env: StoreEnv(storeRoot: root, toolRoots: ["claude": root.appendingPathComponent("claude")]), defaults: defaults)
        model.fake = true
    }
    override func tearDown() {
        model.stopMaintenanceAutomation()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }
    private func source(_ id: String, remote: Bool = true, enabled: Bool = false) -> Entry {
        let cap = Capability(id: id, name: id, type: .skill, desc: "", version: "1", author: nil,
                             tokens: 0, dirURL: root.appendingPathComponent(id))
        return Entry(id: id, cap: cap, children: nil,
                     sourceUrl: remote ? "github.com/example/\(id)" : root.appendingPathComponent(id).path,
                     autoUpdate: enabled)
    }
    private func cli(_ name: String, conflict: Bool = false) -> GlobalCli {
        GlobalCli(name: name, installed: "1.0.0", latest: "2.0.0", prefix: "/test",
                  pathMatchesPrefix: !conflict, allowlisted: true)
    }
    func testFutureDefaultDoesNotTouchCurrentOptOutEvenAfterReconcile() {
        model.entries = [source("one"), source("two", enabled: true)]
        model.setFutureSourceAutoUpdate(true)
        XCTAssertEqual(model.reconcileRemoteSourceDefaults(), 0)
        XCTAssertEqual(model.entries.map(\.autoUpdate), [false, true])
        XCTAssertTrue(model.maintenancePolicy.inheritRemoteAutoUpdate)
        model.entries.append(source("new"))
        XCTAssertEqual(model.reconcileRemoteSourceDefaults(), 1)
        XCTAssertTrue(model.entries.last!.autoUpdate)
    }
    func testApplyToExistingDoesNotChangeFutureDefaultOrLocalSources() {
        model.entries = [source("one", enabled: true), source("local", remote: false, enabled: true)]
        model.setFutureSourceAutoUpdate(true)
        XCTAssertTrue(model.applyAutoUpdateToExistingSources(false))
        XCTAssertTrue(model.maintenancePolicy.inheritRemoteAutoUpdate)
        XCTAssertFalse(model.entries[0].autoUpdate)
        XCTAssertTrue(model.entries[1].autoUpdate)
        XCTAssertEqual(model.reconcileRemoteSourceDefaults(), 0)
    }
    func testMaintenanceTargetsAreExactlyVisibleAndEligible() {
        model.globalClis = [cli("@openai/codex"), cli("@anthropic-ai/claude-code", conflict: true), cli("unknown-agent")]
        model.maintenance.cliScope = .all
        XCTAssertEqual(model.maintenanceCliTargets.map(\.name), ["@openai/codex"])
        model.maintenance.cliQuery = "claude"
        XCTAssertTrue(model.maintenanceCliTargets.isEmpty)
        model.maintenance.cliQuery = "codex"
        XCTAssertEqual(model.maintenanceCliTargets.count, 1)
        model.maintenance.cliChecks[model.globalClis[0].id] = CheckRecord(outcome: .failed)
        XCTAssertTrue(model.maintenanceCliTargets.isEmpty)
    }
    func testNavigationPreservesBothPagesContext() {
        model.query = "matrix search"
        model.maintenance.cliQuery = "codex"
        model.maintenance.cliScrollID = "row-12"
        model.openMaintenance(.clis)
        model.returnToMatrix()
        model.openMaintenance()
        XCTAssertEqual(model.maintenance.tab, .clis)
        XCTAssertEqual(model.maintenance.cliQuery, "codex")
        XCTAssertEqual(model.maintenance.cliScrollID, "row-12")
        XCTAssertEqual(model.query, "matrix search")
    }
    func testInstallationCannotBeDismissedMidWrite() {
        model.sheet = .add
        model.installing = true
        model.dismissShortTask()
        XCTAssertEqual(model.sheet, .add)
        XCTAssertTrue(model.maintenanceMutationBusy)
        model.installing = false
        model.dismissShortTask()
        XCTAssertNil(model.sheet)
    }
    func testToolPreferenceDoesNotCreateToolDirectory() {
        model.fake = false
        let path = root.appendingPathComponent("claude")
        XCTAssertTrue(model.setToolPreference("claude", defaultTarget: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        XCTAssertEqual(model.fs.loadMeta().tools["claude"]?.defaultTarget, true)
    }
    func testFullManualInspectionRequiresSeparateAuthorization() async throws {
        let spy = InspectionSpy()
        model.fake = false
        model.cliInventoryReader = { @Sendable _, full, versions in spy.append(full: full, versions: versions); return [] }
        model.maintenance.cliScope = .all
        XCTAssertFalse(model.checkMaintenanceClis())
        XCTAssertTrue(spy.calls.isEmpty)
        model.maintenance.allCliInspectionAuthorized = true
        XCTAssertTrue(model.checkMaintenanceClis())
        for _ in 0..<100 where model.checkingClis { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertTrue(try XCTUnwrap(spy.calls.first).0)
        XCTAssertFalse(model.autoCliPatrol, "A manual scope must not expand scheduled inspection")
    }
    func testOpeningInventoryDoesNotQueryVersions() async throws {
        let spy = InspectionSpy()
        model.fake = false
        model.cliInventoryReader = { @Sendable _, full, versions in spy.append(full: full, versions: versions); return [] }
        model.openMaintenance(.clis)
        for _ in 0..<100 where model.checkingClis { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertFalse(try XCTUnwrap(spy.calls.first).1)
        model.maintenance.cliQuery = "anything"
        model.maintenance.cliFilter = .issues
        _ = model.filteredMaintenanceClis
        XCTAssertEqual(spy.calls.count, 1, "Search and filtering must not inspect registries")
    }
    func testQueuePreflightRejectsChangedInstallationOrProvenance() {
        let original = cli("@openai/codex")
        XCTAssertTrue(sameCliInstallation(original, as: original))
        var moved = original; moved.prefix = "/another"
        XCTAssertFalse(sameCliInstallation(moved, as: original))
        var changed = original; changed.pathMatchesPrefix = false
        XCTAssertFalse(sameCliInstallation(changed, as: original))
        changed = original; changed.tracksIndex = false
        XCTAssertFalse(sameCliInstallation(changed, as: original))
        changed = original; changed.excluded = true
        XCTAssertFalse(sameCliInstallation(changed, as: original))
    }
    func testRetryOnlySelectsFailuresStillEligible() {
        let failed = cli("@openai/codex")
        let succeeded = cli("@anthropic-ai/claude-code")
        let blocked = cli("unknown-agent")
        model.globalClis = [failed, succeeded, blocked]
        for item in model.globalClis { model.maintenance.report.enqueue(id: item.id, name: item.name, kind: .cli) }
        model.maintenance.report.setPhase(failed.id, .failed)
        model.maintenance.report.setPhase(succeeded.id, .succeeded)
        model.maintenance.report.setPhase(blocked.id, .failed)
        XCTAssertEqual(model.retryableMaintenanceCount, 1)
        model.maintenance.cliChecks[failed.id] = CheckRecord(outcome: .failed)
        XCTAssertEqual(model.retryableMaintenanceCount, 0)
    }
    func testReportSurvivesClosingAndReloading() {
        model.maintenance.report.enqueue(id: "cli-one", name: "CLI One", kind: .cli)
        model.maintenance.report.setPhase("cli-one", .failed, detail: "network unavailable")
        let restored = MaintenanceState(defaults: defaults)
        XCTAssertEqual(restored.report.items.first?.detail, "network unavailable")
        XCTAssertEqual(restored.report.failedIDs(kind: .cli), ["cli-one"])
    }
}
