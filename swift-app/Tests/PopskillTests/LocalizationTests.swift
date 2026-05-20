@testable import Popskill
import Testing

struct LocalizationTests {
    @Test
    func localizationLoadsBundledChineseStrings() {
        let localization = PopskillLocalization(language: .simplifiedChinese)

        #expect(localization.string("Settings") == "设置")
        #expect(localization.string("Capability Packages") == "能力包")
        #expect(localization.string("Asset Model") == "资产模型")
    }

    @Test
    func localizationFallsBackToEnglish() {
        let localization = PopskillLocalization(language: .simplifiedChinese)

        #expect(localization.string("__missing_key__") == "__missing_key__")
        #expect(PopskillLocalization(language: .english).string("Settings") == "Settings")
    }

    @Test
    func localizationFormatsCountStrings() {
        let localization = PopskillLocalization(language: .simplifiedChinese)

        #expect(localization.string("library.summary", 2, 61, 24) == "2 个能力包 · 61 个 Skill · 24 个已启用")
    }

    @Test
    func inspectorTabLabelsAreLocalized() {
        let localization = PopskillLocalization(language: .simplifiedChinese)

        #expect(localization.string("matrix.inspector.tab.overview") == "概览")
        #expect(localization.string("matrix.inspector.tab.usage") == "用量")
        #expect(localization.string("matrix.inspector.tab.paths") == "路径")
        #expect(localization.string("matrix.inspector.tab.sync") == "同步")
        #expect(localization.string("matrix.inspector.header.calls", "412") == "412 次调用")
    }

    @Test
    func inspectorSkillActionLabelsAreLocalized() {
        let localization = PopskillLocalization(language: .simplifiedChinese)

        #expect(localization.string("matrix.skill.action.openReadme") == "编辑 prompt")
        #expect(localization.string("matrix.skill.action.checkUpdates") == "检查更新")
        #expect(localization.string("matrix.skill.action.openSource") == "打开来源")
        #expect(localization.string("matrix.skill.action.revealInFinder") == "在 Finder 中显示")
        #expect(localization.string("matrix.package.action.activateClaude") == "全部激活到 Claude")
        #expect(localization.string("matrix.package.activation.remaining", 2, 1) == "Claude 还差 2 个 · Codex 还差 1 个")
        #expect(localization.string("matrix.inspector.section.machine") == "这台机器")
        #expect(localization.string("matrix.machine.firstActivated") == "首次激活")
        #expect(localization.string("matrix.machine.tokens") == "近30天 tokens")
        #expect(localization.string("matrix.inspector.section.source") == "来源与路径")
        #expect(localization.string("matrix.source.repository") == "仓库")
        #expect(localization.string("matrix.source.localStore") == "本地真身")
    }
}
