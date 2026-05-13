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
    func targetAppRegistryCoversCurrentSkillTargets() {
        #expect(TargetAppRegistry.all.map(\.app) == TargetApp.supported)
        #expect(TargetApp.codex.title == "Codex")
        #expect(TargetApp.codex.symbolName == "chevron.left.forwardslash.chevron.right")
        #expect(TargetApp.codex.definition.skillDirectory == ".codex/skills")
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
