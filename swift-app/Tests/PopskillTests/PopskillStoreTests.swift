@testable import Popskill
import Foundation
import Testing

@MainActor
struct PopskillStoreTests {
    @Test
    func selectSkillNormalizesRawSkillIDForMatrixInspector() {
        let store = PopskillStore()

        store.selectSkill("owner/repo:demo-skill")

        #expect(store.selectedSkillID == "skill:owner/repo:demo-skill")
        #expect(store.inspectorOpen == true)
    }

    @Test
    func selectCapabilityKeepsAlreadyNamespacedCapabilityID() {
        let store = PopskillStore()

        store.selectCapability("agent:engineering/backend-architect")

        #expect(store.selectedSkillID == "agent:engineering/backend-architect")
        #expect(store.inspectorOpen == true)
    }

    @Test
    func closeInspectorClearsSelection() {
        let store = PopskillStore()
        store.selectSkill("demo-skill")

        store.closeInspector()

        #expect(store.selectedSkillID == nil)
        #expect(store.inspectorOpen == false)
    }

    @Test
    func showMatrixShortcutSetsFiltersAndClearsTransientContext() {
        let store = PopskillStore()
        store.currentSelection = .settings
        store.searchText = "baoyu"
        store.matrixFilter = .claudeOnly
        store.matrixTypeFilter = .skill
        store.selectedSkillID = "skill:demo"
        store.inspectorOpen = true

        store.showMatrix(filter: .brokenLinks)

        #expect(store.currentSelection == .matrix)
        #expect(store.searchText == "")
        #expect(store.matrixFilter == .brokenLinks)
        #expect(store.matrixTypeFilter == .allTypes)
        #expect(store.selectedSkillID == nil)
        #expect(store.inspectorOpen == false)

        store.searchText = "keep"
        store.showMatrix(typeFilter: .bundle, clearSearch: false)

        #expect(store.searchText == "keep")
        #expect(store.matrixFilter == .all)
        #expect(store.matrixTypeFilter == .bundle)
    }

    @Test
    func showSettingsSelectsSettingsWithoutChangingMatrixFilters() {
        let store = PopskillStore()
        store.currentSelection = .matrix
        store.matrixFilter = .brokenLinks
        store.matrixTypeFilter = .bundle

        store.showSettings()

        #expect(store.currentSelection == .settings)
        #expect(store.matrixFilter == .brokenLinks)
        #expect(store.matrixTypeFilter == .bundle)
    }

    @Test
    func matrixShortcutCountsUseCurrentCapabilities() {
        let store = PopskillStore()
        var claudeOnly = skillFixture(
            id: "claude-only",
            apps: SkillApps(claude: true, codex: false, gemini: false, opencode: false, hermes: false)
        )
        claudeOnly.deployment = SkillDeployment(
            strategy: "symlink",
            ssotPath: "/Users/example/.cc-switch/skills/claude-only",
            appLinks: [
                "claude": AppLinkStatus(path: "/Users/example/.claude/skills/claude-only", status: "broken")
            ]
        )
        store.skills = [
            claudeOnly,
            skillFixture(
                id: "codex-only",
                apps: SkillApps(claude: false, codex: true, gemini: false, opencode: false, hermes: false)
            ),
            skillFixture(
                id: "both",
                apps: SkillApps(claude: true, codex: true, gemini: false, opencode: false, hermes: false)
            )
        ]
        store.localAgents = [
            LocalAgent(
                id: "agent:demo",
                name: "Demo Agent",
                description: "Agent",
                fileName: "demo.md",
                path: "/tmp/demo.md",
                category: "ops",
                tools: [],
                model: nil,
                lastModifiedAt: nil,
                sizeBytes: 100
            )
        ]
        store.packages = [
            CapabilityPackage(
                id: "pkg:empty",
                type: .composite,
                name: "Empty Bundle",
                vendor: nil,
                summary: "Bundle",
                source: PackageSource(kind: "builtin", location: "empty", updateStrategy: "manual", repoOwner: nil, repoName: nil, repoBranch: nil, readmeUrl: nil),
                components: PackageComponents(cli: [], skills: [], mcp: [], agents: []),
                configSchema: [],
                installed: false,
                lifecycle: nil
            )
        ]

        let counts = store.matrixShortcutCounts()

        #expect(counts.capabilityCount == 5)
        #expect(counts.count(for: .claudeOnly) == 2)
        #expect(counts.count(for: .codexOnly) == 1)
        #expect(counts.count(for: .brokenLinks) == 1)
        #expect(counts.count(for: .bundle) == 1)
        #expect(counts.count(for: .skill) == 3)
        #expect(counts.count(for: .agent) == 1)
        #expect(store.matrixFilterCount(.claudeOnly) == counts.count(for: .claudeOnly))
        #expect(store.matrixTypeFilterCount(.bundle) == counts.count(for: .bundle))
    }

