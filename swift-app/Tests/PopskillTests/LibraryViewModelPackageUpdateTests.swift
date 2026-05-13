@testable import Popskill
import Testing

@MainActor
struct LibraryViewModelPackageUpdateTests {
    @Test
    func updatesForPackageMatchesInstalledSkillIdentifiers() {
        let viewModel = LibraryViewModel()
        viewModel.skills = [
            Skill(
                id: "owner/repo:lark-doc",
                name: "Lark Doc",
                description: "Doc skill",
                directory: "lark-doc",
                repoOwner: "owner",
                repoName: "repo",
                readmeUrl: nil,
                apps: SkillApps(claude: true, codex: false, gemini: false, opencode: false, hermes: false),
                installedAt: nil,
                updatedAt: nil,
                contentHash: nil
            )
        ]
        viewModel.updates = [
            SkillUpdateInfo(id: "owner/repo:lark-doc", name: "Lark Doc", currentHash: "abc123", remoteHash: "def456"),
            SkillUpdateInfo(id: "other-skill", name: "Other", currentHash: nil, remoteHash: "remote")
        ]

        let package = packageWithSkillComponent(id: "lark-doc", name: "Lark Doc", location: "lark-doc")
        let matching = viewModel.updates(for: package)

        #expect(matching.map(\.id) == ["owner/repo:lark-doc"])
    }

    @Test
    func updatesForPackageMatchesComponentIdentifierWithoutInstalledSkill() {
        let viewModel = LibraryViewModel()
        viewModel.updates = [
            SkillUpdateInfo(id: "lark-doc", name: "Lark Doc", currentHash: nil, remoteHash: "def456"),
            SkillUpdateInfo(id: "owner/repo:lark-base", name: "Lark Base", currentHash: nil, remoteHash: "zzz999")
        ]

        let package = packageWithSkillComponent(id: "lark-doc", name: "Lark Doc", location: nil)
        let matching = viewModel.updates(for: package)

        #expect(matching.map(\.id) == ["lark-doc"])
    }

    @Test
    func updatesForPackageIgnoresNonSkillComponents() {
        let viewModel = LibraryViewModel()
        viewModel.updates = [
            SkillUpdateInfo(id: "lark-doc", name: "Lark Doc", currentHash: nil, remoteHash: "def456")
        ]

        let package = CapabilityPackage(
            id: "pkg:lark-cli",
            type: .composite,
            name: "Lark CLI",
            vendor: nil,
            summary: "CLI-only package",
            source: PackageSource(
                kind: "builtin",
                location: "popskill/builtin/lark-cli",
                updateStrategy: "manual",
                repoOwner: nil,
                repoName: nil,
                repoBranch: nil,
                readmeUrl: nil
            ),
            components: PackageComponents(
                cli: [
                    PackageComponent(
                        id: "lark-cli",
                        name: "lark-cli",
                        kind: "cli",
                        required: true,
                        installed: true,
                        status: "detected",
                        location: nil
                    )
                ],
                skills: [],
                mcp: [],
                agents: []
            ),
            configSchema: [],
            installed: true,
            lifecycle: nil
        )

        #expect(viewModel.updates(for: package).isEmpty)
    }

    private func packageWithSkillComponent(id: String, name: String, location: String?) -> CapabilityPackage {
        CapabilityPackage(
            id: "pkg:\(id)",
            type: .composite,
            name: "Demo Package",
            vendor: nil,
            summary: "Demo package",
            source: PackageSource(
                kind: "builtin",
                location: "popskill/builtin/demo",
                updateStrategy: "manual",
                repoOwner: nil,
                repoName: nil,
                repoBranch: nil,
                readmeUrl: nil
            ),
            components: PackageComponents(
                cli: [],
                skills: [
                    PackageComponent(
                        id: id,
                        name: name,
                        kind: "skill",
                        required: true,
                        installed: true,
                        status: "installed",
                        location: location
                    )
                ],
                mcp: [],
                agents: []
            ),
            configSchema: [],
            installed: true,
            lifecycle: nil
        )
    }
}
