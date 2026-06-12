import Foundation

// 本地化取词（v2.12）。约定：
// - key 即中文原文——代码保持中文可读，目录 Resources/Localizable.xcstrings
//   提供 zh-Hans（=key）与 en 两份译文，系统按用户语言挑
// - 带插值的句子直接写 L("已修复 \(n) 个")，LocalizationValue 自动生成
//   "已修复 %lld 个" 形态的 key
// - 不走 L 的字符串（刻意不本地化）：os.Logger 日志、Fixtures 原型样例、
//   Catalog 精选目录的内容数据、调试 env 钩子
// 语言协商做在自己手里：裸二进制（swift build 直跑）没有 main bundle 的
// 语言声明，Foundation 会无视系统语言直接落到 en——按用户偏好在模块可用
// 语言里挑一次，之后 L() 永远从选中的 lproj 取词。.app 与裸二进制行为一致。
private let l10n: (lang: String, bundle: Bundle) = {
    let module = Bundle.module
    let prefs = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
    let pick = Bundle.preferredLocalizations(from: module.localizations, forPreferences: prefs).first
    // 协商结果 → en 兜底（不支持的系统语言一律英文），都取不到才回模块原样
    for cand in [pick, "en"].compactMap({ $0 }) {
        if let path = module.path(forResource: cand, ofType: "lproj"),
           let sub = Bundle(path: path) {
            return (cand, sub)
        }
    }
    return ("zh-Hans", module)
}()

func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: l10n.bundle)
}

/// 与界面语言一致的 Locale——相对时间等格式化跟界面语言走，不跟系统区域
/// （曾硬编码 zh_CN，英文界面会蹦出中文日期）
let l10nLocale = Locale(identifier: l10n.lang == "zh-Hans" ? "zh_CN" : l10n.lang)
