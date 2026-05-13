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
    func standalonePackageFilterUsesMatchedSkillActivity() {
        let activeSkill = skill(id: "demo-skill", enabledInClaude: true)
        let inactiveSkill = skill(id: "quiet-skill", enabledInClaude: false)

        #expect(LibraryFilter.active.includes(package(skillID: "demo-skill"), installedSkills: [activeSkill]))
        #expect(!LibraryFilter.inactive.includes(package(skillID: "demo-skill"), installedSkills: [activeSkill]))
        #expect(!LibraryFilter.active.includes(package(skillID: "quiet-skill"), installedSkills: [inactiveSkill]))
        #expect(LibraryFilter.inactive.includes(package(skillID: "quiet-skill"), installedSkills: [inactiveSkill]))
    }

    @Test
    func compositePackageFilterUsesInstalledComponentState() {
        let installedComposite = package(type: .composite, installedComponents: 1)
        let missingComposite = package(type: .composite, installedComponents: 0)

        #expect(LibraryFilter.active.includes(installedComposite, installedSkills: []))
        #expect(!LibraryFilter.inactive.includes(installedComposite, installedSkills: []))
        #expect(!LibraryFilter.active.includes(missingComposite, installedSkills: []))
        #expect(LibraryFilter.inactive.includes(missingComposite, installedSkills: []))
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

    private func package(
        type: CapabilityPackageType = .standalone,
        skillID: String = "demo-skill",
        installedComponents: Int = 0
    ) -> CapabilityPackage {
        let components: [PackageComponent]
        if installedComponents > 0 {
            components = (0..<installedComponents).map { index in
                PackageComponent(
                    id: index == 0 ? skillID : "component-\(index)",
                    name: index == 0 ? "Demo" : "Component \(index)",
                    kind: "skill",
                    required: true,
                    installed: true,
                    status: "installed",
                    location: index == 0 ? skillID : "component-\(index)"
                )
            }
        } else if type == .standalone {
            components = [
                PackageComponent(
                    id: skillID,
                    name: "Demo",
                    kind: "skill",
                    required: true,
                    installed: true,
                    status: "installed",
                    location: skillID
                )
            ]
        } else {
            components = []
        }

        return CapabilityPackage(
            id: "pkg:\(type.rawValue)",
            type: type,
            name: type.title,
            vendor: nil,
            summary: "Demo package",
            source: PackageSource(kind: "builtin", location: "popskill/demo", updateStrategy: "manual"),
            components: PackageComponents(cli: [], skills: components, mcp: [], agents: []),
            configSchema: [],
            installed: installedComponents > 0 || type == .standalone
        )
    }
}
