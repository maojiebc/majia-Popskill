@testable import Popskill
import Foundation
import Testing

struct AssetDomainModelsTests {
    @Test
    func assetDomainSchemaDecodesSidecarPayload() throws {
        let data = """
        {
          "schemaVersion": 1,
          "modelName": "popskill.asset-control-plane",
          "sourceKinds": ["local", "git", "zip", "registry", "mcp"],
          "versionModes": ["pinned", "floating"],
          "packageTypes": ["standalone", "composite"],
          "componentKinds": ["skill", "cli", "mcpServer", "agent", "rule", "prompt", "config"],
          "deploymentStrategies": ["copy", "symlink", "wrapper", "configPatch"],
          "runtimeTransports": ["stdio", "streamableHttp", "none"],
          "mutationPhases": ["plan", "snapshot", "apply", "verify", "commit", "rollback"],
          "defaultStrategyOrder": ["copy", "configPatch", "wrapper", "symlink"],
          "errorCodes": [
            {
              "code": "E_CONFIG_MERGE_CONFLICT",
              "retryable": false,
              "rollbackRelevant": true,
              "description": "A third-party config file could not be merged without risking user data."
            },
            {
              "code": "E_SECRET_UNAVAILABLE",
              "retryable": true,
              "rollbackRelevant": false,
              "description": "A required secret reference could not be resolved."
            }
          ],
          "invariants": [
            "SSOT lives in Popskill-controlled state; target folders are projections.",
            "Symlink is a target-specific deployment strategy, never the only source of truth."
          ]
        }
        """.data(using: .utf8)!

        let schema = try JSONDecoder().decode(AssetDomainSchema.self, from: data)

        #expect(schema.schemaVersion == 1)
        #expect(schema.modelName == "popskill.asset-control-plane")
        #expect(schema.componentKinds.contains("mcpServer"))
        #expect(schema.deploymentStrategySummary.contains("configPatch"))
        #expect(schema.mutationPhaseSummary == "plan -> snapshot -> apply -> verify -> commit -> rollback")
        #expect(schema.rollbackErrorCodes == ["E_CONFIG_MERGE_CONFLICT"])
    }
}
