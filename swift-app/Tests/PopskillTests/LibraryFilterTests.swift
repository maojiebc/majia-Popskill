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

    @Test
    func librarySortOptionsUseExpectedOrdering() {
        let alpha = skill(id: "alpha", name: "Alpha", installedAt: 10, updatedAt: 20, lastUsedAt: 30, sizeBytes: 40)
        let beta = skill(id: "beta", name: "Beta", installedAt: 30, updatedAt: 10, lastUsedAt: 20, sizeBytes: 80)

        #expect(LibrarySortOption.name.areInIncreasingOrder(alpha, beta))
        #expect(LibrarySortOption.installedAt.areInIncreasingOrder(beta, alpha))
        #expect(LibrarySortOption.lastUsedAt.areInIncreasingOrder(alpha, beta))
        #expect(LibrarySortOption.size.areInIncreasingOrder(beta, alpha))
        #expect(LibrarySortOption.lastUpdatedAt.areInIncreasingOrder(alpha, beta))
    }

    private func skill(
        id: String? = nil,
        name: String = "Demo",
        enabledInClaude: Bool = true,
        installedAt: Int? = nil,
        updatedAt: Int? = nil,
        lastUsedAt: Int? = nil,
        sizeBytes: UInt64? = nil
    ) -> Skill {
        Skill(
            id: id ?? (enabledInClaude ? "active" : "inactive"),
            name: name,
            description: "Demo skill",
            directory: id ?? "demo",
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
            installedAt: installedAt,
            updatedAt: updatedAt,
            contentHash: nil,
            lastUsedAt: lastUsedAt,
            sizeBytes: sizeBytes
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