    @Test
    func capabilitiesExposeCompositePackagesBeforeAtomicRows() {
        let store = PopskillStore()
        store.packages = [
            CapabilityPackage(
                id: "pkg:demo",
                type: .composite,
                name: "Demo Bundle",
                vendor: nil,
                summary: "Demo bundle",
                source: PackageSource(
                    kind: "builtin",
                    location: "demo",
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
                            id: "demo-skill",
                            name: "Demo Skill",
                            kind: "skill",
                            required: true,
                            installed: true,
                            status: "installed",
                            location: "demo-skill"
                        )
                    ],
                    mcp: [],
                    agents: []
                ),
                configSchema: [],
                installed: true,
                lifecycle: nil
            ),
            CapabilityPackage(
                id: "pkg:standalone",
                type: .standalone,
                name: "Standalone",
                vendor: nil,
                summary: "Standalone wrapper",
                source: PackageSource(kind: "builtin", location: "standalone", updateStrategy: "manual", repoOwner: nil, repoName: nil, repoBranch: nil, readmeUrl: nil),
                components: PackageComponents(cli: [], skills: [], mcp: [], agents: []),
                configSchema: [],
                installed: false,
                lifecycle: nil
            )
        ]
        store.skills = [
            Skill(
                id: "demo-skill",
                name: "Demo Skill",
                description: "Skill",
                directory: "demo-skill",
                repoOwner: nil,
                repoName: nil,
                readmeUrl: nil,
                apps: SkillApps(claude: true, codex: false, gemini: false, opencode: false, hermes: false),
                installedAt: nil,
                updatedAt: nil,
                contentHash: nil
            )
        ]

        #expect(store.bundleCount == 1)
        #expect(store.capabilities.map(\.kind) == [.bundle, .skill])
        #expect(store.capabilities.first?.appCoverage[.claude]?.label == "1/1")
    }

    @Test
    func bootstrapLoadsPersistedStubsFromSidecar() async throws {
        let client = try fakeClient(stubbedAt: 123)
        let store = PopskillStore(client: client)

        await store.bootstrap()

        #expect(store.stubs.map(\.id) == ["demo-stub"])
        #expect(store.stubs.first?.backupId == "backup-demo-stub")
        #expect(store.errorMessage == nil)
    }

    @Test
    func upsertStubReplacesExistingSkillAndSortsNewestFirst() {
        let store = PopskillStore()

        store.upsertStub(stubFixture(id: "older", stubbedAt: 10))
        store.upsertStub(stubFixture(id: "newer", stubbedAt: 30))
        store.upsertStub(stubFixture(id: "older", stubbedAt: 40))

        #expect(store.stubs.map(\.id) == ["older", "newer"])
        #expect(store.stubs.map(\.stubbedAt) == [40, 30])
    }

    private func fakeClient(stubbedAt: Int) throws -> SkillCLIClient {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopskillStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake-skill-cli")
        let script = """
        #!/bin/sh
        case "$1" in
          list|repo-list|agent-list|package-list)
            printf '{"ok":true,"data":[]}'
            ;;
          stub-list)
            cat <<'JSON'
        {"ok":true,"data":[{"skill":{"id":"demo-stub","name":"Demo Stub","description":"Persisted stub","directory":"demo-stub","repo_owner":null,"repo_name":null,"readme_url":null,"apps":{"claude":false,"codex":false,"gemini":false,"opencode":false,"hermes":false},"installed_at":null,"updated_at":null,"content_hash":null},"backup_id":"backup-demo-stub","backup_path":"/tmp/backup-demo-stub","stubbed_at":\(stubbedAt)}]}
        JSON
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executable.path
        )
        return SkillCLIClient(executableURL: executable)
    }

    private func stubFixture(id: String, stubbedAt: Int) -> StubbedSkill {
        StubbedSkill(
            skill: skillFixture(
                id: id,
                description: "Stub fixture",
                apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false)
            ),
            backupId: "backup-\(id)",
            backupPath: "/tmp/backup-\(id)",
            stubbedAt: stubbedAt
        )
    }

    private func skillFixture(
        id: String,
        description: String = "Skill",
        apps: SkillApps
    ) -> Skill {
        Skill(
            id: id,
            name: id,
            description: description,
            directory: id,
            repoOwner: nil,
            repoName: nil,
            readmeUrl: nil,
            apps: apps,
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil
        )
    }
}
