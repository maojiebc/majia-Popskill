import XCTest
@testable import Popskill

final class MaintenanceAutomationTests: XCTestCase {
    func testPolicyNormalizationKeepsSafeIntervalsAndDependency() {
        let invalid = MaintenancePolicy(
            inheritRemoteAutoUpdate: true,
            periodicCheckEnabled: false,
            autoUpgradeRecognizedAgents: true,
            intervalHours: 7
        ).normalized
        XCTAssertEqual(invalid.intervalHours, 24)
        XCTAssertFalse(invalid.autoUpgradeRecognizedAgents,
                       "关闭定时检查时不能留下孤立的自动升级开关")

        let valid = MaintenancePolicy(
            inheritRemoteAutoUpdate: false,
            periodicCheckEnabled: true,
            autoUpgradeRecognizedAgents: true,
            intervalHours: 12
        ).normalized
        XCTAssertEqual(valid.intervalHours, 12)
        XCTAssertTrue(valid.autoUpgradeRecognizedAgents)
    }

    func testMaintenanceDueUsesLastFinishedTime() {
        let now = Date(timeIntervalSince1970: 10_000)
        let policy = MaintenancePolicy(
            inheritRemoteAutoUpdate: false,
            periodicCheckEnabled: true,
            autoUpgradeRecognizedAgents: false,
            intervalHours: 6
        )
        XCTAssertTrue(maintenanceRunIsDue(policy: policy, status: MaintenanceRunStatus(), now: now))

        var recent = MaintenanceRunStatus(outcome: .success)
        recent.finishedAt = now.addingTimeInterval(-5 * 3600)
        XCTAssertFalse(maintenanceRunIsDue(policy: policy, status: recent, now: now))

        recent.finishedAt = now.addingTimeInterval(-6 * 3600 - 1)
        XCTAssertTrue(maintenanceRunIsDue(policy: policy, status: recent, now: now))
    }

    func testRemoteSourceInheritanceOnlyTouchesNewIds() {
        let current: Set<String> = ["skill:a", "src:github.com/x/y", "skill:new"]
        let known: Set<String> = ["skill:a", "src:github.com/x/y"]
        XCTAssertEqual(
            remoteSourceIDsToInherit(current: current, known: known, inherit: true),
            ["skill:new"]
        )
        XCTAssertTrue(remoteSourceIDsToInherit(current: current, known: known, inherit: false).isEmpty)
    }

    func testPolicyAndRunStatusRoundTrip() throws {
        let suite = "popskill-maintenance-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let policy = MaintenancePolicy(
            inheritRemoteAutoUpdate: true,
            periodicCheckEnabled: true,
            autoUpgradeRecognizedAgents: true,
            intervalHours: 72
        )
        MaintenancePolicyStore.savePolicy(policy, defaults: defaults)
        XCTAssertEqual(MaintenancePolicyStore.loadPolicy(defaults: defaults), policy)

        let status = MaintenanceRunStatus(
            outcome: .partial,
            startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 200),
            checkedSources: 3,
            sourceUpdatesStarted: 2,
            sourceFailures: 1,
            checkedAgents: 4,
            availableAgentUpdates: 2,
            upgradedAgents: 1,
            unresolvedAgents: 1,
            failedAgentUpgrades: 0,
            error: nil
        )
        MaintenancePolicyStore.saveStatus(status, defaults: defaults)
        XCTAssertEqual(MaintenancePolicyStore.loadStatus(defaults: defaults), status)

        MaintenancePolicyStore.saveKnownSourceIDs(["b", "a"], defaults: defaults)
        XCTAssertEqual(MaintenancePolicyStore.loadKnownSourceIDs(defaults: defaults), ["a", "b"])
    }

    func testBulkAgentUpgradeRejectsPathConflict() {
        var cli = GlobalCli(
            name: "@openai/codex",
            installed: "1.0.0",
            latest: "2.0.0",
            displayName: "@openai/codex",
            channel: .npm,
            prefix: "/opt/homebrew",
            pathHit: "/usr/local/bin/codex",
            pathMatchesPrefix: false,
            excluded: false,
            allowlisted: true
        )
        XCTAssertNotNil(cli.agentDefinition)
        XCTAssertFalse(cli.safeRecognizedAgentUpdate,
                       "PATH 命中另一份时不能进入定时或批量升级")

        cli.pathMatchesPrefix = true
        cli.pathHit = "/opt/homebrew/bin/codex"
        XCTAssertTrue(cli.safeRecognizedAgentUpdate)
    }
}
