import Combine
import XCTest
@testable import Popskill

final class MaintenanceObservationTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "popskill-maintenance-observation-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

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
}
