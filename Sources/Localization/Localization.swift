import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case english
    case simplifiedChinese

    var localizationIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return L10n.text("language.option.system_default")
        case .english:
            return L10n.text("language.option.english")
        case .simplifiedChinese:
            return L10n.text("language.option.simplified_chinese")
        }
    }
}

enum AppLanguagePreference {
    private static let defaultsKey = "appLanguage"

    static var current: AppLanguage {
        get {
            guard
                let value = UserDefaults.standard.string(forKey: defaultsKey),
                let language = AppLanguage(rawValue: value)
            else {
                return .system
            }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}

enum L10n {
    static func text(_ key: String, comment: String = "") -> String {
        NSLocalizedString(
            key,
            tableName: nil,
            bundle: localizationBundle,
            value: "",
            comment: comment
        )
    }

    static func format(_ key: String, _ arguments: CVarArg..., comment: String = "") -> String {
        String(
            format: text(key, comment: comment),
            locale: locale,
            arguments: arguments
        )
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    static func list(_ values: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }

    private static var locale: Locale {
        guard let identifier = AppLanguagePreference.current.localizationIdentifier else {
            return .current
        }
        return Locale(identifier: identifier)
    }

    private static var localizationBundle: Bundle {
        guard
            let identifier = AppLanguagePreference.current.localizationIdentifier,
            let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return .main
        }
        return bundle
    }
}
