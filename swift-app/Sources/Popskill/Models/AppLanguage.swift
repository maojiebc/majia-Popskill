import Foundation
import SwiftUI

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

    var localizationIdentifier: String {
        switch self {
        case .system:
            return Self.systemLocalizationIdentifier
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    var locale: Locale {
        Locale(identifier: localizationIdentifier)
    }

    static func fromStoredValue(_ value: String) -> AppLanguage {
        AppLanguage(rawValue: value) ?? .system
    }

    private static var systemLocalizationIdentifier: String {
        let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferredLanguage.hasPrefix("zh") ? "zh-Hans" : "en"
    }
}

struct PopskillLocalization: Equatable {
    let language: AppLanguage

    func string(_ key: String) -> String {
        Self.lookup(key, localization: language.localizationIdentifier)
    }

    func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: language.locale, arguments: arguments)
    }

    private static let fallbackLocalization = "en"
    private static var cachedTables: [String: [String: String]] = [:]
    private static let cacheLock = NSLock()

    private static func lookup(_ key: String, localization: String) -> String {
        let primary = table(for: localization)[key]
        let fallback = localization == fallbackLocalization ? nil : table(for: fallbackLocalization)[key]
        return primary ?? fallback ?? key
    }

    private static func table(for localization: String) -> [String: String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cachedTable = cachedTables[localization] {
            return cachedTable
        }

        let table = loadTable(for: localization)
        cachedTables[localization] = table
        return table
    }

    private static func loadTable(for localization: String) -> [String: String] {
        guard
            let path = Bundle.module.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: localization
            ),
            let table = NSDictionary(contentsOfFile: path) as? [String: String]
        else {
            return [:]
        }

        return table
    }
}

private struct PopskillLocalizationKey: EnvironmentKey {
    static let defaultValue = PopskillLocalization(language: .system)
}

extension EnvironmentValues {
    var popskillLocalization: PopskillLocalization {
        get { self[PopskillLocalizationKey.self] }
        set { self[PopskillLocalizationKey.self] = newValue }
    }
}

struct LocalizedText: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    @Environment(\.popskillLocalization) private var localization

    var body: some View {
        Text(localization.string(key))
    }
}
