import XCTest
@testable import Popskill
final class OperationReportTests: XCTestCase {
    func testQueuedAndRunningAreDistinct() {
        var r = OperationReport()
        r.enqueue(id: "a", name: "A", kind: .cli)
        r.enqueue(id: "b", name: "B", kind: .cli)
        r.setPhase("a", .running)
        XCTAssertEqual(r.items.map(\.phase), [.running, .queued])
        XCTAssertEqual(r.completedCount, 0)
    }
    func testOnlyFailuresAreRetryable() {
        var r = OperationReport()
        for id in ["a", "b", "c"] { r.enqueue(id: id, name: id, kind: .cli) }
        r.setPhase("a", .succeeded)
        r.setPhase("b", .failed, detail: "offline")
        r.setPhase("c", .unverified)
        XCTAssertEqual(r.failedIDs(kind: .cli), ["b"])
        XCTAssertEqual(r.completedCount, 3)
        XCTAssertFalse(r.isActive)
    }
    func testReopeningInterruptedReportNeverClaimsSuccess() {
        var r = OperationReport()
        r.enqueue(id: "a", name: "A", kind: .source)
        r.setPhase("a", .running)
        r.recoverInterrupted()
        XCTAssertEqual(r.items.first?.phase, .unverified)
        XCTAssertFalse(r.isActive)
    }
    func testDuplicateQueueDoesNotEraseRunningState() {
        var r = OperationReport()
        r.enqueue(id: "a", name: "A", kind: .cli)
        r.setPhase("a", .running)
        r.enqueue(id: "a", name: "A", kind: .cli)
        XCTAssertEqual(r.items.count, 1)
        XCTAssertEqual(r.items.first?.phase, .running)
    }
    func testNewBatchReplacesCompletedReport() {
        var r = OperationReport()
        r.enqueue(id: "a", name: "A", kind: .cli)
        r.setPhase("a", .succeeded)
        r.enqueue(id: "b", name: "B", kind: .source)
        XCTAssertEqual(r.items.map(\.id), ["b"])
    }
    func testCurrentVersionRequiresARealObservation() {
        XCTAssertEqual(verifiedUpgradePhase(observed: nil, target: "2.0.0"), .unverified)
        XCTAssertEqual(verifiedUpgradePhase(observed: "1.0.0", target: "2.0.0"), .unverified)
        XCTAssertEqual(verifiedUpgradePhase(observed: "2.0.0", target: "2.0.0"), .succeeded)
    }
    func testUnifiedBatchKeepsCompletedSourcesWhenCliPhaseBegins() throws {
        // A decoded batch models the persisted boundary while source work is done.
        let json = #"{"items":[],"batchOpen":true}"#.data(using: .utf8)!
        var r = try JSONDecoder().decode(OperationReport.self, from: json)
        r.enqueue(id: "source-ok", name: "Source OK", kind: .source)
        r.enqueue(id: "source-failed", name: "Source Failed", kind: .source)
        r.setPhase("source-ok", .succeeded)
        r.setPhase("source-failed", .failed, detail: "network unavailable")
        r.enqueue(id: "agent", name: "Agent", kind: .cli)
        XCTAssertEqual(r.items.map(\.id), ["source-ok", "source-failed", "agent"])
        XCTAssertEqual(r.failedIDs(kind: .source), ["source-failed"])
        XCTAssertEqual(r.completedCount, 2)
    }
    func testExplicitBatchEndAllowsNextIndependentOperationToReplaceReport() {
        var r = OperationReport()
        r.beginBatch()
        r.enqueue(id: "source", name: "Source", kind: .source)
        r.setPhase("source", .succeeded)
        r.enqueue(id: "cli", name: "CLI", kind: .cli)
        XCTAssertEqual(r.items.count, 2)
        r.setPhase("cli", .failed)
        r.endBatch()
        r.enqueue(id: "next", name: "Next", kind: .source)
        XCTAssertEqual(r.items.map(\.id), ["next"])
    }
    func testInterruptedBatchClosesBoundaryAndOldReceiptsStillDecode() throws {
        var r = OperationReport()
        r.beginBatch()
        r.enqueue(id: "source", name: "Source", kind: .source)
        r.recoverInterrupted()
        XCTAssertEqual(r.items.first?.phase, .unverified)
        r.enqueue(id: "next", name: "Next", kind: .cli)
        XCTAssertEqual(r.items.map(\.id), ["next"])
        let legacy = try JSONDecoder().decode(OperationReport.self,
            from: Data(#"{"items":[]}"#.utf8))
        XCTAssertNil(legacy.batchOpen)
    }
}
