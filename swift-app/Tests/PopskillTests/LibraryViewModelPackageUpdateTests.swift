@testable import Popskill
import Foundation
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

    @Test
    func recoverableStubForComponentMatchesSkillStubByDirectory() {
        let viewModel = LibraryViewModel()
        let stubbedSkill = Skill(
            id: "owner/repo:lark-doc",
            name: "Lark Doc",
            description: "Doc skill",
            directory: "lark-doc",
            repoOwner: "owner",
            repoName: "repo",
            readmeUrl: nil,
            apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false),
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil
        )

        viewModel.stubs = [
            StubbedSkill(
                skill: stubbedSkill,
                backupId: "backup-1",
                backupPath: "/tmp/backup-1",
                stubbedAt: 100
            )
        ]

        let component = PackageComponent(
            id: "lark-doc",
            name: "Lark Doc",
            kind: "skill",
            required: true,
            installed: false,
            status: "stub",
            location: "lark-doc"
        )

        #expect(viewModel.recoverableStub(for: component)?.id == "owner/repo:lark-doc")
    }

    @Test
    func enabledSkillCountTracksEachTargetApp() {
        let viewModel = LibraryViewModel()
        viewModel.skills = [
            Skill(
                id: "skill-a",
                name: "Skill A",
                description: "",
                directory: "skill-a",
                repoOwner: nil,
                repoName: nil,
                readmeUrl: nil,
                apps: SkillApps(claude: true, codex: false, gemini: true, opencode: false, hermes: false),
                installedAt: nil,
                updatedAt: nil,
                contentHash: nil
            ),
            Skill(
                id: "skill-b",
                name: "Skill B",
                description: "",
                directory: "skill-b",
                repoOwner: nil,
                repoName: nil,
                readmeUrl: nil,
                apps: SkillApps(claude: false, codex: true, gemini: false, opencode: true, hermes: false),
                installedAt: nil,
                updatedAt: nil,
                contentHash: nil
            )
        ]

        #expect(viewModel.enabledSkillCount(for: .claude) == 1)
        #expect(viewModel.enabledSkillCount(for: .codex) == 1)
        #expect(viewModel.enabledSkillCount(for: .gemini) == 1)
        #expect(viewModel.enabledSkillCount(for: .opencode) == 1)
        #expect(viewModel.enabledSkillCount(for: .hermes) == 0)
    }

    @Test
    func packageEnabledSkillCountUsesInstalledMatchingSkillComponents() {
        let viewModel = LibraryViewModel()
        viewModel.skills = [
            Skill(
                id: "owner/repo:lark-doc",
                name: "Lark Doc",
                description: "",
                directory: "lark-doc",
                repoOwner: "owner",
                repoName: "repo",
                readmeUrl: nil,
                apps: SkillApps(claude: true, codex: false, gemini: true, opencode: false, hermes: false),
                installedAt: nil,
                updatedAt: nil,
                contentHash: nil
            ),
            Skill(
                id: "owner/repo:lark-base",
                name: "Lark Base",
                description: "",
                directory: "lark-base",
                repoOwner: "owner",
                repoName: "repo",
                readmeUrl: nil,
                apps: SkillApps(claude: false, codex: true, gemini: false, opencode: false, hermes: false),
                installedAt: nil,
                updatedAt: nil,
                contentHash: nil
            )
        ]

        let package = CapabilityPackage(
            id: "pkg:lark",
            type: .composite,
            name: "Lark",
            vendor: nil,
            summary: "Lark package",
            source: PackageSource(
                kind: "builtin",
                location: "popskill/builtin/lark",
                updateStrategy: "manual",
                repoOwner: nil,
                repoName: nil,
                repoBranch: nil,
                readmeUrl: nil
            ),
            components: PackageComponents(
                cli: [],
                skills: [
                    PackageComponent(id: "lark-doc", name: "Lark Doc", kind: "skill", required: true, installed: true, status: "installed", location: "lark-doc"),
                    PackageComponent(id: "lark-base", name: "Lark Base", kind: "skill", required: true, installed: true, status: "installed", location: "lark-base")
                ],
                mcp: [],
                agents: []
            ),
            configSchema: [],
            installed: true,
            lifecycle: nil
        )

        #expect(viewModel.enabledSkillCount(for: .claude, in: package) == 1)
        #expect(viewModel.enabledSkillCount(for: .codex, in: package) == 1)
        #expect(viewModel.enabledSkillCount(for: .gemini, in: package) == 1)
        #expect(viewModel.enabledSkillCount(for: .hermes, in: package) == 0)
    }

    @Test
    func packageEnabledSkillCountIgnoresUninstalledOrUnmatchedComponents() {
        let viewModel = LibraryViewModel()
        viewModel.skills = [
            Skill(
                id: "owner/repo:lark-doc",
                name: "Lark Doc",
                description: "",
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

        let package = CapabilityPackage(
            id: "pkg:lark",
            type: .composite,
            name: "Lark",
            vendor: nil,
            summary: "Lark package",
            source: PackageSource(
                kind: "builtin",
                location: "popskill/builtin/lark",
                updateStrategy: "manual",
                repoOwner: nil,
                repoName: nil,
                repoBranch: nil,
                readmeUrl: nil
            ),
            components: PackageComponents(
                cli: [],
                skills: [
                    PackageComponent(id: "lark-doc", name: "Lark Doc", kind: "skill", required: true, installed: false, status: "declared", location: "lark-doc"),
                    PackageComponent(id: "lark-missing", name: "Lark Missing", kind: "skill", required: true, installed: true, status: "installed", location: "lark-missing")
                ],
                mcp: [],
                agents: []
            ),
            configSchema: [],
            installed: true,
            lifecycle: nil
        )

        #expect(viewModel.enabledSkillCount(for: .claude, in: package) == 0)
    }

    @Test
    func packageCardSignalsExposeUpdateRecoveryAndLastCheck() {
        let viewModel = LibraryViewModel()
        viewModel.updates = [
            SkillUpdateInfo(id: "lark-doc", name: "Lark Doc", currentHash: nil, remoteHash: "def456")
        ]
        let referenceDate = Date(timeIntervalSince1970: 1_778_700_000)
        viewModel.lastCheckedUpdatesAt = referenceDate

        let package = CapabilityPackage(
            id: "pkg:lark",
            type: .composite,
            name: "Lark",
            vendor: nil,
            summary: "Lark package",
            source: PackageSource(
                kind: "builtin",
                location: "popskill/builtin/lark",
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
                        id: "lark-doc",
                        name: "Lark Doc",
                        kind: "skill",
                        required: true,
                        installed: false,
                        status: "stub",
                        location: "lark-doc"
                    )
                ],
                mcp: [],
                agents: []
            ),
            configSchema: [],
            installed: true,
            lifecycle: nil
        )

        let signals = viewModel.packageCardSignals(for: package)

        #expect(signals.pendingUpdates == 1)
        #expect(signals.recoverableMissingComponents == 1)
        #expect(signals.missingRequiredComponents == 1)
        #expect(signals.lastCheckedUpdatesAt == referenceDate)
        #expect(signals.installedSkillComponentCount == 0)
        #expect(signals.appEnabledCounts.count == TargetApp.supported.count)
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
