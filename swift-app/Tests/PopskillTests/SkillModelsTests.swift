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
    func sourceURLIgnoresUnsupportedReadmeSchemes() {
        let skill = CatalogSkill(
            key: "maojiebc/majia-skills/demo",
            name: "Demo",
            description: "Demo skill",
            directory: "demo",
            readmeUrl: "javascript:alert(1)",
            installed: false,
            repoOwner: "maojiebc",
            repoName: "majia-skills",
            repoBranch: nil
        )

        #expect(skill.sourceURL?.absoluteString == "https://github.com/maojiebc/majia-skills")
    }

    @Test
    func sourceURLRejectsEmptyRepositoryParts() {
        let skill = CatalogSkill(
            key: "demo",
            name: "Demo",
            description: "Demo skill",
            directory: "demo",
            readmeUrl: nil,
            installed: false,
            repoOwner: "",
            repoName: "majia-skills",
            repoBranch: nil
        )

        #expect(skill.sourceURL == nil)
    }

    @Test
    func sourceLabelFallsBackToDirectoryForEmptyRepositoryParts() {
        let skill = CatalogSkill(
            key: "demo",
            name: "Demo",
            description: "Demo skill",
            directory: "demo",
            readmeUrl: nil,
            installed: false,
            repoOwner: "",
            repoName: "majia-skills",
            repoBranch: nil
        )

        #expect(skill.sourceLabel == "demo")
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

    @Test
    func securityScanStatusDecodesBlockedValue() throws {
        let data = """
        {
          "scanner": "ecc-agentshield",
          "status": "blocked",
          "summary": "High severity finding",
          "exitCode": 1,
          "stdout": "",
          "stderr": "",
          "scannedAt": 1778603190
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let result = try decoder.decode(SecurityScanResult.self, from: data)

        #expect(result.status == .blocked)
        #expect(result.exitCode == 1)
    }

    @Test
    func securityScanRecordDecodesPersistedPayload() throws {
        let data = """
        {
          "skillId": "owner/repo:demo",
          "skillDirectory": "/Users/demo/.cc-switch/skills/demo",
          "result": {
            "scanner": "ecc-agentshield",
            "status": "verified",
            "summary": "AgentShield completed without reported findings",
            "exitCode": 0,
            "stdout": "",
            "stderr": "",
            "scannedAt": 1778603190
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let record = try decoder.decode(SecurityScanRecord.self, from: data)

        #expect(record.skillId == "owner/repo:demo")
        #expect(record.result.status == .verified)
    }

    @Test
    func webDAVStatusDecodesUnconfiguredPayload() throws {
        let data = """
        {
          "configured": false
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(WebDAVStatus.self, from: data)

        #expect(result.configured == false)
        #expect(result.enabled == nil)
    }

    @Test
    func webDAVRemoteInfoDecodesSnapshotPayload() throws {
        let data = """
        {
          "deviceName": "Mac Studio",
          "createdAt": 1778603190,
          "snapshotId": "snapshot-123",
          "version": 1,
          "protocolVersion": 1,
          "dbCompatVersion": 3,
          "compatible": true,
          "artifacts": ["database", "skills"],
          "layout": "profile",
          "remotePath": "cc-switch-sync/default"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let info = try decoder.decode(WebDAVRemoteInfo.self, from: data)

        #expect(info.snapshotId == "snapshot-123")
        #expect(info.compatible == true)
        #expect(info.artifacts == ["database", "skills"])
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
