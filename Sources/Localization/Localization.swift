import Foundation

enum L10n {
    static func text(_ key: String, comment: String = "") -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: "", comment: comment)
    }

    static func format(_ key: String, _ arguments: CVarArg..., comment: String = "") -> String {
        String(
            format: text(key, comment: comment),
            locale: Locale.current,
            arguments: arguments
        )
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(Locale.current))
    }

    static func list(_ values: [String]) -> String {
        ListFormatter.localizedString(byJoining: values)
    }
}
