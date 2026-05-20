@testable import Popskill
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
}
