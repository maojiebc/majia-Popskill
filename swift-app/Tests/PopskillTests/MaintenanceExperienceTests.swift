import XCTest
@testable import Popskill

final class MaintenanceExperienceTests: XCTestCase {
    func testAgentCatalogRecognizesMainstreamNpmAgents() {
        let gemini = GlobalCli(name: "@google/gemini-cli", installed: "1.0.0")
        let qwen = GlobalCli(name: "@qwen-code/qwen-code", installed: "1.0.0")
        let opencode = GlobalCli(name: "opencode", installed: "1.0.0")

        XCTAssertEqual(gemini.agentDefinition?.displayName, "Gemini CLI")
        XCTAssertEqual(qwen.agentDefinition?.displayName, "Qwen Code")
        XCTAssertEqual(opencode.agentDefinition?.displayName, "OpenCode")
        XCTAssertTrue(gemini.looksLikeAgent)
    }

    func testUnknownAgentIsVisibleButNotBulkUpgradeSafe() {
        let cli = GlobalCli(
            name: "future-agent-cli",
            installed: "1.0.0",
            latest: "1.1.0",
            allowlisted: false
        )

        XCTAssertTrue(cli.looksLikeAgent)
        XCTAssertNil(cli.agentDefinition)
        XCTAssertFalse(cli.safeRecognizedAgentUpdate,
                       "关键词猜中的未知包只能逐行确认，不能混进批量升级")
    }

    func testRecognizedAgentUpdateIsBulkSafe() {
        let cli = GlobalCli(
            name: "aider-chat",
            installed: "0.80.0",
            latest: "0.81.0",
            channel: .pipx,
            allowlisted: true
        )

        XCTAssertEqual(cli.agentDefinition?.displayName, "Aider")
        XCTAssertTrue(cli.safeRecognizedAgentUpdate)
    }

    func testBulkAutomaticUpdateOnlyAcceptsRemoteManagedSources() {
        XCTAssertTrue(supportsBulkAutomaticUpdate(
            sourceUrl: "github.com/anthropics/skills", managedExternally: false))
        XCTAssertTrue(supportsBulkAutomaticUpdate(
            sourceUrl: "npm:@google/gemini-cli", managedExternally: false))
        XCTAssertTrue(supportsBulkAutomaticUpdate(
            sourceUrl: "https://example.com/.well-known/skills/demo/SKILL.md", managedExternally: false))
        XCTAssertFalse(supportsBulkAutomaticUpdate(
            sourceUrl: "~/work/my-skill", managedExternally: false))
        XCTAssertFalse(supportsBulkAutomaticUpdate(
            sourceUrl: "github.com/a/b", managedExternally: true))
        XCTAssertFalse(supportsBulkAutomaticUpdate(sourceUrl: nil, managedExternally: false))
    }

    func testSkillInsightExtractsSummaryUseCasesAndCapabilities() {
        let markdown = """
        ---
        name: campaign-review
        description: Campaign review assistant
        ---

        # Campaign Review

        Helps operators review a campaign before launch and find missing evidence.

        ## When to use
        - Before submitting a national campaign for approval
        - When a regional plan lacks measurable success criteria

        ## Capabilities
        - Checks goals, audience, budget and rollback conditions
        - Produces a concise review memo
        - Flags assumptions that still need real data
        """

        let insight = SkillInsight.parse(
            markdown: markdown,
            name: "campaign-review",
            fallbackDescription: ""
        )

        XCTAssertEqual(insight.summary,
                       "Helps operators review a campaign before launch and find missing evidence.")
        XCTAssertEqual(insight.useCases.count, 2)
        XCTAssertEqual(insight.capabilities.count, 3)
        XCTAssertTrue(insight.useCases[0].contains("Before submitting"))
        XCTAssertTrue(insight.capabilities[0].contains("Checks goals"))
    }

    func testSkillInsightUnderstandsChineseSectionNames() {
        let markdown = """
        # 门店复盘

        帮助区域运营把散乱数据整理成可执行复盘。

        ## 适用场景
        - 周会前快速找到异常门店
        - 活动结束后核对目标与结果

        ## 核心能力
        1. 汇总关键指标
        2. 标出缺失证据
        """

        let insight = SkillInsight.parse(
            markdown: markdown,
            name: "门店复盘",
            fallbackDescription: "暂无描述"
        )

        XCTAssertEqual(insight.summary, "帮助区域运营把散乱数据整理成可执行复盘。")
        XCTAssertEqual(insight.useCases, ["周会前快速找到异常门店", "活动结束后核对目标与结果"])
        XCTAssertEqual(insight.capabilities, ["汇总关键指标", "标出缺失证据"])
    }

    func testUsefulCatalogDescriptionWinsOverDocumentOpening() {
        let insight = SkillInsight.parse(
            markdown: "# Demo\n\nThis is the document opening.",
            name: "demo",
            fallbackDescription: "面向真实业务的精选中文说明"
        )
        XCTAssertEqual(insight.summary, "面向真实业务的精选中文说明")
    }
}
