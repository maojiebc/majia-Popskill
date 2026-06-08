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
    func matrixBulkSelectingBundleSelectsComponentsAndCountsLeaves() throws {
        let store = PopskillStore()
        store.skills = [
            skillFixture(
                id: "demo-skill",
                apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false)
            ),
            skillFixture(
                id: "helper-skill",
                apps: SkillApps(claude: false, codex: true, gemini: false, opencode: false, hermes: false)
            ),
            skillFixture(
                id: "standalone",
                apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false)
            )
        ]
        store.packages = [bulkPackageFixture()]

        let capabilities = store.capabilities
        let bundle = try #require(capabilities.first(where: { $0.kind == .bundle }))
        let package = try #require(bundle.package)

        store.toggleMatrixBulkSelection(for: bundle)
        let summary = store.matrixBulkSelectionSummary(capabilities: capabilities)

        #expect(store.matrixBulkSelectionState(for: bundle) == .selected)
        #expect(store.matrixBulkSelectionState(packageID: package.id, component: package.components.skills[0]) == .selected)
        #expect(summary.topLevelCount == 1)
        #expect(summary.leafCount == 3)
        #expect(summary.selectedBundleCount == 1)
        #expect(summary.selectedChildCount == 3)
        #expect(store.matrixBulkSelectedSkillIDs(capabilities: capabilities) == ["demo-skill", "helper-skill"])
    }

    @Test
    func matrixBulkSelectingChildWithoutBundleCountsAsOrphanLeaf() throws {
        let store = PopskillStore()
        store.skills = [
            skillFixture(
                id: "demo-skill",
                apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false)
            )
        ]
        store.packages = [bulkPackageFixture()]

        let bundle = try #require(store.capabilities.first(where: { $0.kind == .bundle }))
        let package = try #require(bundle.package)
        let child = package.components.skills[0]

        store.toggleMatrixBulkComponentSelection(packageID: package.id, component: child)
        let summary = store.matrixBulkSelectionSummary(capabilities: store.capabilities)

        #expect(store.matrixBulkSelectionState(for: bundle) == .mixed)
        #expect(summary.topLevelCount == 1)
        #expect(summary.leafCount == 1)
        #expect(summary.selectedBundleCount == 0)
        #expect(summary.selectedChildCount == 1)
    }

    @Test
    func matrixBulkEnableSelectedSkillsCallsSidecarAndUpdatesApps() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopskillBulkToggle-\(UUID().uuidString).log")
        let client = try fakeClient(script: """
        #!/bin/sh
        case "$1" in
          toggle)
            printf '%s|%s|%s\\n' "$2" "$4" "$6" >> "\(logURL.path)"
            printf '{"ok":true,"data":{"id":"%s","app":"%s","enabled":%s}}' "$2" "$4" "$6"
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """)
        let store = PopskillStore(client: client)
        store.skills = [
            skillFixture(
                id: "demo-skill",
                apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false)
            ),
            skillFixture(
                id: "helper-skill",
                apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false)
            )
        ]
        store.packages = [bulkPackageFixture()]
        let bundle = try #require(store.capabilities.first(where: { $0.kind == .bundle }))
        store.toggleMatrixBulkSelection(for: bundle)

        let ok = await store.matrixBulkSetSelectedSkills(app: .claude, enabled: true, capabilities: store.capabilities)

        #expect(ok)
        #expect(store.skills.allSatisfy { $0.apps.claude })
        let log = try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        #expect(log == ["demo-skill|claude|true", "helper-skill|claude|true"])
        #expect(store.errorMessage == nil)
    }

    @Test
    func bootstrapLoadsPersistedStubsFromSidecar() async throws {
        let client = try fakeClient(stubbedAt: 123)
        let suiteName = "PopskillStoreTests-\(UUID().uuidString)"
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PopskillStore(client: client, userDefaults: defaults)

        await store.bootstrap()

        #expect(store.stubs.map(\.id) == ["demo-stub"])
        #expect(store.stubs.first?.backupId == "backup-demo-stub")
        #expect(store.errorMessage == nil)
    }

    @Test
    func syncPreferencesPersistThroughInjectedDefaults() throws {
        let suiteName = "PopskillStoreTests-\(UUID().uuidString)"
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PopskillStore(userDefaults: defaults)
        store.lastSyncProvider = "icloud"
        store.autoSyncEnabled = true
        store.lastSyncAt = Date(timeIntervalSince1970: 1_778_000_000)

        let restored = PopskillStore(userDefaults: defaults)

        #expect(restored.lastSyncProvider == "icloud")
        #expect(restored.autoSyncEnabled)
        #expect(restored.lastSyncAt == Date(timeIntervalSince1970: 1_778_000_000))
    }

    @Test
    func settingsPreferencesDefaultOnAndPersistThroughInjectedDefaults() throws {
        let suiteName = "PopskillStoreTests-\(UUID().uuidString)"
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunch = PopskillStore(userDefaults: defaults)

        #expect(firstLaunch.defaultInstallClaude)
        #expect(firstLaunch.defaultInstallCodex)
        #expect(firstLaunch.installVerificationMode == .strict)
        #expect(firstLaunch.installAutoUpdatePolicy == .weekly)
        #expect(firstLaunch.quotaMonthlyTokenBudget == 2_000_000)
        #expect(firstLaunch.quotaWarningThresholdPercent == 80)
        #expect(firstLaunch.quotaWarningTokenCount == 1_600_000)
        #expect(firstLaunch.quotaTrackingEnabled)
        #expect(firstLaunch.defaultInstallTargets == [.claude, .codex])
        #expect(firstLaunch.quotaUsageState(for: 1_599_999) == .normal)
        #expect(firstLaunch.quotaUsageState(for: 1_600_000) == .warning)
        #expect(firstLaunch.quotaUsageState(for: 2_000_000) == .exceeded)

        firstLaunch.defaultInstallClaude = false
        firstLaunch.defaultInstallCodex = true
        firstLaunch.installVerificationMode = .warn
        firstLaunch.installAutoUpdatePolicy = .manual
        firstLaunch.quotaMonthlyTokenBudget = 500_000
        firstLaunch.quotaWarningThresholdPercent = 60
        firstLaunch.quotaTrackingEnabled = false

        let restored = PopskillStore(userDefaults: defaults)

        #expect(!restored.defaultInstallClaude)
        #expect(restored.defaultInstallCodex)
        #expect(restored.installVerificationMode == .warn)
        #expect(restored.installAutoUpdatePolicy == .manual)
        #expect(restored.quotaMonthlyTokenBudget == 500_000)
        #expect(restored.quotaWarningThresholdPercent == 60)
        #expect(restored.quotaWarningTokenCount == 300_000)
        #expect(!restored.quotaTrackingEnabled)
        #expect(restored.defaultInstallTargets == [.codex])
        #expect(restored.quotaUsageState(for: 500_000) == .trackingOff)
    }

    @Test
    func usageScanIsClearedWhenQuotaTrackingIsDisabled() async {
        let store = PopskillStore()
        store.usageSummary = UsageSummary(usageEvents: 1, inputTokens: 120)
        store.usageScanError = "stale"
        store.quotaTrackingEnabled = false

        await store.refreshUsageScan()

        #expect(store.usageSummary == nil)
        #expect(store.usageScanError == nil)
        #expect(!store.usageScanInFlight)
    }

    @Test
    func bootstrapRunsStartupAutoPullBeforeLoadingInventory() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopskillAutoSync-\(UUID().uuidString).log")
        let client = try fakeClient(script: """
        #!/bin/sh
        printf '%s\\n' "$*" >> "\(logURL.path)"
        case "$1" in
          sync)
            if [ "$2" != "pull" ] || [ "$3" != "--provider" ] || [ "$4" != "icloud" ]; then
              printf '{"ok":false,"error":{"code":"BAD_SYNC","message":"unexpected sync args"}}'
              exit 1
            fi
            printf '{"ok":true,"data":{"provider":"icloud","action":"pull","ok":true,"message":"pulled"}}'
            ;;
          list)
            cat <<'JSON'
        {"ok":true,"data":[{"id":"synced-skill","name":"Synced Skill","description":"Pulled from remote","directory":"synced-skill","repo_owner":null,"repo_name":null,"readme_url":null,"apps":{"claude":true,"codex":false,"gemini":false,"opencode":false,"hermes":false},"installed_at":null,"updated_at":null,"content_hash":"remote"}]}
        JSON
            ;;
          repo-list|agent-list|package-list|stub-list)
            printf '{"ok":true,"data":[]}'
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """)
        let suiteName = "PopskillStoreTests-\(UUID().uuidString)"
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PopskillStore(client: client, userDefaults: defaults)
        store.lastSyncProvider = "icloud"
        store.autoSyncEnabled = true

        await store.bootstrap()

        let invocations = try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        #expect(invocations.first == "sync pull --provider icloud --json")
        #expect(store.skills.map(\.id) == ["synced-skill"])
        #expect(store.lastSyncResult?.provider == "icloud")
        #expect(store.lastSyncResult?.action == "pull")
        #expect(store.lastAutoSyncAttemptAt != nil)
        #expect(store.lastSyncAt != nil)
        #expect(store.errorMessage == nil)
    }

    @Test
    func manualPullRefreshesCoreInventoryAfterSuccessfulSync() async throws {
        let client = try fakeClient(script: """
        #!/bin/sh
        case "$1" in
          sync)
            printf '{"ok":true,"data":{"provider":"git","action":"pull","ok":true,"message":"pulled"}}'
            ;;
          list)
            cat <<'JSON'
        {"ok":true,"data":[{"id":"after-pull","name":"After Pull","description":"Reloaded","directory":"after-pull","repo_owner":null,"repo_name":null,"readme_url":null,"apps":{"claude":false,"codex":true,"gemini":false,"opencode":false,"hermes":false},"installed_at":null,"updated_at":null,"content_hash":"fresh"}]}
        JSON
            ;;
          repo-list|agent-list|package-list|stub-list)
            printf '{"ok":true,"data":[]}'
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """)
        let suiteName = "PopskillStoreTests-\(UUID().uuidString)"
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PopskillStore(client: client, userDefaults: defaults)

        let result = await store.runSync(.pull, provider: .git)

        #expect(result?.ok == true)
        #expect(store.skills.map(\.id) == ["after-pull"])
        #expect(store.lastSyncAt != nil)
        #expect(store.errorMessage == nil)
    }

    @Test
    func refreshCatalogLoadsDiscoverableSkillsFromSidecar() async throws {
        let client = try fakeClient(script: """
        #!/bin/sh
        case "$1" in
          discover)
            if [ "$2" != "--json" ] || [ "$3" != "--limit" ] || [ "$4" != "80" ]; then
              printf '{"ok":false,"error":{"code":"BAD_ARGS","message":"unexpected discover args"}}'
              exit 1
            fi
            cat <<'JSON'
        {"ok":true,"data":[{"key":"owner/repo:demo-skill","name":"Demo Skill","description":"Installable","directory":"demo-skill","readme_url":"https://example.com/readme","installed":false,"repo_owner":"owner","repo_name":"repo","repo_branch":"main"}]}
        JSON
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """)
        let store = PopskillStore(client: client)

        await store.refreshCatalog(force: true)

        #expect(store.catalogSkills.map(\.key) == ["owner/repo:demo-skill"])
        #expect(store.catalogSkills.first?.sourceLabel == "owner/repo")
        #expect(store.catalogError == nil)
        #expect(store.lastCatalogRefreshAt != nil)
    }

    @Test
    func catalogInstallPlansUseDefaultTargets() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopskillCatalogInstallPlan-\(UUID().uuidString).log")
        let client = try fakeClient(script: """
        #!/bin/sh
        printf '%s\\n' "$*" >> "\(logURL.path)"
        case "$1" in
          install-plan)
            if [ "$2" != "owner/repo:demo-skill" ] || [ "$3" != "--app" ] || [ "$5" != "--json" ]; then
              printf '{"ok":false,"error":{"code":"BAD_ARGS","message":"unexpected install-plan args"}}'
              exit 1
            fi
            case "$4" in
              claude)
                printf '{"ok":true,"data":{"skillKey":"owner/repo:demo-skill","name":"Demo Skill","description":"Installable","targetApp":"claude","installDirectory":"demo-skill","source":{"repoOwner":"owner","repoName":"repo","repoBranch":"main","readmeUrl":"https://example.com/readme"},"existingSkillId":null,"writes":{"ssotPath":"/tmp/store/demo-skill","appSkillPath":"/tmp/.claude/skills/demo-skill"},"securityGate":"agentShieldPostInstallRollback","steps":["downloadFromRepository","copyToSkillStore","enableTargetApp"]}}'
                ;;
              codex)
                printf '{"ok":true,"data":{"skillKey":"owner/repo:demo-skill","name":"Demo Skill","description":"Installable","targetApp":"codex","installDirectory":"demo-skill","source":{"repoOwner":"owner","repoName":"repo","repoBranch":"main","readmeUrl":"https://example.com/readme"},"existingSkillId":null,"writes":{"ssotPath":"/tmp/store/demo-skill","appSkillPath":"/tmp/.codex/skills/demo-skill"},"securityGate":"agentShieldPostInstallRollback","steps":["downloadFromRepository","copyToSkillStore","enableTargetApp"]}}'
                ;;
              *)
                printf '{"ok":false,"error":{"code":"BAD_APP","message":"unexpected app"}}'
                exit 1
                ;;
            esac
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """)
        let suiteName = "PopskillStoreTests-\(UUID().uuidString)"
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PopskillStore(client: client, userDefaults: defaults)
        let catalog = CatalogSkill(
            key: "owner/repo:demo-skill",
            name: "Demo Skill",
            description: "Installable",
            directory: "demo-skill",
            readmeUrl: nil,
            installed: false,
            repoOwner: "owner",
            repoName: "repo",
            repoBranch: "main"
        )

        let plans = try await store.catalogInstallPlans(catalog)

        #expect(plans.map(\.targetApp) == ["claude", "codex"])
        #expect(plans.compactMap(\.writes.appSkillPath) == [
            "/tmp/.claude/skills/demo-skill",
            "/tmp/.codex/skills/demo-skill"
        ])
        #expect(plans.allSatisfy { $0.skillKey == "owner/repo:demo-skill" })

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("install-plan owner/repo:demo-skill --app claude --json"))
        #expect(log.contains("install-plan owner/repo:demo-skill --app codex --json"))
    }

    @Test
    func installCatalogSkillUsesDefaultTargetsAndSelectsInstalledSkill() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopskillCatalogInstall-\(UUID().uuidString).log")
        let client = try fakeClient(script: """
        #!/bin/sh
        printf '%s\\n' "$*" >> "\(logURL.path)"
        case "$1" in
          install)
            if [ "$2" != "owner/repo:demo-skill" ] || [ "$3" != "--app" ] || [ "$5" != "--json" ]; then
              printf '{"ok":false,"error":{"code":"BAD_ARGS","message":"unexpected install args"}}'
              exit 1
            fi
            case "$4" in
              claude)
                printf '{"ok":true,"data":{"id":"owner/repo:demo-skill","name":"Demo Skill","description":"Installed","directory":"demo-skill","repo_owner":"owner","repo_name":"repo","readme_url":null,"apps":{"claude":true,"codex":false,"gemini":false,"opencode":false,"hermes":false},"installed_at":1770000000,"updated_at":null,"content_hash":"claude-hash"}}'
                ;;
              codex)
                printf '{"ok":true,"data":{"id":"owner/repo:demo-skill","name":"Demo Skill","description":"Installed","directory":"demo-skill","repo_owner":"owner","repo_name":"repo","readme_url":null,"apps":{"claude":false,"codex":true,"gemini":false,"opencode":false,"hermes":false},"installed_at":1770000000,"updated_at":null,"content_hash":"codex-hash"}}'
                ;;
              *)
                printf '{"ok":false,"error":{"code":"BAD_APP","message":"unexpected app"}}'
                exit 1
                ;;
            esac
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """)
        let suiteName = "PopskillStoreTests-\(UUID().uuidString)"
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PopskillStore(client: client, userDefaults: defaults)
        let catalog = CatalogSkill(
            key: "owner/repo:demo-skill",
            name: "Demo Skill",
            description: "Installable",
            directory: "demo-skill",
            readmeUrl: nil,
            installed: false,
            repoOwner: "owner",
            repoName: "repo",
            repoBranch: "main"
        )
        store.catalogSkills = [catalog]

        let ok = await store.installCatalogSkill(catalog)

        #expect(ok)
        #expect(store.skills.map(\.id) == ["owner/repo:demo-skill"])
        #expect(store.skills.first?.apps.claude == true)
        #expect(store.skills.first?.apps.codex == true)
        #expect(store.skills.first?.contentHash == "codex-hash")
        #expect(store.catalogSkills.first?.installed == true)
        #expect(store.currentSelection == .matrix)
        #expect(store.selectedSkillID == "skill:owner/repo:demo-skill")
        #expect(store.lastSyncAt != nil)
        #expect(store.errorMessage == nil)

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("install owner/repo:demo-skill --app claude --json"))
        #expect(log.contains("install owner/repo:demo-skill --app codex --json"))
    }

    @Test
    func installCatalogSkillRequiresADefaultTarget() async throws {
        let client = try fakeClient(script: """
        #!/bin/sh
        printf '{"ok":false,"error":{"code":"SHOULD_NOT_RUN","message":"install should not be called"}}'
        exit 1
        """)
        let suiteName = "PopskillStoreTests-\(UUID().uuidString)"
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PopskillStore(client: client, userDefaults: defaults)
        store.defaultInstallClaude = false
        store.defaultInstallCodex = false
        let catalog = CatalogSkill(
            key: "owner/repo:demo-skill",
            name: "Demo Skill",
            description: "Installable",
            directory: "demo-skill",
            readmeUrl: nil,
            installed: false,
            repoOwner: "owner",
            repoName: "repo",
            repoBranch: "main"
        )

        let ok = await store.installCatalogSkill(catalog)

        #expect(!ok)
        #expect(store.skills.isEmpty)
        #expect(store.errorMessage == "No default install target selected.")
    }

    @Test
    func catalogInstallPlansRequireDefaultTarget() async throws {
        let client = try fakeClient(script: """
        #!/bin/sh
        printf '{"ok":false,"error":{"code":"SHOULD_NOT_RUN","message":"install-plan should not be called"}}'
        exit 1
        """)
        let suiteName = "PopskillStoreTests-\(UUID().uuidString)"
        let defaults = try temporaryDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PopskillStore(client: client, userDefaults: defaults)
        store.defaultInstallClaude = false
        store.defaultInstallCodex = false
        let catalog = CatalogSkill(
            key: "owner/repo:demo-skill",
            name: "Demo Skill",
            description: "Installable",
            directory: "demo-skill",
            readmeUrl: nil,
            installed: false,
            repoOwner: "owner",
            repoName: "repo",
            repoBranch: "main"
        )

        var caught: CatalogInstallError?
        do {
            _ = try await store.catalogInstallPlans(catalog)
        } catch let error as CatalogInstallError {
            caught = error
        } catch {
            caught = nil
        }

        #expect(caught == .noDefaultTarget)
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

    @Test
    func updateInstalledSkillUpsertsReturnedSkillAndClearsMatchingPendingUpdate() async throws {
        let client = try fakeClient(script: """
        #!/bin/sh
        case "$1" in
          update)
            cat <<'JSON'
        {"ok":true,"data":{"id":"owner/repo:demo-skill","name":"Demo Skill","description":"Updated","directory":"demo-skill","repo_owner":"owner","repo_name":"repo","readme_url":null,"apps":{"claude":true,"codex":false,"gemini":false,"opencode":false,"hermes":false},"installed_at":null,"updated_at":1770000000,"content_hash":"remote-hash"}}
        JSON
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """)
        let store = PopskillStore(client: client)
        store.skills = [
            skillFixture(
                id: "owner/repo:demo-skill",
                apps: SkillApps(claude: true, codex: false, gemini: false, opencode: false, hermes: false)
            )
        ]
        store.updates = [
            SkillUpdateInfo(id: "owner/repo:demo-skill", name: "Demo Skill", currentHash: "local-hash", remoteHash: "remote-hash")
        ]

        let ok = await store.updateInstalledSkill(store.updates[0])

        #expect(ok)
        #expect(store.skills.first?.description == "Updated")
        #expect(store.skills.first?.contentHash == "remote-hash")
        #expect(store.updates.isEmpty)
        #expect(store.errorMessage == nil)
    }

    @Test
    func repairLinkHealthRowRelinksBrokenTargetsAndRefreshesHealth() async throws {
        let client = try fakeClient(script: """
        #!/bin/sh
        case "$1" in
          toggle)
            printf '{"ok":true,"data":{"id":"demo-skill","app":"claude","enabled":true}}'
            ;;
          link-health)
            cat <<'JSON'
        {"ok":true,"data":{"summary":{"ok":1,"broken":0,"inactive":0},"rows":[{"skill_id":"demo-skill","skill_name":"Demo Skill","deployment":{"strategy":"symlink","ssot_path":"/tmp/demo-skill","app_links":{"claude":{"path":"/tmp/.claude/skills/demo-skill","status":"ok"}}}}]}}
        JSON
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """)
        let store = PopskillStore(client: client)
        store.skills = [
            skillFixture(
                id: "demo-skill",
                apps: SkillApps(claude: false, codex: false, gemini: false, opencode: false, hermes: false)
            )
        ]
        let row = LinkHealthRow(
            skillId: "demo-skill",
            skillName: "Demo Skill",
            deployment: SkillDeployment(
                strategy: "symlink",
                ssotPath: "/tmp/demo-skill",
                appLinks: [
                    "claude": AppLinkStatus(path: "/tmp/.claude/skills/demo-skill", status: "broken")
                ]
            )
        )

        let ok = await store.repairLinkHealthRow(row, action: .relink)

        #expect(ok)
        #expect(store.skills.first?.apps.claude == true)
        #expect(store.linkHealth?.summary.broken == 0)
        #expect(store.errorMessage == nil)
    }

    @Test
    func createLocalSkillWritesSkillMarkdownImportsAndSelectsSkill() async throws {
        let client = try fakeClient(script: """
        #!/bin/sh
        case "$1" in
          import-unmanaged)
            if [ "$2" != "demo-skill" ] || [ "$3" != "--json" ] || [ "$4" != "--app" ] || [ "$5" != "claude" ] || [ "$6" != "--app" ] || [ "$7" != "codex" ]; then
              printf '{"ok":false,"error":{"code":"BAD_ARGS","message":"unexpected import args"}}'
              exit 1
            fi
            cat <<'JSON'
        {"ok":true,"data":[{"id":"local:demo-skill","name":"Demo Skill!","description":"Created locally","directory":"demo-skill","repo_owner":null,"repo_name":null,"readme_url":null,"apps":{"claude":true,"codex":true,"gemini":false,"opencode":false,"hermes":false},"installed_at":1770000000,"updated_at":null,"content_hash":"created-hash"}]}
        JSON
            ;;
          package-list)
            printf '{"ok":true,"data":[]}'
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopskillCreateStore-\(UUID().uuidString)", isDirectory: true)
        let store = PopskillStore(client: client, localSkillStoreURL: storeRoot)

        let ok = await store.createLocalSkill(CreatedSkillDraft(
            name: "Demo Skill!",
            description: "Created locally",
            author: "me",
            version: "1.2.3",
            bodyMarkdown: """
            ---
            name: ignored
            description: ignored
            ---

            # Real instructions

            Preserve this body.
            """,
            targetApps: [.claude, .codex]
        ))

        #expect(ok)
        #expect(store.skills.map(\.id) == ["local:demo-skill"])
        #expect(store.skills.first?.apps.claude == true)
        #expect(store.skills.first?.apps.codex == true)
        #expect(store.currentSelection == .matrix)
        #expect(store.selectedSkillID == "skill:local:demo-skill")
        #expect(store.inspectorOpen == true)
        #expect(store.errorMessage == nil)

        let markdownURL = storeRoot
            .appendingPathComponent("demo-skill", isDirectory: true)
            .appendingPathComponent("SKILL.md")
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        #expect(markdown.contains("name: \"Demo Skill!\""))
        #expect(markdown.contains("description: \"Created locally\""))
        #expect(markdown.contains("author: \"me\""))
        #expect(markdown.contains("version: \"1.2.3\""))
        #expect(markdown.contains("# Real instructions"))
        #expect(!markdown.contains("name: ignored"))
    }

    @Test
    func createLocalSkillRejectsExistingStoreDirectoryBeforeImporting() async throws {
        let client = try fakeClient(script: """
        #!/bin/sh
        printf '{"ok":false,"error":{"code":"SHOULD_NOT_RUN","message":"sidecar should not be called"}}'
        exit 1
        """)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopskillExistingStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storeRoot.appendingPathComponent("demo-skill", isDirectory: true),
            withIntermediateDirectories: true
        )
        let store = PopskillStore(client: client, localSkillStoreURL: storeRoot)

        let ok = await store.createLocalSkill(CreatedSkillDraft(
            name: "demo-skill",
            description: "Existing",
            author: "me",
            version: "0.1.0",
            bodyMarkdown: "# Body",
            targetApps: []
        ))

        #expect(!ok)
        #expect(store.skills.isEmpty)
        #expect(store.errorMessage?.contains("already exists") == true)
    }

    @Test
    func createLocalBundleWritesManifestRefreshesPackagesAndSelectsBundle() async throws {
        let client = try fakeClient(script: """
        #!/bin/sh
        case "$1" in
          package-list)
            cat <<'JSON'
        {"ok":true,"data":[{"id":"pkg:local/demo-bundle","type":"composite","name":"Demo Bundle","vendor":"Local","summary":"2 capabilities assembled in Popskill.","source":{"kind":"local-bundle","location":"local:demo-bundle","update_strategy":"local","repo_owner":null,"repo_name":null,"repo_branch":"0.2.0","readme_url":null},"components":{"cli":[],"skills":[{"id":"local:demo-skill","name":"Demo Skill","kind":"skill","required":true,"installed":true,"status":"installed","location":"demo-skill"}],"mcp":[],"agents":[{"id":"demo-agent","name":"Demo Agent","kind":"agent","required":true,"installed":true,"status":"installed","location":"demo-agent.md"}]},"config_schema":[],"installed":true,"lifecycle":{"installed_at":1770000000,"updated_at":null,"content_hash":null}}]}
        JSON
            ;;
          *)
            printf '{"ok":false,"error":{"code":"UNKNOWN","message":"unexpected command"}}'
            exit 1
            ;;
        esac
        """)
        let packageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopskillBundleStore-\(UUID().uuidString)", isDirectory: true)
        let store = PopskillStore(client: client, localPackageStoreURL: packageRoot)

        let ok = await store.createLocalBundle(CreatedBundleDraft(
            name: "Demo Bundle",
            version: "0.2.0",
            upstream: "local",
            items: [
                CreatedBundleItem(
                    id: "local:demo-skill",
                    kind: .skill,
                    name: "Demo Skill",
                    location: "demo-skill"
                ),
                CreatedBundleItem(
                    id: "demo-agent",
                    kind: .agent,
                    name: "Demo Agent",
                    location: "demo-agent.md"
                )
            ]
        ))

        #expect(ok)
        #expect(store.packages.map(\.id) == ["pkg:local/demo-bundle"])
        #expect(store.currentSelection == .matrix)
        #expect(store.selectedSkillID == "bundle:pkg:local/demo-bundle")
        #expect(store.inspectorOpen == true)
        #expect(store.errorMessage == nil)

        let manifestURL = packageRoot
            .appendingPathComponent("demo-bundle", isDirectory: true)
            .appendingPathComponent("popskill.toml")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        #expect(manifest.contains("[bundle]"))
        #expect(manifest.contains("name = \"Demo Bundle\""))
        #expect(manifest.contains("version = \"0.2.0\""))
        #expect(manifest.contains("upstream = \"local\""))
        #expect(manifest.contains("id = \"local:demo-skill\""))
        #expect(!manifest.contains("id = \"skill:local:demo-skill\""))
        #expect(manifest.contains("kind = \"agent\""))
    }

    @Test
    func createLocalBundleRejectsExistingDirectoryBeforeRefreshingPackages() async throws {
        let client = try fakeClient(script: """
        #!/bin/sh
        printf '{"ok":false,"error":{"code":"SHOULD_NOT_RUN","message":"sidecar should not be called"}}'
        exit 1
        """)
        let packageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopskillExistingBundleStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: packageRoot.appendingPathComponent("demo-bundle", isDirectory: true),
            withIntermediateDirectories: true
        )
        let store = PopskillStore(client: client, localPackageStoreURL: packageRoot)

        let ok = await store.createLocalBundle(CreatedBundleDraft(
            name: "demo-bundle",
            version: "0.1.0",
            upstream: "local",
            items: [
                CreatedBundleItem(id: "demo-skill", kind: .skill, name: "Demo Skill", location: "demo-skill")
            ]
        ))

        #expect(!ok)
        #expect(store.packages.isEmpty)
        #expect(store.errorMessage?.contains("already exists") == true)
    }

    private func fakeClient(stubbedAt: Int) throws -> SkillCLIClient {
        try fakeClient(script: """
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
        """)
    }

    private func fakeClient(script: String) throws -> SkillCLIClient {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopskillStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake-skill-cli")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executable.path
        )
        return SkillCLIClient(executableURL: executable)
    }

    private func temporaryDefaults(suiteName: String) throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "PopskillStoreTests", code: 1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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

    private func bulkPackageFixture() -> CapabilityPackage {
        CapabilityPackage(
            id: "pkg:demo-bundle",
            type: .composite,
            name: "Demo Bundle",
            vendor: "Popskill",
            summary: "Bulk fixture",
            source: PackageSource(
                kind: "builtin",
                location: "demo-bundle",
                updateStrategy: "manual",
                repoOwner: nil,
                repoName: nil,
                repoBranch: nil,
                readmeUrl: nil
            ),
            components: PackageComponents(
                cli: [
                    PackageComponent(
                        id: "ripgrep",
                        name: "ripgrep",
                        kind: "cli",
                        required: true,
                        installed: true,
                        status: "installed",
                        location: "rg"
                    )
                ],
                skills: [
                    PackageComponent(
                        id: "demo-skill",
                        name: "demo-skill",
                        kind: "skill",
                        required: true,
                        installed: true,
                        status: "installed",
                        location: "demo-skill"
                    ),
                    PackageComponent(
                        id: "helper-skill",
                        name: "helper-skill",
                        kind: "skill",
                        required: true,
                        installed: true,
                        status: "installed",
                        location: "helper-skill"
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
