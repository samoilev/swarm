import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case russian = "ru"
    case english = "en"

    public static let storageKey = "appLanguage"
    public static let `default` = AppLanguage.russian

    public var id: String { rawValue }
    public var locale: Locale { Locale(identifier: rawValue) }

    /// Language names stay in their own language so the setting remains readable
    /// even if the current interface language was selected accidentally.
    public var displayName: String {
        switch self {
        case .russian: "Русский"
        case .english: "English"
        }
    }

    public static var current: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey) else { return .default }
        return AppLanguage(rawValue: rawValue) ?? .default
    }
}

public enum L10n {
    public struct Key: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        fileprivate var value: String
        fileprivate var arguments: [CVarArg]

        public init(stringLiteral value: String) {
            self.value = value
            arguments = []
        }

        public init(stringInterpolation: StringInterpolation) {
            value = stringInterpolation.value
            arguments = stringInterpolation.arguments
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            fileprivate var value = ""
            fileprivate var arguments: [CVarArg] = []

            public init(literalCapacity: Int, interpolationCount: Int) {
                value.reserveCapacity(literalCapacity + interpolationCount * 2)
                arguments.reserveCapacity(interpolationCount)
            }

            public mutating func appendLiteral(_ literal: String) {
                value += literal.replacingOccurrences(of: "%", with: "%%")
            }

            public mutating func appendInterpolation(_ expression: some Any) {
                value += "%@"
                arguments.append(String(describing: expression) as NSString)
            }
        }
    }

    public static func tr(_ key: Key) -> String {
        translated(key.value, arguments: key.arguments, language: AppLanguage.current)
    }

    static func tr(_ key: Key, language: AppLanguage) -> String {
        translated(key.value, arguments: key.arguments, language: language)
    }

    /// Localizes strings produced by the domain layer after their values have
    /// already been assembled, such as relationship names.
    public static func dynamic(_ russian: String) -> String {
        translated(russian, arguments: [], language: AppLanguage.current)
    }

    static func dynamic(_ russian: String, language: AppLanguage) -> String {
        translated(russian, arguments: [], language: language)
    }

    private static func translated(_ russian: String, arguments: [CVarArg], language: AppLanguage) -> String {
        guard language == .english,
              let path = Bundle.module.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return arguments.isEmpty ? russian.replacingOccurrences(of: "%%", with: "%") : String(format: russian, arguments: arguments)
        }

        let translated = bundle.localizedString(forKey: russian, value: russian, table: nil)
        if !arguments.isEmpty { return String(format: translated, arguments: arguments) }
        if translated != russian { return translated }
        return translatedRuntimeString(russian)
    }

    private static func translatedRuntimeString(_ russian: String) -> String {
        if russian.hasPrefix("Через: ") { return "Via: " + russian.dropFirst("Через: ".count) }
        if let generation = leadingNumber(in: russian), russian.hasSuffix("-й предок") {
            return "\(englishOrdinal(generation))-generation ancestor"
        }
        if let generation = leadingNumber(in: russian), russian.hasSuffix("-й потомок") {
            return "\(englishOrdinal(generation))-generation descendant"
        }
        if let russianDegree = leadingNumber(in: russian), russian.contains("-юродн") {
            let degree = max(1, russianDegree - 1)
            let removed = russian.contains("племян") || russian.contains("дяд") || russian.contains("тёт")
            return "\(englishOrdinal(degree)) cousin" + (removed ? " once removed" : "")
        }
        return russian
    }

    private static func leadingNumber(in value: String) -> Int? {
        Int(value.prefix(while: \.isNumber))
    }

    private static func englishOrdinal(_ value: Int) -> String {
        let remainder100 = value % 100
        let suffix = if (11 ... 13).contains(remainder100) {
            "th"
        } else {
            switch value % 10 {
            case 1: "st"
            case 2: "nd"
            case 3: "rd"
            default: "th"
            }
        }
        return "\(value)\(suffix)"
    }
}
