import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system: "language.system"
        case .english: "language.english"
        case .simplifiedChinese: "language.simplifiedChinese"
        }
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }

    static func fromStoredValue(_ value: String) -> AppLanguage {
        AppLanguage(rawValue: value) ?? .system
    }
}
