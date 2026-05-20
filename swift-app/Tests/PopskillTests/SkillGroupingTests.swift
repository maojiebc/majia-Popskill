@testable import Popskill
import Foundation
import Testing

/// Pure-logic tests for the matrix grouping helper. The matrix UI surface is
/// painted in MatrixView / MatrixGroupHeader; this file just locks the bucket
/// invariants so a regression doesn't quietly reorder the page on the user.
struct SkillGroupingTests {
    @Test
    func emptyInputProducesEmptyGroups() {
        #expect(SkillGrouping.group([]).isEmpty)
    }

    @Test
    func singleSkillWithRepoProducesOneGroup() {
        let cap = capability(name: "doc-writer", owner: "anthropics", name2: "skills")
        let groups = SkillGrouping.group([cap])

        #expect(groups.count == 1)
        #expect(groups.first?.id == "anthropics/skills")
        #expect(groups.first?.label == "anthropics/skills")
        #expect(groups.first?.isUngrouped == false)
        #expect(groups.first?.capabilities.count == 1)
    }

    @Test
    func skillsWithoutRepoFallIntoUngroupedBucket() {
        let withRepo = capability(name: "alpha", owner: "anthropics", name2: "skills")
        let standalone = capability(name: "beta", owner: nil, name2: nil)

        let groups = SkillGrouping.group([standalone, withRepo])

        #expect(groups.count == 2)
        #expect(groups.last?.id == SkillGrouping.ungroupedID)
        #expect(groups.last?.isUngrouped == true)
        #expect(groups.last?.capabilities.first?.name == "beta")
    }

    @Test
    func bucketSortIsAlphabeticAndStable() {
        let a = capability(name: "alpha", owner: "zzz", name2: "lib")
        let b = capability(name: "beta", owner: "aaa", name2: "lib")
        let c = capability(name: "gamma", owner: "mmm", name2: "lib")

        let groups = SkillGrouping.group([a, b, c])

        #expect(groups.map(\.id) == ["aaa/lib", "mmm/lib", "zzz/lib"])
    }

    @Test
    func skillsInsideBucketSortByNameCaseInsensitive() {
        let alpha = capability(name: "Alpha", owner: "anthropics", name2: "skills")
        let beta = capability(name: "beta", owner: "anthropics", name2: "skills")
        let charlie = capability(name: "Charlie", owner: "anthropics", name2: "skills")

        let group = SkillGrouping.group([charlie, beta, alpha]).first

        #expect(group?.capabilities.map(\.name) == ["Alpha", "beta", "Charlie"])
    }

    @Test
    func ungroupedAlwaysLastEvenWithManyRepoGroups() {
        let none = capability(name: "loose", owner: nil, name2: nil)
        let z = capability(name: "z", owner: "z-org", name2: "lib")
        let a = capability(name: "a", owner: "a-org", name2: "lib")

        let groups = SkillGrouping.group([none, z, a])
        #expect(groups.map(\.id) == ["a-org/lib", "z-org/lib", SkillGrouping.ungroupedID])
    }

    // MARK: kind-section tests (v0.4 matrix extension)

    @Test
    func sectionsBucketByKindAndSkipEmptyKinds() {
        let skillCap = capability(name: "alpha", kind: .skill, owner: "a", name2: "lib")
        let agentCap = capability(name: "agent-one", kind: .agent, owner: nil, name2: nil)

        let sections = SkillGrouping.sections([skillCap, agentCap])

        #expect(sections.count == 2)
        #expect(sections.map(\.kind) == [.skill, .agent])
        #expect(sections.first?.totalCount == 1)
    }

