import Foundation

// One lightweight result for the most recent batch, not a second inventory or task engine.
enum MaintenanceObject: String, Codable, Sendable { case source, cli }
enum OperationPhase: String, Codable, Sendable {
    case queued, running, succeeded, failed, unverified, skipped
    var isActive: Bool { self == .queued || self == .running }
}
struct OperationItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let kind: MaintenanceObject
    var phase: OperationPhase = .queued
    var detail: String?
    var finishedAt: Date?
}
struct OperationReport: Codable, Equatable, Sendable {
    var items: [OperationItem] = []
    var startedAt: Date?
    var isActive: Bool { items.contains { $0.phase.isActive } }
    var completedCount: Int { items.filter { !$0.phase.isActive }.count }
    var runningName: String? { items.first { $0.phase == .running }?.name }
    var queuedCount: Int { items.filter { $0.phase == .queued }.count }

    mutating func enqueue(id: String, name: String, kind: MaintenanceObject) {
        if !isActive { items = []; startedAt = Date() }
        guard !items.contains(where: { $0.id == id }) else { return }
        items.append(OperationItem(id: id, name: name, kind: kind))
    }
    mutating func setPhase(_ id: String, _ phase: OperationPhase, detail: String? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].phase = phase
        items[i].detail = detail
        items[i].finishedAt = phase.isActive ? nil : Date()
    }
    mutating func recoverInterrupted() {
        for i in items.indices where items[i].phase.isActive {
            items[i].phase = .unverified
            items[i].detail = nil
        }
    }
    func failedIDs(kind: MaintenanceObject) -> Set<String> {
        Set(items.filter { $0.kind == kind && $0.phase == .failed }.map(\.id))
    }
}

// A successful command is not proof that the expected installed version is present.
func verifiedUpgradePhase(observed: String?, target: String) -> OperationPhase {
    guard let observed, !observed.isEmpty, observed == target else { return .unverified }
    return .succeeded
}
