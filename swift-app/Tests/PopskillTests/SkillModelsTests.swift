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
    func matrixCapabilityIDsPreserveScopedSkillIdentifiers() {
        let skill = Skill(
            id: "owner/repo:demo-skill",
            name: "Demo",
            description: "Demo skill",
            directory: "demo-skill",
            repoOwner: "owner",
            repoName: "repo",
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

        let capability = MatrixCapability.fromSkill(skill)

        #expect(capability.id == "skill:owner/repo:demo-skill")
        #expect(MatrixCapability.skillToggleKey(for: skill.id, app: .codex) == "skill:owner/repo:demo-skill|codex")
    }

    @Test
    func enabledAppCountCountsAllTargetApps() {
        var skill = installedSkill(directory: "demo-skill")

        skill.apps.codex = true
        skill.apps.hermes = true

        #expect(skill.enabledAppCount == 3)
    }

    @Test
    func skillBrokenLinkDetectionUsesDeploymentStatuses() {
        var skill = installedSkill(directory: "demo-skill")

        #expect(skill.hasBrokenLink == false)

        skill.deployment = SkillDeployment(
            strategy: "symlink",
            ssotPath: "/Users/example/.cc-switch/skills/demo-skill",
            appLinks: [
                "claude": AppLinkStatus(path: "/Users/example/.claude/skills/demo-skill", status: "ok"),
                "codex": AppLinkStatus(path: "/Users/example/.codex/skills/demo-skill", status: "BROKEN")
            ]
        )

        #expect(skill.deployment?.hasBrokenLink == true)
        #expect(skill.hasBrokenLink == true)
    }

    @Test
    func capabilityPackageBrokenLinksAggregateMatchedSkills() {
        let package = self.package(components: [component(id: "demo-skill", installed: true)])
        let unrelatedPackage = self.package(components: [component(id: "healthy-skill", installed: true)])
        var skill = installedSkill(directory: "demo-skill")

        skill.deployment = SkillDeployment(
            strategy: "symlink",
            ssotPath: "/Users/example/.cc-switch/skills/demo-skill",
            appLinks: [
                "claude": AppLinkStatus(path: "/Users/example/.claude/skills/demo-skill", status: "broken")
            ]
        )

        #expect(package.hasBrokenLinks(in: [skill]) == true)
        #expect(unrelatedPackage.hasBrokenLinks(in: [skill]) == false)
    }

    @Test
    func matrixCapabilityBrokenLinksAggregateDirectAndPackageLinks() {
        let package = self.package(components: [component(id: "demo-skill", installed: true)])
        let unrelatedPackage = self.package(components: [component(id: "healthy-skill", installed: true)])
        var skill = installedSkill(directory: "demo-skill")

        skill.deployment = SkillDeployment(
            strategy: "symlink",
            ssotPath: "/Users/example/.cc-switch/skills/demo-skill",
            appLinks: [
                "codex": AppLinkStatus(path: "/Users/example/.codex/skills/demo-skill", status: "broken")
            ]
        )

        #expect(MatrixCapability.fromSkill(skill).hasBrokenLinks(in: []) == true)
        #expect(MatrixCapability.fromPackage(package, skills: [skill]).hasBrokenLinks(in: [skill]) == true)
        #expect(MatrixCapability.fromPackage(unrelatedPackage, skills: [skill]).hasBrokenLinks(in: [skill]) == false)
    }

    @Test
    func matrixCapabilitySearchMatchesSourceTriggersAndAppTargets() {
        var skill = Skill(
            id: "dotey/prompt-engineering:baoyu-comic",
            name: "baoyu-comic",
            description: "Comic generator",
            directory: "baoyu-comic",
            repoOwner: "dotey",
            repoName: "prompt-engineering",
            readmeUrl: nil,
            apps: SkillApps(claude: false, codex: true, gemini: false, opencode: false, hermes: false),
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil
        )
        skill.capabilitySummary = "Turns topics into four-panel comics."
        skill.triggerScenarios = ["用 baoyu-comic 把 X 画成四格"]
        skill.sourceType = "github"
        let capability = MatrixCapability.fromSkill(skill)

        #expect(capability.matchesSearch(query: SearchTextNormalizer.key("dotey")))
        #expect(capability.matchesSearch(query: SearchTextNormalizer.key("prompt engineering")))
        #expect(capability.matchesSearch(query: SearchTextNormalizer.key("四格")))
        #expect(capability.matchesSearch(query: SearchTextNormalizer.key("codex")))
        #expect(!capability.matchesSearch(query: SearchTextNormalizer.key("feishu")))
    }

    @Test
    func matrixCapabilitySearchMatchesPackageSourceComponentsAndConfig() {
        let package = CapabilityPackage(
            id: "pkg:feishu-suite",
            type: .composite,
            name: "Feishu Suite",
            vendor: "ByteDance",
            summary: "Office automation suite",
            source: PackageSource(
                kind: "github",
                location: "github.com/feishu/lark-suite",
                updateStrategy: "manual",
                repoOwner: "feishu",
                repoName: "lark-suite",
                repoBranch: "main",
                readmeUrl: nil
            ),
            components: PackageComponents(
                cli: [
                    PackageComponent(id: "lark-cli", name: "lark-cli", kind: "cli", required: true, installed: false, status: "stub", location: "feishu-suite/lark-cli")
                ],
                skills: [],
                mcp: [
                    PackageComponent(id: "lark-openapi-mcp", name: "Lark OpenAPI MCP", kind: "mcp", required: false, installed: false, status: "registry-reference", location: nil)
                ],
                agents: []
            ),
            configSchema: [
                PackageConfigField(id: "lark.app_secret", label: "App Secret", required: true, secret: true, storage: "keychain")
            ],
            installed: false,
            lifecycle: nil
        )
        let capability = MatrixCapability.fromPackage(package, skills: [])

        #expect(capability.matchesSearch(query: SearchTextNormalizer.key("bytedance")))
        #expect(capability.matchesSearch(query: SearchTextNormalizer.key("lark suite")))
        #expect(capability.matchesSearch(query: SearchTextNormalizer.key("套装")))
        #expect(capability.matchesSearch(query: SearchTextNormalizer.key("占位")))
        #expect(capability.matchesSearch(query: SearchTextNormalizer.key("keychain")))
        #expect(!capability.matchesSearch(query: SearchTextNormalizer.key("baoyu comic")))
    }

    @Test
    func targetAppRegistryCoversCurrentSkillTargets() {
        #expect(TargetAppRegistry.all.map(\.app) == TargetApp.supported)
        #expect(TargetApp.quickToggleSupported == [.claude, .codex, .gemini])
        #expect(TargetApp.codex.title == "Codex")
        #expect(TargetApp.codex.symbolName == "chevron.left.forwardslash.chevron.right")
        #expect(TargetApp.codex.definition.skillDirectory == ".codex/skills")
        #expect(TargetApp.hermes.definition.quickToggle == false)
        #expect(TargetApp.opencode.definition.detectPath == ".config/opencode")
    }

    @Test
    func idleCandidateRequiresInactiveAndStaleLifecycle() {
        let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)
        let staleTimestamp = Int(referenceDate.addingTimeInterval(-61 * 24 * 60 * 60).timeIntervalSince1970)
        let recentTimestamp = Int(referenceDate.addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970)
        let disabledApps = SkillApps(
            claude: false,
            codex: false,
            gemini: false,
            opencode: false,
            hermes: false
        )

        let active = installedSkill(directory: "active", installedAt: staleTimestamp)
        let staleInactive = installedSkill(directory: "stale", installedAt: staleTimestamp, apps: disabledApps)
        let recentInactive = installedSkill(directory: "recent", installedAt: recentTimestamp, apps: disabledApps)
        let recentlyUpdated = installedSkill(
            directory: "updated",
            installedAt: staleTimestamp,
            updatedAt: recentTimestamp,
            apps: disabledApps
        )
        let unknownInactive = installedSkill(directory: "unknown", apps: disabledApps)

        #expect(active.isIdleCandidate(referenceDate: referenceDate) == false)
        #expect(staleInactive.isIdleCandidate(referenceDate: referenceDate) == true)
        #expect(recentInactive.isIdleCandidate(referenceDate: referenceDate) == false)
        #expect(recentlyUpdated.isIdleCandidate(referenceDate: referenceDate) == false)
        #expect(unknownInactive.isIdleCandidate(referenceDate: referenceDate) == true)
    }

    @Test
    func installedSkillMatchesTranscriptAttributionIdentifiers() {
        let skill = Skill(
            id: "jimliu/baoyu-skills:baoyu-image-gen",
            name: "baoyu-image-gen",
            description: "Image generation",
            directory: "baoyu-image-gen",
            repoOwner: "jimliu",
            repoName: "baoyu-skills",
            readmeUrl: nil,
            apps: SkillApps(
                claude: false,
                codex: true,
                gemini: false,
                opencode: false,
                hermes: false
            ),
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil
        )

        #expect(skill.matchesAttributionSkill("jimliu/baoyu-skills:baoyu-image-gen"))
        #expect(skill.matchesAttributionSkill("baoyu-image-gen"))
        #expect(skill.matchesAttributionSkill("BAOYU-IMAGE-GEN"))
        #expect(skill.matchesAttributionSkill("other-plugin:baoyu-image-gen"))
        #expect(!skill.matchesAttributionSkill("baoyu-cover-image"))
    }

    @Test
    func installedSkillUsageSnapshotAggregatesAttributionStats() {
        let skill = installedSkill(directory: "baoyu-comic")
        let lastUsed = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = UsageSummary(
            filesScanned: 2,
            sessions: 2,
            usageEvents: 3,
            inputTokens: 100,
            outputTokens: 80,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            attributedSkillUsageEvents: 2,
            modelStats: [],
            skillStats: [
                SkillUsageStat(
                    skillID: "baoyu-comic",
                    sourcePlugin: nil,
                    usageEvents: 2,
                    inputTokens: 20,
                    outputTokens: 30,
                    cacheCreationTokens: 5,
                    cacheReadTokens: 7,
                    lastUsedAt: lastUsed
                ),
                SkillUsageStat(
                    skillID: "jimliu/baoyu-skills:baoyu-comic",
                    sourcePlugin: nil,
                    usageEvents: 1,
                    inputTokens: 10,
                    outputTokens: 12,
                    cacheCreationTokens: 0,
                    cacheReadTokens: 0,
                    lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000)
                ),
                SkillUsageStat(
                    skillID: "unrelated",
                    sourcePlugin: nil,
                    usageEvents: 9,
                    inputTokens: 999,
                    outputTokens: 999,
                    cacheCreationTokens: 999,
                    cacheReadTokens: 999,
                    lastUsedAt: nil
                )
            ],
            recentSessions: []
        )

        let snapshot = skill.usageSnapshot(using: summary)

        #expect(snapshot?.usageEvents == 3)
        #expect(snapshot?.totalTokens == 84)
        #expect(snapshot?.lastUsedAt == lastUsed)
    }

    @Test
    func installedSkillUsageSnapshotPrefersRecentThirtyDayWindow() {
        let skill = installedSkill(directory: "baoyu-comic")
        let oldStat = SkillUsageStat(
            skillID: "baoyu-comic",
            sourcePlugin: nil,
            usageEvents: 9,
            inputTokens: 90,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let recentDay = Date(timeIntervalSince1970: 1_799_971_200)
        var recentStat = SkillUsageStat(
            skillID: "baoyu-comic",
            sourcePlugin: nil,
            usageEvents: 2,
            inputTokens: 4,
            outputTokens: 6,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        recentStat.dailyStats = [
            UsageBucketStat(
                dayStart: recentDay,
                usageEvents: 2,
                inputTokens: 4,
                outputTokens: 6,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            )
        ]
        var recentWindow = UsageWindowSummary(
            days: 30,
            startedAt: Date(timeIntervalSince1970: 1_799_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        recentWindow.usageEvents = 2
        recentWindow.inputTokens = 4
        recentWindow.outputTokens = 6
        recentWindow.attributedSkillUsageEvents = 2
        recentWindow.skillStats = [recentStat]
        let summary = UsageSummary(
            usageEvents: 11,
            inputTokens: 94,
            outputTokens: 6,
            attributedSkillUsageEvents: 11,
            skillStats: [oldStat],
            recent30Days: recentWindow
        )

        let snapshot = skill.usageSnapshot(using: summary)

        #expect(snapshot?.usageEvents == 2)
        #expect(snapshot?.totalTokens == 10)
        #expect(snapshot?.lastUsedAt == recentStat.lastUsedAt)
        #expect(snapshot?.dailyStats.map(\.dayStart) == [recentDay])
        #expect(snapshot?.dailyStats.first?.usageEvents == 2)
    }

    @Test
    func installPlanDecodesPreviewPayload() throws {
        let data = """
        {
          "skillKey": "owner/repo:demo",
          "name": "Demo",
          "description": "Demo skill",
          "targetApp": "codex",
          "installDirectory": "demo",
          "source": {
            "repoOwner": "owner",
            "repoName": "repo",
            "repoBranch": "main",
            "readmeUrl": "https://example.com/readme"
          },
          "existingSkillId": null,
          "writes": {
            "ssotPath": "/Users/demo/.cc-switch/skills/demo",
            "appSkillPath": "/Users/demo/.codex/skills/demo"
          },
          "securityGate": "agentShieldPostInstallRollback",
          "steps": ["downloadFromRepository", "runAgentShield"]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let plan = try decoder.decode(InstallPlan.self, from: data)

        #expect(plan.skillKey == "owner/repo:demo")
        #expect(plan.source.repoOwner == "owner")
        #expect(plan.writes.appSkillPath?.hasSuffix("/.codex/skills/demo") == true)
        #expect(plan.securityGate == "agentShieldPostInstallRollback")
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

    @Test
    func webDAVSyncPlanDecodesBoundaryPayload() throws {
        let data = """
        {
          "available": false,
          "readiness": "blocked-by-cc-switch-boundary",
          "summary": "Remote snapshot lookup is available, but manual upload/download is not exposed from the sidecar yet.",
          "blockedBy": ["Tauri State boundary"],
          "safeActions": ["webdav-status --json"],
          "requiresSubmoduleApi": true
        }
        """.data(using: .utf8)!

        let plan = try JSONDecoder().decode(WebDAVSyncPlan.self, from: data)

        #expect(plan.available == false)
        #expect(plan.readiness == "blocked-by-cc-switch-boundary")
        #expect(plan.requiresSubmoduleApi == true)
    }

    @Test
    func localAgentDecodesFrontmatterDerivedPayload() throws {
        let data = """
        {
          "id": "engineering/backend-architect",
          "name": "Backend Architect",
          "description": "Designs service boundaries and migration plans.",
          "fileName": "backend-architect.md",
          "path": "/Users/example/.claude/agents/engineering/backend-architect.md",
          "category": "engineering",
          "tools": ["Read", "Write", "Bash"],
          "model": "sonnet",
          "lastModifiedAt": 1778603190,
          "sizeBytes": 2048
        }
        """.data(using: .utf8)!

        let agent = try JSONDecoder().decode(LocalAgent.self, from: data)

        #expect(agent.id == "engineering/backend-architect")
        #expect(agent.categoryLabel == "engineering")
        #expect(agent.toolSummary == "Read, Write, Bash")
        #expect(agent.fileURL.path == "/Users/example/.claude/agents/engineering/backend-architect.md")
    }

    @Test
    func agentTargetDecodesAgencyAgentsToolMatrixPayload() throws {
        let data = """
        {
          "id": "kimi",
          "name": "Kimi Code",
          "scope": "user",
          "format": "agent-yaml",
          "paths": ["/Users/example/.config/kimi/agents"],
          "detected": true,
          "source": "agency-agents",
          "note": "AgencyAgents emits agent.yaml plus system.md per agent."
        }
        """.data(using: .utf8)!

        let target = try JSONDecoder().decode(AgentTarget.self, from: data)

        #expect(target.id == "kimi")
        #expect(target.primaryPath == "/Users/example/.config/kimi/agents")
        #expect(target.statusLabel == "Detected")
        #expect(target.pathSummary == "/Users/example/.config/kimi/agents")
        #expect(target.symbolName == "k.circle")
        #expect(target.definition.displayName == "Kimi Code")
        #expect(target.isRegistryTarget == true)
        #expect(target.isImportedTarget == false)
        #expect(target.source == "agency-agents")
    }

    @Test
    func agentTargetMissingStateUsesAppStoreStyleStatus() {
        let target = AgentTarget(
            id: "qwen",
            name: "Qwen Code",
            scope: "user/project",
            format: "markdown-agent",
            paths: ["/Users/example/.qwen/agents", "/Users/example/project/.qwen/agents"],
            detected: false,
            source: "agency-agents",
            note: nil
        )

        #expect(target.statusLabel == "Missing")
        #expect(target.pathSummary == "/Users/example/.qwen/agents\n/Users/example/project/.qwen/agents")
        #expect(target.symbolName == "q.circle")
    }

    @Test
    func targetAgentRegistryCoversAgencyAgentsMatrix() {
        #expect(TargetAgentRegistry.all.count == 11)
        #expect(TargetAgentRegistry.all.map(\.targetID) == [
            "claude-code",
            "copilot",
            "antigravity",
            "gemini-cli",
            "opencode",
            "openclaw",
            "cursor",
            "aider",
            "windsurf",
            "qwen",
            "kimi"
        ])
        #expect(TargetAgentRegistry.definition(for: "claude-code", fallbackName: "Claude").linkedApp == .claude)
        #expect(TargetAgentRegistry.definition(for: "opencode", fallbackName: "OpenCode").linkedApp == .opencode)
        #expect(TargetAgentRegistry.definition(for: "claude-code", fallbackName: "Claude").detectPaths == [".claude", ".claude/agents"])
        #expect(TargetAgentRegistry.definition(for: "gemini-cli", fallbackName: "Gemini CLI").cliCommands == ["gemini"])
    }

    @Test
    func agentTargetExposesRegistryDiagnostics() {
        let target = AgentTarget(
            id: "claude-code",
            name: "Claude Code",
            scope: "user",
            format: "markdown-agent",
            paths: ["/Users/example/.claude/agents"],
            detected: false,
            source: "agency-agents",
            note: nil
        )

        #expect(target.expectedPathSummary == ".claude, .claude/agents")
        #expect(target.cliCommandSummary == "claude")
        #expect(target.appBundleSummary == nil)
    }

    @Test
    func importedAgentTargetClassificationAndRegistrySorting() {
        let imported = AgentTarget(
            id: "custom-workbench",
            name: "Custom Workbench",
            scope: "project",
            format: "markdown-agent",
            paths: ["/Users/example/project/.custom/agents"],
            detected: true,
            source: "manual-import",
            note: nil
        )
        let knownMissing = AgentTarget(
            id: "claude-code",
            name: "Claude Code",
            scope: "user",
            format: "markdown-agent",
            paths: ["/Users/example/.claude/agents"],
            detected: false,
            source: "agency-agents",
            note: nil
        )

        let sorted = TargetAgentRegistry.sort([imported, knownMissing])

        #expect(imported.isImportedTarget == true)
        #expect(imported.isRegistryTarget == false)
        #expect(imported.linkedApp == nil)
        #expect(sorted.map(\.id) == ["claude-code", "custom-workbench"])
    }


    @Test
    func catalogAgentDecodesAgencyAgentsCatalogPayload() throws {
        let data = """
        {
          "id": "msitarzewski/agency-agents:marketing/xiaohongshu-specialist",
          "name": "xiaohongshu-specialist",
          "description": "Builds Xiaohongshu content plans.",
          "path": "marketing/xiaohongshu-specialist.md",
          "category": "marketing",
          "repoOwner": "msitarzewski",
          "repoName": "agency-agents",
          "repoBranch": "main",
          "readmeUrl": "https://github.com/msitarzewski/agency-agents/blob/main/marketing/xiaohongshu-specialist.md",
          "rawUrl": "https://raw.githubusercontent.com/msitarzewski/agency-agents/main/marketing/xiaohongshu-specialist.md",
          "tools": ["Read", "Write"],
          "model": "sonnet",
          "source": "agency-agents"
        }
        """.data(using: .utf8)!

        let agent = try JSONDecoder().decode(CatalogAgent.self, from: data)

        #expect(agent.category == "marketing")
        #expect(agent.repoName == "agency-agents")
        #expect(agent.tools == ["Read", "Write"])
        #expect(agent.source == "agency-agents")
    }

    @Test
    func agentInstallPlanDecodesPreviewPayload() throws {
        let data = """
        {
          "agentId": "msitarzewski/agency-agents:marketing/xiaohongshu-specialist",
          "name": "Xiaohongshu Specialist",
          "targetId": "claude-code",
          "targetName": "Claude Code",
          "targetFormat": "markdown-agent",
          "source": {
            "repoOwner": "msitarzewski",
            "repoName": "agency-agents",
            "repoBranch": "main",
            "path": "marketing/xiaohongshu-specialist.md",
            "rawUrl": "https://raw.githubusercontent.com/msitarzewski/agency-agents/main/marketing/xiaohongshu-specialist.md"
          },
          "writes": ["/Users/example/.claude/agents/xiaohongshu-specialist.md"],
          "conflict": null,
          "requiresConversion": false,
          "steps": ["fetchFromAgencyAgents", "writeAgentFile"]
        }
        """.data(using: .utf8)!

        let plan = try JSONDecoder().decode(AgentInstallPlan.self, from: data)

        #expect(plan.agentId == "msitarzewski/agency-agents:marketing/xiaohongshu-specialist")
        #expect(plan.targetId == "claude-code")
        #expect(plan.source.repoName == "agency-agents")
        #expect(plan.writes == ["/Users/example/.claude/agents/xiaohongshu-specialist.md"])
        #expect(plan.requiresConversion == false)
    }

    @Test
    func capabilityPackageDecodesCompositePayload() throws {
        let data = """
        {
          "id": "pkg:lark",
          "type": "composite",
          "name": "Feishu / Lark",
          "vendor": "ByteDance",
          "summary": "Composite office package.",
          "source": {
            "kind": "builtin",
            "location": "popskill/builtin/lark",
            "updateStrategy": "manual"
          },
          "components": {
            "cli": [
              {
                "id": "lark-cli",
                "name": "lark-cli",
                "kind": "cli",
                "required": true,
                "installed": false,
                "status": "declared"
              }
            ],
            "skills": [
              {
                "id": "lark-doc",
                "name": "Lark Doc",
                "kind": "skill",
                "required": true,
                "installed": true,
                "status": "installed",
                "location": "lark-doc"
              }
            ],
            "mcp": [],
            "agents": []
          },
          "configSchema": [
            {
              "id": "lark.app_secret",
              "label": "App Secret",
              "required": true,
              "secret": true,
              "storage": "keychain"
            }
          ],
          "installed": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let package = try decoder.decode(CapabilityPackage.self, from: data)

        #expect(package.id == "pkg:lark")
        #expect(package.type == .composite)
        #expect(package.typeLabel == "Composite")
        #expect(package.componentCount == 2)
        #expect(package.installedComponentCount == 1)
        #expect(package.requiredComponentCount == 2)
        #expect(package.missingComponentCount == 1)
        #expect(package.missingRequiredComponentCount == 1)
        #expect(package.health == .blocked)
        #expect(package.configSchema.first?.storage == "keychain")
        #expect(package.components.all.map(\.displayKey) == ["cli:lark-cli", "skill:lark-doc"])
    }

    @Test
    func packageComponentMatchesInstalledSkillByScopedIdentifierAndLocation() {
        let component = PackageComponent(
            id: "lark-doc",
            name: "Lark Doc",
            kind: "skill",
            required: true,
            installed: true,
            status: "installed",
            location: "skills/lark-doc"
        )
        let skill = Skill(
            id: "larksuite/cli:lark-doc",
            name: "Lark Doc",
            description: "Docs skill",
            directory: "lark-doc",
            repoOwner: "larksuite",
            repoName: "cli",
            readmeUrl: nil,
            apps: SkillApps(claude: true, codex: false, gemini: false, opencode: false, hermes: false),
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil
        )

        #expect(component.matchesSkill(skill))
    }

    @Test
    func capabilityPackageCoverageUsesSkillTogglesAndComponentFallbacks() {
        let package = CapabilityPackage(
            id: "pkg:lark",
            type: .composite,
            name: "Feishu / Lark",
            vendor: "ByteDance",
            summary: "Composite office package.",
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
                cli: [
                    PackageComponent(id: "lark-cli", name: "lark-cli", kind: "cli", required: true, installed: true, status: "detected", location: nil)
                ],
                skills: [
                    PackageComponent(id: "lark-doc", name: "Lark Doc", kind: "skill", required: true, installed: true, status: "installed", location: "lark-doc")
                ],
                mcp: [
                    PackageComponent(id: "lark-mcp", name: "Lark MCP", kind: "mcp", required: false, installed: false, status: "registry-reference", location: nil)
                ],
                agents: [
                    PackageComponent(id: "lark-agent", name: "Lark Agent", kind: "agent", required: false, installed: true, status: "installed", location: "~/.claude/agents/lark-agent.md")
                ]
            ),
            configSchema: [],
            installed: true,
            lifecycle: nil
        )
        let skill = Skill(
            id: "larksuite/cli:lark-doc",
            name: "Lark Doc",
            description: "Docs skill",
            directory: "lark-doc",
            repoOwner: "larksuite",
            repoName: "cli",
            readmeUrl: nil,
            apps: SkillApps(claude: true, codex: false, gemini: false, opencode: false, hermes: false),
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil
        )

        let coverage = package.appCoverage(using: [skill])
        let capability = MatrixCapability.fromPackage(package, skills: [skill])

        #expect(coverage[.claude]?.label == "3/4")
        #expect(coverage[.codex]?.label == "1/4")
        #expect(capability.id == "bundle:pkg:lark")
        #expect(capability.kind == .bundle)
        #expect(capability.apps.claude == true)
        #expect(capability.apps.codex == true)
    }

    @Test
    func packageComponentAppStateUsesInstalledSkillTogglesAndStubStatus() {
        let skill = installedSkill(
            directory: "baoyu-comic",
            apps: SkillApps(claude: true, codex: false, gemini: false, opencode: false, hermes: false)
        )
        let skillComponent = PackageComponent(
            id: "baoyu-comic",
            name: "baoyu-comic",
            kind: "skill",
            required: true,
            installed: true,
            status: "installed",
            location: "skills/baoyu-comic"
        )
        let stubbedAgent = PackageComponent(
            id: "base-analyst",
            name: "base-analyst",
            kind: "agent",
            required: false,
            installed: false,
            status: "stub",
            location: "~/.claude/agents/base-analyst.md"
        )
        let installedCLI = PackageComponent(
            id: "lark-cli",
            name: "lark-cli",
            kind: "cli",
            required: true,
            installed: true,
            status: "detected",
            location: nil
        )

        #expect(skillComponent.appState(for: .claude, matching: skill) == .active)
        #expect(skillComponent.appState(for: .codex, matching: skill) == .off)
        #expect(stubbedAgent.appState(for: .claude, matching: nil) == .stub)
        #expect(stubbedAgent.appState(for: .codex, matching: nil) == .off)
        #expect(installedCLI.appState(for: .codex, matching: nil) == .active)
        #expect(installedCLI.appState(for: .gemini, matching: nil) == .unsupported)
    }

    @Test
    func capabilityPackageUsageSnapshotAggregatesMatchedSkillStats() {
        let package = CapabilityPackage(
            id: "pkg:baoyu",
            type: .composite,
            name: "Baoyu Skills",
            vendor: "@dotey",
            summary: "Prompt package",
            source: PackageSource(
                kind: "github",
                location: "jimliu/baoyu-skills",
                updateStrategy: "git",
                repoOwner: "jimliu",
                repoName: "baoyu-skills",
                repoBranch: nil,
                readmeUrl: nil
            ),
            components: PackageComponents(
                cli: [],
                skills: [
                    PackageComponent(id: "baoyu-comic", name: "baoyu-comic", kind: "skill", required: true, installed: true, status: "installed", location: "skills/baoyu-comic"),
                    PackageComponent(id: "baoyu-translate", name: "baoyu-translate", kind: "skill", required: true, installed: true, status: "installed", location: "skills/baoyu-translate")
                ],
                mcp: [],
                agents: []
            ),
            configSchema: [],
            installed: true,
            lifecycle: nil
        )
        let comic = Skill(
            id: "jimliu/baoyu-skills:baoyu-comic",
            name: "baoyu-comic",
            description: "Comic",
            directory: "baoyu-comic",
            repoOwner: "jimliu",
            repoName: "baoyu-skills",
            readmeUrl: nil,
            apps: SkillApps(claude: true, codex: true, gemini: false, opencode: false, hermes: false),
            installedAt: nil,
            updatedAt: nil,
            contentHash: nil
        )
        let lastUsed = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = UsageSummary(
            filesScanned: 3,
            sessions: 2,
            usageEvents: 4,
            inputTokens: 100,
            outputTokens: 80,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            attributedSkillUsageEvents: 3,
            modelStats: [],
            skillStats: [
                SkillUsageStat(
                    skillID: "jimliu/baoyu-skills:baoyu-comic",
                    sourcePlugin: nil,
                    usageEvents: 2,
                    inputTokens: 20,
                    outputTokens: 30,
                    cacheCreationTokens: 5,
                    cacheReadTokens: 7,
                    lastUsedAt: lastUsed
                ),
                SkillUsageStat(
                    skillID: "other:baoyu-translate",
                    sourcePlugin: nil,
                    usageEvents: 1,
                    inputTokens: 10,
                    outputTokens: 12,
                    cacheCreationTokens: 0,
                    cacheReadTokens: 0,
                    lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000)
                ),
                SkillUsageStat(
                    skillID: "unrelated",
                    sourcePlugin: nil,
                    usageEvents: 9,
                    inputTokens: 999,
                    outputTokens: 999,
                    cacheCreationTokens: 999,
                    cacheReadTokens: 999,
                    lastUsedAt: nil
                )
            ],
            recentSessions: []
        )

        let snapshot = package.usageSnapshot(using: summary, skills: [comic])

        #expect(snapshot?.matchedSkillCount == 2)
        #expect(snapshot?.usageEvents == 3)
        #expect(snapshot?.totalTokens == 84)
        #expect(snapshot?.lastUsedAt == lastUsed)
        #expect(snapshot?.componentStats.map(\.componentID) == ["baoyu-comic", "baoyu-translate"])
        #expect(snapshot?.componentStats.first?.componentName == "baoyu-comic")
        #expect(snapshot?.componentStats.first?.usageEvents == 2)
        #expect(snapshot?.componentStats.first?.totalTokens == 62)
    }

    @Test
    func capabilityPackageUsageSnapshotPrefersRecentThirtyDayWindow() {
        let package = self.package(components: [component(id: "baoyu-comic", installed: true)])
        let skill = installedSkill(directory: "baoyu-comic")
        let oldStat = SkillUsageStat(
            skillID: "baoyu-comic",
            sourcePlugin: nil,
            usageEvents: 6,
            inputTokens: 60,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            lastUsedAt: nil
        )
        let recentDay = Date(timeIntervalSince1970: 1_799_971_200)
        var recentStat = SkillUsageStat(
            skillID: "baoyu-comic",
            sourcePlugin: nil,
            usageEvents: 1,
            inputTokens: 2,
            outputTokens: 3,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        recentStat.dailyStats = [
            UsageBucketStat(
                dayStart: recentDay,
                usageEvents: 1,
                inputTokens: 2,
                outputTokens: 3,
                cacheCreationTokens: 0,
                cacheReadTokens: 0
            )
        ]
        var recentWindow = UsageWindowSummary(
            days: 30,
            startedAt: Date(timeIntervalSince1970: 1_799_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        recentWindow.usageEvents = 1
        recentWindow.inputTokens = 2
        recentWindow.outputTokens = 3
        recentWindow.attributedSkillUsageEvents = 1
        recentWindow.skillStats = [recentStat]
        let summary = UsageSummary(
            usageEvents: 7,
            inputTokens: 62,
            outputTokens: 3,
            attributedSkillUsageEvents: 7,
            skillStats: [oldStat],
            recent30Days: recentWindow
        )

        let snapshot = package.usageSnapshot(using: summary, skills: [skill])

        #expect(snapshot?.usageEvents == 1)
        #expect(snapshot?.totalTokens == 5)
        #expect(snapshot?.componentStats.first?.componentID == "baoyu-comic")
        #expect(snapshot?.dailyStats.map(\.dayStart) == [recentDay])
        #expect(snapshot?.componentStats.first?.dailyStats.map(\.usageEvents) == [1])
    }

    @Test
    func capabilityPackageFindsContainedAndCompanionSkills() {
        let package = self.package(components: [
            component(id: "baoyu-comic", installed: true),
            component(id: "baoyu-translate", installed: true),
            component(id: "declared-only", installed: false)
        ])
        let comic = installedSkill(directory: "baoyu-comic")
        let translate = installedSkill(directory: "baoyu-translate")
        let unrelated = installedSkill(directory: "other-skill")

        #expect(package.containsSkill(comic))
        #expect(package.containsSkill(translate))
        #expect(!package.containsSkill(unrelated))
        #expect(package.companionInstalledSkills(for: comic, in: [comic, translate, unrelated]).map(\.id) == ["baoyu-translate"])
        #expect(package.installedSkillsRequiringEnablement(for: .claude, in: [comic, translate, unrelated]).isEmpty)
        #expect(package.installedSkillsRequiringEnablement(for: .codex, in: [comic, translate, unrelated]).map(\.id) == ["baoyu-comic", "baoyu-translate"])
    }

    @Test
    func matrixUsageIndexCachesSkillPackageAndComponentUsage() {
        let skill = installedSkill(directory: "baoyu-comic")
        let package = self.package(components: [
            component(id: "baoyu-comic", installed: true)
        ])
        let summary = UsageSummary(
            filesScanned: 1,
            sessions: 1,
            usageEvents: 3,
            inputTokens: 50,
            outputTokens: 30,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            attributedSkillUsageEvents: 2,
            modelStats: [],
            skillStats: [
                SkillUsageStat(
                    skillID: "baoyu-comic",
                    sourcePlugin: nil,
                    usageEvents: 2,
                    inputTokens: 20,
                    outputTokens: 10,
                    cacheCreationTokens: 0,
                    cacheReadTokens: 5,
                    lastUsedAt: nil
                ),
                SkillUsageStat(
                    skillID: "unrelated",
                    sourcePlugin: nil,
                    usageEvents: 1,
                    inputTokens: 99,
                    outputTokens: 99,
                    cacheCreationTokens: 0,
                    cacheReadTokens: 0,
                    lastUsedAt: nil
                )
            ],
            recentSessions: []
        )

        let index = MatrixUsageIndex(summary: summary, skills: [skill], packages: [package])
        let emptyIndex = MatrixUsageIndex(summary: nil, skills: [skill], packages: [package])

        #expect(index.hasSummary)
        #expect(index.skillSnapshot(for: "baoyu-comic")?.usageEvents == 2)
        #expect(index.skillSnapshot(for: "baoyu-comic")?.totalTokens == 35)
        #expect(index.packageSnapshot(for: "pkg:demo")?.usageEvents == 2)
        #expect(index.packageComponentStat(packageID: "pkg:demo", componentID: "baoyu-comic")?.totalTokens == 35)
        #expect(index.skillSnapshot(for: "missing")?.hasUsage == false)
        #expect(!emptyIndex.hasSummary)
        #expect(emptyIndex.skillSnapshot(for: "baoyu-comic") == nil)
    }

    @Test
    func usageDisplayFormatterCompactsMatrixMetrics() {
        #expect(UsageDisplayFormatter.compactTokens(999) == "999")
        #expect(UsageDisplayFormatter.compactTokens(1_500) == "1.5K")
        #expect(UsageDisplayFormatter.compactCount(2_500_000) == "2.5M")
    }

    @Test
    func capabilityPackageHealthSeparatesActivePartialBlockedAndInactive() {
        #expect(package(components: []).health == .inactive)
        #expect(package(components: [component(installed: true)]).health == .active)
        #expect(package(components: [
            component(id: "installed", installed: true),
            component(id: "optional", required: false, installed: false)
        ]).health == .partial)
        #expect(package(components: [
            component(id: "installed", installed: true),
            component(id: "required", required: true, installed: false)
        ]).health == .blocked)
    }

    @Test
    func capabilityPackageRecoverableMissingAndPrimaryKinds() {
        let package = CapabilityPackage(
            id: "pkg:mix",
            type: .composite,
            name: "Mix",
            vendor: nil,
            summary: "Mixed package",
            source: PackageSource(
                kind: "builtin",
                location: "mix",
                updateStrategy: "manual",
                repoOwner: nil,
                repoName: nil,
                repoBranch: nil,
                readmeUrl: nil
            ),
            components: PackageComponents(
                cli: [
                    PackageComponent(
                        id: "tool",
                        name: "tool",
                        kind: "cli",
                        required: true,
                        installed: false,
                        status: "declared",
                        location: nil
                    )
                ],
                skills: [
                    PackageComponent(
                        id: "skill-a",
                        name: "Skill A",
                        kind: "skill",
                        required: true,
                        installed: true,
                        status: "installed",
                        location: "skill-a"
                    )
                ],
                mcp: [],
                agents: []
            ),
            configSchema: [],
            installed: true,
            lifecycle: nil
        )

        #expect(package.recoverableMissingComponentCount == 1)
        #expect(package.primaryComponentKindsLabel == "Skill + Cli")
    }

    @Test
    func capabilityPackageComponentGroupSummariesTrackPerKindHealth() {
        let package = CapabilityPackage(
            id: "pkg:groups",
            type: .composite,
            name: "Group Demo",
            vendor: nil,
            summary: "Group summary package",
            source: PackageSource(
                kind: "builtin",
                location: "group-demo",
                updateStrategy: "manual",
                repoOwner: nil,
                repoName: nil,
                repoBranch: nil,
                readmeUrl: nil
            ),
            components: PackageComponents(
                cli: [
                    PackageComponent(
                        id: "tool-a",
                        name: "tool-a",
                        kind: "cli",
                        required: true,
                        installed: true,
                        status: "installed",
                        location: nil
                    )
                ],
                skills: [
                    PackageComponent(
                        id: "skill-a",
                        name: "Skill A",
                        kind: "skill",
                        required: true,
                        installed: true,
                        status: "installed",
                        location: "skill-a"
                    ),
                    PackageComponent(
                        id: "skill-b",
                        name: "Skill B",
                        kind: "skill",
                        required: false,
                        installed: false,
                        status: "stub",
                        location: "skill-b"
                    )
                ],
                mcp: [],
                agents: [
                    PackageComponent(
                        id: "agent-a",
                        name: "Agent A",
                        kind: "agent",
                        required: true,
                        installed: false,
                        status: "declared",
                        location: nil
                    )
                ]
            ),
            configSchema: [],
            installed: true,
            lifecycle: nil
        )

        #expect(package.componentGroupSummaries.map(\.kind) == ["skill", "cli", "agent"])
        #expect(package.componentGroupSummaries.first(where: { $0.kind == "skill" })?.installed == 1)
        #expect(package.componentGroupSummaries.first(where: { $0.kind == "skill" })?.recoverableMissing == 1)
        #expect(package.componentGroupSummaries.first(where: { $0.kind == "agent" })?.missingRequired == 1)
    }

    @Test
    func capabilityPackageLifecycleHelpersExposeLatestTimestampAndTrackedHash() {
        var package = self.package(components: [component(installed: true)])
        package = CapabilityPackage(
            id: package.id,
            type: package.type,
            name: package.name,
            vendor: package.vendor,
            summary: package.summary,
            source: package.source,
            components: package.components,
            configSchema: package.configSchema,
            installed: package.installed,
            lifecycle: PackageLifecycle(
                installedAt: 1_700_000_000,
                updatedAt: 1_700_000_120,
                contentHash: "  abcdef12  "
            )
        )

        #expect(package.lastLifecycleTimestamp == 1_700_000_120)
        #expect(package.trackedContentHash == "abcdef12")
    }

    @Test
    func capabilityPackageLifecycleHelpersHandleMissingOrBlankValues() {
        var package = self.package(components: [])
        #expect(package.lastLifecycleTimestamp == nil)
        #expect(package.trackedContentHash == nil)

        package = CapabilityPackage(
            id: package.id,
            type: package.type,
            name: package.name,
            vendor: package.vendor,
            summary: package.summary,
            source: package.source,
            components: package.components,
            configSchema: package.configSchema,
            installed: package.installed,
            lifecycle: PackageLifecycle(
                installedAt: 0,
                updatedAt: -42,
                contentHash: "   "
            )
        )

        #expect(package.lastLifecycleTimestamp == nil)
        #expect(package.trackedContentHash == nil)
    }

    @Test
    func matrixVersionFormatterPrefersHashThenUpdatedDate() {
        #expect(MatrixVersionFormatter.value(contentHash: "  abcdef123456  ", updatedAt: 1_700_000_000) == "abcdef1")
        #expect(MatrixVersionFormatter.value(contentHash: nil, updatedAt: 1_700_000_000) == "2023-11-14")
        #expect(MatrixVersionFormatter.value(contentHash: "   ", updatedAt: 0) == nil)
    }

    @Test
    func capabilityPackageMatchesScopedSkillUpdateIdentifier() {
        let package = self.package(
            components: [
                PackageComponent(
                    id: "lark-doc",
                    name: "Lark Doc",
                    kind: "skill",
                    required: true,
                    installed: true,
                    status: "installed",
                    location: "lark-doc"
                )
            ]
        )
        let update = SkillUpdateInfo(
            id: "owner/repo:lark-doc",
            name: "Lark Doc",
            currentHash: "abc12345",
            remoteHash: "def67890"
        )

        #expect(package.matchingSkillComponent(for: update)?.id == "lark-doc")
    }

    @Test
    func capabilityPackageMatchesSkillUpdateByComponentLocation() {
        let package = self.package(
            components: [
                PackageComponent(
                    id: "lark-doc",
                    name: "Lark Doc",
                    kind: "skill",
                    required: true,
                    installed: true,
                    status: "installed",
                    location: "skills/lark-doc"
                )
            ]
        )
        let update = SkillUpdateInfo(
            id: "owner/repo:skills/lark-doc",
            name: "Lark Doc",
            currentHash: nil,
            remoteHash: "def67890"
        )

        #expect(package.matchingSkillComponent(for: update)?.location == "skills/lark-doc")
    }

    @Test
    func capabilityPackageMatchesSkillUpdateByNameFallback() {
        let package = self.package(
            components: [
                PackageComponent(
                    id: "lark-doc",
                    name: "Lark Doc",
                    kind: "skill",
                    required: true,
                    installed: true,
                    status: "installed",
                    location: nil
                )
            ]
        )
        let update = SkillUpdateInfo(
            id: "owner/repo:unknown",
            name: "Lark Doc",
            currentHash: nil,
            remoteHash: "def67890"
        )

        #expect(package.matchingSkillComponent(for: update)?.id == "lark-doc")
    }

    @Test
    func capabilityPackageUpdateMatchingSkipsNonSkillComponents() {
        let package = CapabilityPackage(
            id: "pkg:cli-only",
            type: .composite,
            name: "CLI Only",
            vendor: nil,
            summary: "No skills",
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
                cli: [
                    PackageComponent(
                        id: "demo-cli",
                        name: "demo-cli",
                        kind: "cli",
                        required: true,
                        installed: true,
                        status: "installed",
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
        let update = SkillUpdateInfo(
            id: "owner/repo:demo-cli",
            name: "demo-cli",
            currentHash: "abc",
            remoteHash: "def"
        )

        #expect(package.matchingSkillComponent(for: update) == nil)
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

    private func installedSkill(
        directory: String,
        installedAt: Int? = nil,
        updatedAt: Int? = nil,
        apps: SkillApps = SkillApps(
            claude: true,
            codex: false,
            gemini: false,
            opencode: false,
            hermes: false
        )
    ) -> Skill {
        Skill(
            id: directory,
            name: "Demo",
            description: "Demo skill",
            directory: directory,
            repoOwner: nil,
            repoName: nil,
            readmeUrl: nil,
            apps: apps,
            installedAt: installedAt,
            updatedAt: updatedAt,
            contentHash: nil
        )
    }

    private func package(components: [PackageComponent]) -> CapabilityPackage {
        CapabilityPackage(
            id: "pkg:demo",
            type: .composite,
            name: "Demo",
            vendor: nil,
            summary: "Demo package",
            source: PackageSource(
                kind: "builtin",
                location: "demo",
                updateStrategy: "manual",
                repoOwner: nil,
                repoName: nil,
                repoBranch: nil,
                readmeUrl: nil
            ),
            components: PackageComponents(cli: [], skills: components, mcp: [], agents: []),
            configSchema: [],
            installed: components.contains(where: \.installed),
            lifecycle: nil
        )
    }

    private func component(
        id: String = "demo",
        required: Bool = true,
        installed: Bool
    ) -> PackageComponent {
        PackageComponent(
            id: id,
            name: id,
            kind: "skill",
            required: required,
            installed: installed,
            status: installed ? "installed" : "declared",
            location: id
        )
    }
}