    @Test
    func sectionsRespectCanonicalKindOrder() {
        // CapabilityKind.allCases is the canonical order — even with inputs
        // interleaved, sections come out in bundle/skill/agent/cli/mcp/config order.
        let bundleCap = capability(name: "package", kind: .bundle, owner: "pkg", name2: "source")
        let agentCap = capability(name: "z", kind: .agent, owner: nil, name2: nil)
        let skillCap = capability(name: "y", kind: .skill, owner: "a", name2: "lib")

        let sections = SkillGrouping.sections([agentCap, skillCap, bundleCap])

        #expect(sections.map(\.kind) == [.bundle, .skill, .agent])
    }

    @Test
    func sectionsCanReverseKindOrderForTypeAscendingSort() {
        let bundleCap = capability(name: "package", kind: .bundle, owner: "pkg", name2: "source")
        let agentCap = capability(name: "z", kind: .agent, owner: nil, name2: nil)
        let skillCap = capability(name: "y", kind: .skill, owner: "a", name2: "lib")

        let sections = SkillGrouping.sections(
            [agentCap, skillCap, bundleCap],
            sort: .typeAscending
        )

        #expect(sections.map(\.kind) == [.agent, .skill, .bundle])
    }

    @Test
    func groupSortsCapabilitiesByNameDescending() {
        let alpha = capability(name: "Alpha", owner: "anthropics", name2: "skills")
        let beta = capability(name: "beta", owner: "anthropics", name2: "skills")
        let charlie = capability(name: "Charlie", owner: "anthropics", name2: "skills")

        let group = SkillGrouping.group([alpha, charlie, beta], sort: .nameDescending).first

        #expect(group?.capabilities.map(\.name) == ["Charlie", "beta", "Alpha"])
    }

    @Test
    func groupSortsCapabilitiesByCallsDescending() {
        let alpha = capability(name: "Alpha", owner: "anthropics", name2: "skills")
        let beta = capability(name: "beta", owner: "anthropics", name2: "skills")
        let usageIndex = MatrixUsageIndex(
            summary: UsageSummary(
                skillStats: [
                    SkillUsageStat(
                        skillID: "Alpha",
                        sourcePlugin: nil,
                        usageEvents: 2,
                        inputTokens: 10,
                        outputTokens: 0,
                        cacheCreationTokens: 0,
                        cacheReadTokens: 0,
                        lastUsedAt: nil
                    ),
                    SkillUsageStat(
                        skillID: "beta",
                        sourcePlugin: nil,
                        usageEvents: 8,
                        inputTokens: 3,
                        outputTokens: 0,
                        cacheCreationTokens: 0,
                        cacheReadTokens: 0,
                        lastUsedAt: nil
                    )
                ]
            ),
            skills: [skill(id: "Alpha"), skill(id: "beta")],
            packages: []
        )

        let group = SkillGrouping.group([alpha, beta], sort: .callsDescending, usageIndex: usageIndex).first

        #expect(group?.capabilities.map(\.name) == ["beta", "Alpha"])
    }

    @Test
    func sectionsAreEmptyForEmptyInput() {
        #expect(SkillGrouping.sections([]).isEmpty)
    }

    // MARK: helpers

    private func capability(
        name: String,
        kind: CapabilityKind = .skill,
        owner: String?,
        name2: String?
    ) -> MatrixCapability {
        MatrixCapability(
            id: "test:\(name)",
            kind: kind,
            name: name,
            summary: nil,
            sourceLabel: owner.flatMap { o in name2.map { n in "\(o)/\(n)" } } ?? name,
            sourceType: nil,
            repoOwner: owner,
            repoName: name2,
            apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false),
            deployment: nil,
            directory: name,
            installedAt: nil,
            updatedAt: nil,
            sizeBytes: nil,
            triggerScenarios: nil,
            underlyingSkillID: kind == .skill ? name : nil,
            underlyingAgentID: kind == .agent ? name : nil
        )
    }

    private func skill(id: String) -> Skill {
        Skill(
            id: id,
            name: id,
            description: "Test skill",
            directory: id,
            repoOwner: nil,
            repoName: nil,
            readmeUrl: nil,
            apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false),
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil
        )
    }
}
