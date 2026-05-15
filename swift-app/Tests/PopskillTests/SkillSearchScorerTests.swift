@testable import Popskill
import Foundation
import Testing

struct SkillSearchScorerTests {
    @Test
    func emptyQueryReturnsNil() {
        let hit = SkillSearchScorer.score(skill: skill(name: "baoyu-diagram"), query: "")
        #expect(hit == nil)
    }

    @Test
    func nameExactMatchScoresHighest() {
        let hit = SkillSearchScorer.score(
            skill: skill(name: "diagram", description: "Draw flowcharts"),
            query: "diagram"
        )
        // name == query (1000) plus source/directory contains (10 + 5) = 1015.
        // We only assert the ≥ 1000 floor so the test stays stable when search-
        // field weights are tuned later.
        #expect((hit?.score ?? 0) >= 1000)
        #expect(hit?.matchedOnName == true)
    }

    @Test
    func namePrefixOutranksContains() {
        let prefix = SkillSearchScorer.score(skill: skill(name: "diagram-tool"), query: "diagram")
        let contains = SkillSearchScorer.score(skill: skill(name: "draw-diagram"), query: "diagram")
        #expect(prefix != nil && contains != nil)
        #expect((prefix?.score ?? 0) > (contains?.score ?? 0))
    }

    @Test
    func triggerMatchesAddOneHundredEach() {
        let hit = SkillSearchScorer.score(
            skill: skill(
                name: "diagram",
                triggerScenarios: ["画个图", "draw a diagram"]
            ),
            query: "diagram"
        )
        #expect(hit?.matchedTriggers == ["draw a diagram"])
        // name == query (1000) + 1 matching trigger (100) + description contains is 0 here
        #expect((hit?.score ?? 0) >= 1100)
    }

    @Test
    func duplicateTriggersCountOnce() {
        let hit = SkillSearchScorer.score(
            skill: skill(
                name: "diagram",
                triggerScenarios: ["draw", "DRAW", "Draw"]
            ),
            query: "draw"
        )
        #expect(hit?.matchedTriggers.count == 1)
    }

    @Test
    func summaryMatchScoresWithoutNameHit() {
        let hit = SkillSearchScorer.score(
            skill: skill(
                name: "lark-doc",
                description: "Manage Lark documents end-to-end",
                capabilitySummary: "Manage Lark documents end-to-end"
            ),
            query: "document"
        )
        #expect(hit?.matchedOnName == false)
        // summary contains (50) + description contains (20) = 70
        #expect(hit?.score == 70)
    }

    @Test
    func zeroMatchReturnsNil() {
        let hit = SkillSearchScorer.score(
            skill: skill(name: "baoyu-diagram", description: "Draw diagrams"),
            query: "unrelated-token-xyz"
        )
        #expect(hit == nil)
    }

    @Test
    func chineseQueryMatchesChineseTrigger() {
        let hit = SkillSearchScorer.score(
            skill: skill(
                name: "baoyu-diagram",
                triggerScenarios: ["画个图", "画图", "做图"]
            ),
            query: "画图"
        )
        #expect((hit?.matchedTriggers ?? []).contains("画图"))
        #expect((hit?.matchedTriggers ?? []).contains("画个图"))
    }

    @Test
    func agentScoringUsesCategoryAndFileNameAsAuxiliaryFields() {
        // Auxiliary-only match: query lives in category, name has no match.
        let hit = SkillSearchScorer.score(
            agent: localAgent(
                name: "doc-writer",
                description: "Drafts Lark documents",
                category: "office"
            ),
            query: "office"
        )
        // category contains (10) + fileName "doc-writer.md" no contains (0) = 10
        #expect(hit?.score == 10)
        #expect(hit?.matchedOnName == false)
    }

    @Test
    func agentScoringCombinesNameTriggerAndSummary() {
        let hit = SkillSearchScorer.score(
            agent: localAgent(
                name: "diagram-agent",
                description: "Drafts architecture diagrams",
                capabilitySummary: "Drafts architecture diagrams",
                triggerScenarios: ["draw a diagram", "render flowchart"]
            ),
            query: "diagram"
        )
        // name hasPrefix (500) + 1 trigger match (100) + summary contains (50) +
        // description contains (20) + fileName "" no hit (0) = 670
        #expect((hit?.score ?? 0) >= 670)
        #expect(hit?.matchedTriggers == ["draw a diagram"])
    }

    @Test
    func agentZeroMatchReturnsNil() {
        let hit = SkillSearchScorer.score(
            agent: localAgent(name: "lark-office-assistant", description: "Drafts Lark documents"),
            query: "unrelated-xyz"
        )
        #expect(hit == nil)
    }

    private func skill(
        name: String,
        description: String = "",
        capabilitySummary: String? = nil,
        triggerScenarios: [String]? = nil
    ) -> Skill {
        Skill(
            id: "test/\(name)",
            name: name,
            description: description,
            directory: name,
            repoOwner: nil,
            repoName: nil,
            readmeUrl: nil,
            apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false),
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil,
            capabilitySummary: capabilitySummary,
            triggerScenarios: triggerScenarios
        )
    }

    private func localAgent(
        name: String,
        description: String = "",
        category: String = "local",
        capabilitySummary: String? = nil,
        triggerScenarios: [String]? = nil
    ) -> LocalAgent {
        LocalAgent(
            id: "test/\(name)",
            name: name,
            description: description,
            fileName: "\(name).md",
            path: "/tmp/\(name).md",
            category: category,
            tools: [],
            model: nil,
            lastModifiedAt: nil,
            sizeBytes: 0,
            capabilitySummary: capabilitySummary,
            triggerScenarios: triggerScenarios
        )
    }
}
