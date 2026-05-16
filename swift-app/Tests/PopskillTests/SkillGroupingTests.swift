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
        let skill = skill(name: "doc-writer", owner: "anthropics", name2: "skills")
        let groups = SkillGrouping.group([skill])

        #expect(groups.count == 1)
        #expect(groups.first?.id == "anthropics/skills")
        #expect(groups.first?.label == "anthropics/skills")
        #expect(groups.first?.isUngrouped == false)
        #expect(groups.first?.skills.count == 1)
    }

    @Test
    func skillsWithoutRepoFallIntoUngroupedBucket() {
        let withRepo = skill(name: "alpha", owner: "anthropics", name2: "skills")
        let standalone = skill(name: "beta", owner: nil, name2: nil)

        let groups = SkillGrouping.group([standalone, withRepo])

        #expect(groups.count == 2)
        // Ungrouped must be last regardless of input order.
        #expect(groups.last?.id == SkillGrouping.ungroupedID)
        #expect(groups.last?.isUngrouped == true)
        #expect(groups.last?.skills.first?.name == "beta")
    }

    @Test
    func bucketSortIsAlphabeticAndStable() {
        let a = skill(name: "alpha", owner: "zzz", name2: "lib")
        let b = skill(name: "beta", owner: "aaa", name2: "lib")
        let c = skill(name: "gamma", owner: "mmm", name2: "lib")

        let groups = SkillGrouping.group([a, b, c])

        #expect(groups.map(\.id) == ["aaa/lib", "mmm/lib", "zzz/lib"])
    }

    @Test
    func skillsInsideBucketSortByNameCaseInsensitive() {
        let alpha = skill(name: "Alpha", owner: "anthropics", name2: "skills")
        let beta = skill(name: "beta", owner: "anthropics", name2: "skills")
        let charlie = skill(name: "Charlie", owner: "anthropics", name2: "skills")

        let group = SkillGrouping.group([charlie, beta, alpha]).first

        #expect(group?.skills.map(\.name) == ["Alpha", "beta", "Charlie"])
    }

    @Test
    func ungroupedAlwaysLastEvenWithManyRepoGroups() {
        let none = skill(name: "loose", owner: nil, name2: nil)
        let z = skill(name: "z", owner: "z-org", name2: "lib")
        let a = skill(name: "a", owner: "a-org", name2: "lib")

        let groups = SkillGrouping.group([none, z, a])
        #expect(groups.map(\.id) == ["a-org/lib", "z-org/lib", SkillGrouping.ungroupedID])
    }

    private func skill(name: String, owner: String?, name2: String?) -> Skill {
        Skill(
            id: "test/\(name)",
            name: name,
            description: "",
            directory: name,
            repoOwner: owner,
            repoName: name2,
            readmeUrl: nil,
            apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false),
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil
        )
    }
}
