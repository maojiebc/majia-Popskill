@testable import Popskill
import Testing

struct LibraryFilterTests {
    @Test
    func allFilterIncludesEverySkill() {
        #expect(LibraryFilter.all.includes(skill(enabledInClaude: true)))
        #expect(LibraryFilter.all.includes(skill(enabledInClaude: false)))
    }

    @Test
    func activeFilterIncludesEnabledSkillsOnly() {
        #expect(LibraryFilter.active.includes(skill(enabledInClaude: true)))
        #expect(!LibraryFilter.active.includes(skill(enabledInClaude: false)))
    }

    @Test
    func inactiveFilterIncludesDisabledSkillsOnly() {
        #expect(!LibraryFilter.inactive.includes(skill(enabledInClaude: true)))
        #expect(LibraryFilter.inactive.includes(skill(enabledInClaude: false)))
    }

    private func skill(enabledInClaude: Bool) -> Skill {
        Skill(
            id: enabledInClaude ? "active" : "inactive",
            name: "Demo",
            description: "Demo skill",
            directory: "demo",
            repoOwner: nil,
            repoName: nil,
            readmeUrl: nil,
            apps: SkillApps(
                claude: enabledInClaude,
                codex: false,
                gemini: false,
                opencode: false,
                hermes: false
            ),
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil
        )
    }
}
