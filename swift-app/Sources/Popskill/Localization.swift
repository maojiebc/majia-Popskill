import Foundation

// 本地化取词（v2.12）。约定：
// - key 即中文原文——代码保持中文可读，目录 Resources/Localizable.xcstrings
//   提供 zh-Hans（=key）与 en 两份译文，系统按用户语言挑
// - 带插值的句子直接写 L("已修复 \(n) 个")，LocalizationValue 自动生成
//   "已修复 %lld 个" 形态的 key
// - 不走 L 的字符串（刻意不本地化）：os.Logger 日志、Fixtures 原型样例、
//   Catalog 精选目录的内容数据、调试 env 钩子
private final class BundleToken {}

/// 自己找资源 bundle，**不用 SPM 生成的 `Bundle.module`**：那个访问器写死去
/// `Bundle.main.bundleURL/Popskill_Popskill.bundle`（.app 顶层）找，而打包脚本把
/// 资源放在标准的 Contents/Resources/——对不上时 Bundle.module 直接 fatalError，
/// 导致打包后的 .app 一启动就崩（v2.12/2.13 实事故）。这里在多个候选位置找，
/// **找不到也绝不崩**：退回 main bundle（L() 落回中文 key），半成品也好过崩溃。
private let resourceBundle: Bundle = {
    let name = "Popskill_Popskill.bundle"
    let candidates: [URL?] = [
        Bundle.main.resourceURL,                                    // .app/Contents/Resources（打包脚本 ditto 到这）
        Bundle.main.bundleURL,                                      // .app 自身（SPM 访问器的默认猜测）
        Bundle.main.executableURL?.deletingLastPathComponent(),     // Contents/MacOS 或 .build/debug（裸二进制旁）
        Bundle(for: BundleToken.self).resourceURL,
        Bundle(for: BundleToken.self).bundleURL,
    ]
    for base in candidates.compactMap({ $0 }) {
        if let b = Bundle(url: base.appendingPathComponent(name)) { return b }
    }
    return .main
}()

/// 协商候选顺序（纯函数，可测）：用户偏好在模块可用语言里挑一个 → en 兜底。
/// **available 来自 `Bundle.localizations` = lproj 目录的磁盘真实名**，SwiftPM
/// 会把它小写成 "zh-hans"——所以返回值形态不可假设，判定一律走 l10nLangIsChinese。
func l10nLangCandidates(available: [String], prefs: [String]) -> [String] {
    let pick = Bundle.preferredLocalizations(from: available, forPreferences: prefs).first
    return [pick, "en"].compactMap { $0 }
}

// 语言协商做在自己手里：裸二进制（swift build 直跑）没有 main bundle 的
// 语言声明，Foundation 会无视系统语言直接落到 en——按用户偏好在模块可用
// 语言里挑一次，之后 L() 永远从选中的 lproj 取词。.app 与裸二进制行为一致。
private let l10n: (lang: String, bundle: Bundle) = {
    let module = resourceBundle
    let prefs = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
    for cand in l10nLangCandidates(available: module.localizations, prefs: prefs) {
        if let path = module.path(forResource: cand, ofType: "lproj"),
           let sub = Bundle(path: path) {
            return (cand, sub)
        }
    }
    // 资源 bundle 整个找不到（测试进程即如此）：L() 落回中文 key，语言按中文算
    return ("zh-Hans", module)
}()

/// 协商选中的语言标签。诊断用（`POPSKILL_L10N_PROBE=1` 打印它）——
/// 形态随 SwiftPM 产物可能是 "zh-hans"，别拿它跟字面量比，用 l10nIsChinese
let l10nLang = l10n.lang

func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: l10n.bundle)
}

/// 语言标签是否中文。**绝不能拿协商结果跟 "zh-Hans" 裸比**（v2.14–2.18.0 潜伏
/// 三版的真 bug，坑 #22）：SwiftPM 把资源 bundle 里的 lproj 目录名小写成
/// `zh-hans`，`Bundle.localizations` 返回的是磁盘真实名，协商结果因此是
/// "zh-hans"——大小写敏感的 `==` 判 false，中文界面下 Catalog 精选目录
/// 整片走英文面。按语言码判定，与大小写/地区后缀/分隔符形态全无关。
func l10nLangIsChinese(_ lang: String) -> Bool {
    let l = lang.lowercased()
    return l == "zh" || l.hasPrefix("zh-") || l.hasPrefix("zh_")
}

/// 界面当前是否中文。内容级双语数据（Catalog 精选目录的 zh/en 简介）用它挑面，
/// 不走 L() 的资源表机制——几百条目录数据进 xcstrings 会把 catalog 变成垃圾场
let l10nIsChinese = l10nLangIsChinese(l10n.lang)

/// 与界面语言一致的 Locale——相对时间等格式化跟界面语言走，不跟系统区域
/// （曾硬编码 zh_CN，英文界面会蹦出中文日期）
let l10nLocale = Locale(identifier: l10nIsChinese ? "zh_CN" : l10n.lang)
