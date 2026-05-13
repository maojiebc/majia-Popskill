@testable import Popskill
import Testing

struct LocalizationTests {
    @Test
    func localizationLoadsBundledChineseStrings() {
        let localization = PopskillLocalization(language: .simplifiedChinese)

        #expect(localization.string("Settings") == "设置")
        #expect(localization.string("Capability Packages") == "能力包")
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
}
