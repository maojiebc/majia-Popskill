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

    @Test
    func stubFilterDoesNotIncludeInstalledSkills() {
        #expect(!LibraryFilter.stub.includes(skill(enabledInClaude: true)))
        #expect(!LibraryFilter.stub.includes(skill(enabledInClaude: false)))
    }

    @Test
    func packageFiltersSeparateCompositeAndStandalone() {
        let composite = package(type: .composite)
        let standalone = package(type: .standalone)

        #expect(PackageFilter.all.includes(composite))
        #expect(PackageFilter.all.includes(standalone))
        #expect(PackageFilter.composite.includes(composite))
        #expect(!PackageFilter.composite.includes(standalone))
        #expect(!PackageFilter.standalone.includes(composite))
        #expect(PackageFilter.standalone.includes(standalone))
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

    private func package(type: CapabilityPackageType) -> CapabilityPackage {
        CapabilityPackage(
            id: "pkg:\(type.rawValue)",
            type: type,
            name: type.title,
            vendor: nil,
            summary: "Demo package",
            source: PackageSource(kind: "builtin", location: "popskill/demo", updateStrategy: "manual"),
            components: PackageComponents(cli: [], skills: [], mcp: [], agents: []),
            configSchema: [],
            installed: false
        )
    }
}
