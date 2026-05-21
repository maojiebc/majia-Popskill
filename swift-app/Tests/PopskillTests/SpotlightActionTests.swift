@testable import Popskill
import Foundation
import Testing

struct SpotlightActionTests {
    @Test
    func spotlightActionsExposeUsageScan() {
        #expect(SpotlightAction.all.map(\.id).contains("usage-scan"))
        #expect(SpotlightAction.all.map(\.id).contains("show-bundles"))
        #expect(SpotlightAction.all.map(\.id).contains("show-skills"))
        #expect(SpotlightAction.all.map(\.id).contains("show-cli"))
        #expect(SpotlightAction.all.map(\.id).contains("show-mcp"))
        #expect(SpotlightAction.all.map(\.id).contains("show-broken-links"))
        #expect(SpotlightAction.all.map(\.id).contains("show-inactive"))

        let usageScan = SpotlightAction.all.first { $0.id == "usage-scan" }
        #expect(usageScan?.titleKey == "spotlight.action.usageScan.title")
        #expect(usageScan?.subtitleKey == "spotlight.action.usageScan.subtitle")
    }

    @Test
    func spotlightRecentRankerPrefersUsageOverLifecycleForSkills() {
        let lifecycleNewer = skillFixture(id: "newer-install", name: "Newer Install", installedAt: 1_900_000_000)
        let recentlyUsed = skillFixture(id: "recently-used", name: "Recently Used", installedAt: 1_600_000_000)
        let highCalls = skillFixture(id: "high-calls", name: "High Calls", installedAt: 1_500_000_000)
        let summary = UsageSummary(
            skillStats: [
                usageStat(skillID: "recently-used", calls: 1, tokens: 10, lastUsedAt: 1_800_000_000),
                usageStat(skillID: "high-calls", calls: 20, tokens: 200, lastUsedAt: 1_700_000_000)
            ]
        )

        let ranked = SpotlightRecentRanker.recentSkills(
            [lifecycleNewer, highCalls, recentlyUsed],
            summary: summary
        )

        #expect(ranked.map(\.id) == ["recently-used", "high-calls", "newer-install"])
    }

    @Test
    func spotlightRecentRankerFallsBackToLifecycleWhenUsageIsMissing() {
        let older = skillFixture(id: "older", name: "Older", installedAt: 100)
        let newer = skillFixture(id: "newer", name: "Newer", updatedAt: 200)

        let ranked = SpotlightRecentRanker.recentSkills([older, newer], summary: nil)

        #expect(ranked.map(\.id) == ["newer", "older"])
    }

    @Test
    func spotlightRecentRankerRanksPackagesByComponentUsage() {
        let usedPackage = packageFixture(
            id: "pkg-used",
            name: "Used Package",
            componentID: "used-skill",
            lifecycleUpdatedAt: 100
        )
        let lifecycleNewer = packageFixture(
            id: "pkg-newer",
            name: "Lifecycle Newer",
            componentID: "unused-skill",
            lifecycleUpdatedAt: 1_900_000_000
        )
        let usedSkill = skillFixture(id: "used-skill", name: "Used Skill")
        let summary = UsageSummary(
            skillStats: [
                usageStat(skillID: "used-skill", calls: 2, tokens: 20, lastUsedAt: 1_800_000_000)
            ]
        )

        let ranked = SpotlightRecentRanker.recentPackages(
            [lifecycleNewer, usedPackage],
            skills: [usedSkill],
            summary: summary
        )

        #expect(ranked.map(\.id) == ["pkg-used", "pkg-newer"])
    }

    @MainActor
    @Test
    func spotlightMatrixFilterActionsOpenExpectedMatrixViews() {
        let store = PopskillStore()

        store.searchText = "baoyu"
        SpotlightAction.all.first { $0.id == "show-bundles" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixTypeFilter == .bundle)
        #expect(store.matrixFilter == .all)
        #expect(store.searchText.isEmpty)

        SpotlightAction.all.first { $0.id == "show-skills" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixTypeFilter == .skill)
        #expect(store.matrixFilter == .all)

        SpotlightAction.all.first { $0.id == "show-cli" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixTypeFilter == .cli)
        #expect(store.matrixFilter == .all)

        SpotlightAction.all.first { $0.id == "show-mcp" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixTypeFilter == .mcp)
        #expect(store.matrixFilter == .all)

        SpotlightAction.all.first { $0.id == "show-broken-links" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixFilter == .brokenLinks)
        #expect(store.matrixTypeFilter == .allTypes)

        SpotlightAction.all.first { $0.id == "show-inactive" }?.run(store: store)
        #expect(store.currentSelection == .matrix)
        #expect(store.matrixFilter == .inactive)
        #expect(store.matrixTypeFilter == .allTypes)
    }

    private func skillFixture(
        id: String,
        name: String,
        installedAt: Int? = nil,
        updatedAt: Int? = nil
    ) -> Skill {
        Skill(
            id: id,
            name: name,
            description: "\(name) description",
            directory: id,
            repoOwner: nil,
            repoName: nil,
            readmeUrl: nil,
            apps: SkillApps(claude: true, codex: true, gemini: false, opencode: false, hermes: false),
            installedAt: installedAt,
            updatedAt: updatedAt,
            contentHash: nil
        )
    }

    private func packageFixture(
        id: String,
        name: String,
        componentID: String,
        lifecycleUpdatedAt: Int
    ) -> CapabilityPackage {
        CapabilityPackage(
            id: id,
            type: .composite,
            name: name,
            vendor: nil,
            summary: "\(name) summary",
            source: PackageSource(
                kind: "builtin",
                location: id,
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
                        id: componentID,
                        name: componentID,
                        kind: "skill",
                        required: true,
                        installed: true,
                        status: "installed",
                        location: componentID
                    )
                ],
                mcp: [],
                agents: []
            ),
            configSchema: [],
            installed: true,
            lifecycle: PackageLifecycle(
                installedAt: nil,
                updatedAt: lifecycleUpdatedAt,
                contentHash: nil
            )
        )
    }

    private func usageStat(
        skillID: String,
        calls: Int,
        tokens: Int64,
        lastUsedAt: TimeInterval
    ) -> SkillUsageStat {
        SkillUsageStat(
            skillID: skillID,
            sourcePlugin: nil,
            usageEvents: calls,
            inputTokens: tokens,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            lastUsedAt: Date(timeIntervalSince1970: lastUsedAt)
        )
    }
}
