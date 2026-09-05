import XCTest
#if canImport(Combine)
import Combine
#endif
@testable import Popskill

final class MaintenanceHistoryTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "popskill-maintenance-history-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    func testTemporarilyMissingSourceIsNotNewWhenItReturns() throws {
        try withDefaults { defaults in
            MaintenancePolicyStore.saveKnownSourceIDs(["skill:a", "skill:b"], defaults: defaults)
            // A partial scan must not erase knowledge of a previously configured source.
            MaintenancePolicyStore.saveKnownSourceIDs(["skill:b"], defaults: defaults)
            let inherited = remoteSourceIDsToInherit(
                current: ["skill:a", "skill:b", "skill:new"],
                known: MaintenancePolicyStore.loadKnownSourceIDs(defaults: defaults),
                inherit: true
            )
            XCTAssertEqual(inherited, ["skill:new"],
                           "A returning source must not have its explicit opt-out overwritten")
        }
    }

    func testEmptyScanDoesNotResetSourceHistory() throws {
        try withDefaults { defaults in
            MaintenancePolicyStore.saveKnownSourceIDs(["src:github.com/x/y"], defaults: defaults)
            MaintenancePolicyStore.saveKnownSourceIDs([], defaults: defaults)
            XCTAssertEqual(MaintenancePolicyStore.loadKnownSourceIDs(defaults: defaults),
                           ["src:github.com/x/y"])
        }
    }

    func testRepeatedScansAccumulateOnlyUniqueSourceIDs() throws {
        try withDefaults { defaults in
            MaintenancePolicyStore.saveKnownSourceIDs(["a", "b"], defaults: defaults)
            MaintenancePolicyStore.saveKnownSourceIDs(["b", "c"], defaults: defaults)
            MaintenancePolicyStore.saveKnownSourceIDs(["c"], defaults: defaults)
            XCTAssertEqual(MaintenancePolicyStore.loadKnownSourceIDs(defaults: defaults), ["a", "b", "c"])
            XCTAssertTrue(remoteSourceIDsToInherit(
                current: ["a", "b", "c", "new"],
                known: MaintenancePolicyStore.loadKnownSourceIDs(defaults: defaults),
                inherit: false
            ).isEmpty)
        }
    }
    #if canImport(Combine)
    func testSavedPolicyAndStatusReachMainRunLoopObservers() throws {
        try withDefaults { defaults in
            let refreshed = expectation(description: "Saved maintenance state reaches the UI notification path")
            let policy = MaintenancePolicy(inheritRemoteAutoUpdate: true)
            let status = MaintenanceRunStatus(outcome: .success)
            // Exercise real UserDefaults notifications, not a manually posted event.
            let subscription = NotificationCenter.default.publisher(
                for: UserDefaults.didChangeNotification, object: defaults
            )
            .receive(on: RunLoop.main)
            .filter { _ in
                MaintenancePolicyStore.loadPolicy(defaults: defaults) == policy
                    && MaintenancePolicyStore.loadStatus(defaults: defaults) == status
            }
            .prefix(1)
            .sink { _ in
                XCTAssertTrue(Thread.isMainThread)
                refreshed.fulfill()
            }
            defer { subscription.cancel() }

            MaintenancePolicyStore.savePolicy(policy, defaults: defaults)
            MaintenancePolicyStore.saveStatus(status, defaults: defaults)
            wait(for: [refreshed], timeout: 3)
        }
    }
    #endif
}
