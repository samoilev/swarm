import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case russian = "ru"
    case english = "en"

    public static let storageKey = "appLanguage"
    public static let choiceCompletedKey = "appLanguageChoiceCompleted"
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

    public func formatted(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    /// The Mac's own interface language, resolved to one Swarm speaks.
    ///
    /// Used where Swarm's text sits inside a menu AppKit also writes into: the App
    /// menu's Hide/Quit items follow the Mac, not the language chosen in Swarm, so an
    /// "О Swarm" above an English "Quit Swarm" reads as a bug rather than a setting.
    public static func system(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        let codes = preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        // English for every Mac that isn't Russian: a French reader is better served by
        // the language they are more likely to share with the rest of the menu.
        return codes.first == russian.rawValue ? .russian : .english
    }

    public static var current: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey) else { return .default }
        return AppLanguage(rawValue: rawValue) ?? .default
    }

    public static func migrateLegacyPreferenceIfNeeded(
        currentDefaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: "com.familytreestudio.app")
    ) {
        guard currentDefaults.object(forKey: storageKey) == nil,
              let rawValue = legacyDefaults?.string(forKey: storageKey),
              AppLanguage(rawValue: rawValue) != nil else { return }
        currentDefaults.set(rawValue, forKey: storageKey)
    }

    public static func prepareInitialChoice(
        hasExistingLibrary: Bool,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.object(forKey: choiceCompletedKey) == nil else { return }
        if let raw = defaults.string(forKey: storageKey), AppLanguage(rawValue: raw) != nil {
            defaults.set(true, forKey: choiceCompletedKey)
        } else if hasExistingLibrary {
            defaults.set(AppLanguage.russian.rawValue, forKey: storageKey)
            defaults.set(true, forKey: choiceCompletedKey)
        }
    }
}

public enum L10n {
    public enum CountUnit: Sendable {
        case person
        case family
        case event
        case tree
        case generation
        case step
        case child
        case citation
        case photo
        case attachment
    }

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

    public static func tr(_ key: Key, language: AppLanguage) -> String {
        translated(key.value, arguments: key.arguments, language: language)
    }

    /// Locale-aware counted nouns used by generated interface copy. Keeping the
    /// grammar here prevents views from assembling English phrases from Russian
    /// abbreviations and eliminates singular strings such as “1 people”.
    public static func count(
        _ value: Int,
        _ unit: CountUnit,
        language: AppLanguage = .current
    ) -> String {
        switch language {
        case .english:
            let noun = switch unit {
            case .person: value == 1 ? "person" : "people"
            case .family: value == 1 ? "family" : "families"
            case .event: value == 1 ? "event" : "events"
            case .tree: value == 1 ? "tree" : "trees"
            case .generation: value == 1 ? "generation" : "generations"
            case .step: value == 1 ? "step" : "steps"
            case .child: value == 1 ? "child" : "children"
            case .citation: value == 1 ? "citation" : "citations"
            case .photo: value == 1 ? "photo" : "photos"
            case .attachment: value == 1 ? "attachment" : "attachments"
            }
            return "\(value) \(noun)"
        case .russian:
            let forms: (one: String, few: String, many: String) = switch unit {
            case .person: ("человек", "человека", "человек")
            case .family: ("семья", "семьи", "семей")
            case .event: ("событие", "события", "событий")
            case .tree: ("дерево", "дерева", "деревьев")
            case .generation: ("поколение", "поколения", "поколений")
            case .step: ("шаг", "шага", "шагов")
            case .child: ("ребёнок", "ребёнка", "детей")
            case .citation: ("ссылка на источник", "ссылки на источники", "ссылок на источники")
            // "фото" is indeclinable, so all three forms are the same word.
            case .photo: ("фото", "фото", "фото")
            case .attachment: ("вложение", "вложения", "вложений")
            }
            let absolute = abs(value)
            let lastTwo = absolute % 100
            let noun: String = if (11 ... 14).contains(lastTwo) {
                forms.many
            } else {
                switch absolute % 10 {
                case 1: forms.one
                case 2 ... 4: forms.few
                default: forms.many
                }
            }
            return "\(value) \(noun)"
        }
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
              let path = ResourceBundle.core.path(forResource: "en", ofType: "lproj"),
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

    /// "1st", "2nd", "13th". Shared with `KinshipFormatter`, which builds the same
    /// ordinals for cousin degrees and great-grandparent generations.
    static func englishOrdinal(_ value: Int) -> String {
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
