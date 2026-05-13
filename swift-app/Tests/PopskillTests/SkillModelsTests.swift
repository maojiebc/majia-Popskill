@testable import Popskill
import Foundation
import Testing

struct SkillModelsTests {
    @Test
    func catalogSourceLabelOmitsMainBranch() {
        let skill = catalogSkill(repoBranch: "main")

        #expect(skill.sourceLabel == "maojiebc/majia-skills")
    }

    @Test
    func catalogSourceLabelIncludesNonMainBranch() {
        let skill = catalogSkill(repoBranch: "dev")

        #expect(skill.sourceLabel == "maojiebc/majia-skills@dev")
    }

    @Test
    func sourceURLFallsBackToGitHubRepository() {
        let skill = catalogSkill(repoBranch: nil)

        #expect(skill.sourceURL?.absoluteString == "https://github.com/maojiebc/majia-skills")
    }

    @Test
    func sourceURLPrefersReadmeURL() {
        let skill = CatalogSkill(
            key: "maojiebc/majia-skills/demo",
            name: "Demo",
            description: "Demo skill",
            directory: "demo",
            readmeUrl: "https://example.com/readme",
            installed: false,
            repoOwner: "maojiebc",
            repoName: "majia-skills",
            repoBranch: nil
        )

        #expect(skill.sourceURL?.absoluteString == "https://example.com/readme")
    }

    @Test
    func sourceURLIgnoresRelativeReadmeURL() {
        let skill = CatalogSkill(
            key: "maojiebc/majia-skills/demo",
            name: "Demo",
            description: "Demo skill",
            directory: "demo",
            readmeUrl: "README.md",
            installed: false,
            repoOwner: "maojiebc",
            repoName: "majia-skills",
            repoBranch: nil
        )

        #expect(skill.sourceURL?.absoluteString == "https://github.com/maojiebc/majia-skills")
    }

    @Test
    func installedSkillLocalStoreURLUsesCCSwitchStore() {
        let skill = installedSkill(directory: "demo-skill")

        #expect(skill.localStoreURL.path.hasSuffix("/.cc-switch/skills/demo-skill"))
    }

    @Test
    func enabledAppCountCountsAllTargetApps() {
        var skill = installedSkill(directory: "demo-skill")

        skill.apps.codex = true
        skill.apps.hermes = true

        #expect(skill.enabledAppCount == 3)
    }

    private func catalogSkill(repoBranch: String?) -> CatalogSkill {
        CatalogSkill(
            key: "maojiebc/majia-skills/demo",
            name: "Demo",
            description: "Demo skill",
            directory: "demo",
            readmeUrl: nil,
            installed: false,
            repoOwner: "maojiebc",
            repoName: "majia-skills",
            repoBranch: repoBranch
        )
    }

    private func installedSkill(directory: String) -> Skill {
        Skill(
            id: directory,
            name: "Demo",
            description: "Demo skill",
            directory: directory,
            repoOwner: nil,
            repoName: nil,
            readmeUrl: nil,
            apps: SkillApps(
                claude: true,
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
