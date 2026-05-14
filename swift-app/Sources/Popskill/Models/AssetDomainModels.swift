import Foundation

struct AssetDomainSchema: Codable, Equatable {
    let schemaVersion: Int
    let modelName: String
    let sourceKinds: [String]
    let versionModes: [String]
    let packageTypes: [String]
    let componentKinds: [String]
    let deploymentStrategies: [String]
    let runtimeTransports: [String]
    let mutationPhases: [String]
    let defaultStrategyOrder: [String]
    let errorCodes: [AssetErrorCodeDefinition]
    let invariants: [String]

    var componentKindSummary: String {
        summarized(componentKinds)
    }

    var deploymentStrategySummary: String {
        summarized(deploymentStrategies)
    }

    var runtimeTransportSummary: String {
        summarized(runtimeTransports)
    }

    var mutationPhaseSummary: String {
        mutationPhases.joined(separator: " -> ")
    }

    var rollbackErrorCodes: [String] {
        errorCodes
            .filter(\.rollbackRelevant)
            .map(\.code)
    }

    private func summarized(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }
}

struct AssetErrorCodeDefinition: Codable, Equatable, Identifiable {
    var id: String { code }

    let code: String
    let retryable: Bool
    let rollbackRelevant: Bool
    let description: String
}
